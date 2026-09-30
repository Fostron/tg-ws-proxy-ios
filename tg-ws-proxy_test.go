package main

import (
	"net"
	"net/url"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestMain(m *testing.M) {
	initLogging(false)
	os.Exit(m.Run())
}

// The Worker dials dst with plain TCP, so it must get the DC's own MTProto
// address — never the WebSocket gateway from the DC->IP settings.
func TestWorkerDialTargetUsesRealDcAddress(t *testing.T) {
	dcOptMu.Lock()
	dcOpt = map[int]string{2: "149.154.167.220", 4: "149.154.167.220"}
	dcOptMu.Unlock()
	defer func() {
		dcOptMu.Lock()
		dcOpt = nil
		dcOptMu.Unlock()
	}()

	cases := []struct {
		dc      int
		isMedia bool
		wantDst string
	}{
		{2, false, "149.154.167.51"},
		{2, true, "149.154.167.51"},
		{4, false, "149.154.167.91"},
		{1, false, "149.154.175.50"},
		{203, true, "91.105.192.100"},
	}
	for _, c := range cases {
		host, path, ok := workerDialTarget("name-1234.user.workers.dev", c.dc, c.isMedia)
		if !ok {
			t.Fatalf("DC%d: workerDialTarget failed", c.dc)
		}
		if host != "name-1234.user.workers.dev" {
			t.Errorf("DC%d: host = %q", c.dc, host)
		}
		u, err := url.Parse("https://x" + path)
		if err != nil {
			t.Fatalf("DC%d: bad path %q: %v", c.dc, path, err)
		}
		if u.Path != "/apiws" {
			t.Errorf("DC%d: path = %q, want /apiws", c.dc, u.Path)
		}
		if got := u.Query().Get("dst"); got != c.wantDst {
			t.Errorf("DC%d media=%v: dst = %q, want %q", c.dc, c.isMedia, got, c.wantDst)
		}
	}
}

func TestWorkerDialTargetKeepsUserQuery(t *testing.T) {
	host, path, ok := workerDialTarget("https://w.example.workers.dev/relay?k=v", 5, false)
	if !ok || host != "w.example.workers.dev" {
		t.Fatalf("got host=%q ok=%v", host, ok)
	}
	if !strings.HasPrefix(path, "/relay?k=v&dst=149.154.171.5&dc=5") {
		t.Errorf("path = %q", path)
	}
	if _, _, ok := workerDialTarget("   ", 2, false); ok {
		t.Error("empty URL accepted")
	}
}

func TestParseCfUserDomains(t *testing.T) {
	got := parseCfUserDomains(" Example.com, b.org;c.net  example.com.\n")
	want := []string{"example.com", "b.org", "c.net"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

// Several own domains used to collapse into one bogus "a.com, b.com" entry
// the moment StartProxy re-initialised the domain list.
func TestInitCfproxyDomainsSplitsUserList(t *testing.T) {
	cfproxyMu.Lock()
	cfproxyUserDomain = "one.example, two.example"
	cfproxyCacheDir = ""
	cfproxyMu.Unlock()
	defer func() {
		cfproxyMu.Lock()
		cfproxyUserDomain = ""
		cfproxyMu.Unlock()
	}()

	initCfproxyDomains()

	cfproxyMu.RLock()
	defer cfproxyMu.RUnlock()
	if want := []string{"one.example", "two.example"}; !reflect.DeepEqual(cfproxyDomains, want) {
		t.Errorf("cfproxyDomains = %v, want %v", cfproxyDomains, want)
	}
	if activeCfDomain != "one.example" {
		t.Errorf("activeCfDomain = %q", activeCfDomain)
	}
}

// Same decoding as upstream's _dd() in proxy/config.py.
func TestDefaultCfDomainsMatchUpstream(t *testing.T) {
	got := defaultCfproxyDomains()
	if len(got) != len(cfproxyEnc) {
		t.Fatalf("decoded %d of %d built-in domains", len(got), len(cfproxyEnc))
	}
	want := []string{"pclead.co.uk", "offshor.co.uk", "cakeisalie.co.uk"}
	if !reflect.DeepEqual(got[:3], want) {
		t.Errorf("got %v, want %v", got[:3], want)
	}
}

func TestLooksDead(t *testing.T) {
	cases := []struct {
		name string
		r    bridgeResult
		want bool
	}{
		{"answered", bridgeResult{up: 500, down: 300, elapsed: time.Minute}, false},
		{"client left fast", bridgeResult{up: 500, elapsed: 2 * time.Second}, false},
		{"nothing sent", bridgeResult{elapsed: time.Minute, upstreamEnded: true}, false},
		{"upstream hung up silent", bridgeResult{up: 500, elapsed: 300 * time.Millisecond, upstreamEnded: true}, true},
		{"silence", bridgeResult{up: 500, elapsed: 15 * time.Second}, true},
	}
	for _, c := range cases {
		if got := c.r.looksDead(); got != c.want {
			t.Errorf("%s: looksDead = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestTierCooldown(t *testing.T) {
	resetTierCooldowns()
	defer resetTierCooldowns()

	dead := bridgeResult{up: 64, upstreamEnded: true}
	alive := bridgeResult{up: 64, down: 128, elapsed: time.Second}

	for i := 1; i < deadStrikesToDisable; i++ {
		judgeSession(tierWorker, 2, false, dead)
		if _, cooling := tierCoolingDown(tierWorker, 2, false); cooling {
			t.Fatalf("route disabled after only %d dead session(s)", i)
		}
	}
	judgeSession(tierWorker, 2, false, dead)
	if _, cooling := tierCoolingDown(tierWorker, 2, false); !cooling {
		t.Fatalf("%d dead sessions in a row didn't disable the route", deadStrikesToDisable)
	}
	if _, cooling := tierCoolingDown(tierWorker, 4, false); cooling {
		t.Error("cooldown leaked to another DC")
	}
	judgeSession(tierWorker, 2, false, alive)
	if _, cooling := tierCoolingDown(tierWorker, 2, false); cooling {
		t.Error("a working session didn't clear the cooldown")
	}
}

// A working CDN that has the odd silent session (the case in the field log)
// must never get switched off.
func TestTierStrikesResetBySuccess(t *testing.T) {
	resetTierCooldowns()
	defer resetTierCooldowns()

	dead := bridgeResult{up: 2500, elapsed: 12 * time.Second}
	alive := bridgeResult{up: 300, down: 90000, elapsed: 4 * time.Second}
	for i := 0; i < 10; i++ {
		judgeSession(tierCdn, 2, false, dead)
		judgeSession(tierCdn, 2, false, dead)
		judgeSession(tierCdn, 2, false, alive)
	}
	if _, cooling := tierCoolingDown(tierCdn, 2, false); cooling {
		t.Error("a mostly-working CDN route was disabled")
	}
}

func TestSummaryHasExactByteCounts(t *testing.T) {
	stats.Reset()
	defer stats.Reset()
	stats.bytesUp.Add(123456)
	stats.bytesDown.Add(7890123)
	s := stats.Summary()
	if !strings.Contains(s, " upb=123456 ") || !strings.HasSuffix(s, " downb=7890123") {
		t.Errorf("summary = %q", s)
	}
}

func TestReadProxyProtocolV1(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	go func() {
		_, _ = client.Write([]byte("PROXY TCP4 203.0.113.7 10.0.0.2 51234 1443\r\nX"))
	}()

	peer, err := readProxyProtocolV1(server)
	if err != nil {
		t.Fatal(err)
	}
	if peer != "203.0.113.7:51234" {
		t.Errorf("peer = %q", peer)
	}
	// The byte after the header must still be there for the MTProto reader.
	b := make([]byte, 1)
	if _, err := server.Read(b); err != nil || b[0] != 'X' {
		t.Errorf("next byte = %q, err %v", b, err)
	}
}

func TestReadProxyProtocolV1RejectsMissingHeader(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	go func() {
		_, _ = client.Write([]byte("\xef\xef\xef\xef not a proxy header\n"))
	}()
	if _, err := readProxyProtocolV1(server); err == nil {
		t.Error("accepted a connection without PROXY header")
	}
}

func TestFailedBeforeConnect(t *testing.T) {
	if !failedBeforeConnect(&net.DNSError{Err: "no such host", Name: "x"}) {
		t.Error("DNS error should allow a DoH retry")
	}
	if !failedBeforeConnect(&net.OpError{Op: "dial", Err: os.ErrDeadlineExceeded}) {
		t.Error("dial error should allow a DoH retry")
	}
	if failedBeforeConnect(&WsHandshakeError{StatusCode: 403}) {
		t.Error("an HTTP answer already came from Cloudflare; DoH can't help")
	}
}
