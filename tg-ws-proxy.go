package main

/*
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#ifdef __APPLE__
#include <os/log.h>
#endif

static void iosLogProxy(const char *msg) {
#ifdef __APPLE__
    os_log(OS_LOG_DEFAULT, "[TgWsProxy] %{public}s", msg);
#else
    fprintf(stderr, "[TgWsProxy] %s\n", msg);
#endif
}
*/
import "C"

import (
	"bufio"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net"
	"net/http"
	"net/url"

	utls "github.com/refraction-networking/utls"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

// ---------------------------------------------------------------------------
// Constants & Configuration
// ---------------------------------------------------------------------------

const (
	defaultPort    = 1443
	tcpNodelay     = true
	defaultRecvBuf = 256 * 1024
	defaultSendBuf = 256 * 1024
	defaultPoolSz  = 4

	wsPoolMaxAge = 120.0

	// Same cooldowns upstream uses: a handshake error (non-302) only shortens
	// the next Direct attempt, while a timeout or a session that never got a
	// single byte back takes Direct out of rotation for that DC entirely.
	dcFailCooldown = 60.0
	ipFailCooldown = 600.0

	wsFailTimeout   = 2.0
	wsDirectTimeout = 5.0

	// A relayed session that carried client data but never got one byte back
	// is what DPI dropping a "connected" route looks like — and also what a
	// Worker dialing the wrong address looks like. Either the upstream side
	// hung up on us, or it sat silent at least this long.
	deadSessionMinSilence = 8 * time.Second
	deadRouteCooldown     = 10 * time.Minute

	poolMaintainInterval = 5

	// Bridge read deadlines — short enough to detect dead connections on mobile
	bridgeReadTimeout  = 2 * time.Minute
	bridgePingInterval = 30 * time.Second
	wsWriteTimeout     = 5 * time.Second
	wsControlTimeout   = 2 * time.Second
	wsPoolProbeTimeout = 1200 * time.Millisecond
	wsPoolProbeAfter   = 8.0
	wsBridgeChunkSize  = 64 * 1024
	pooledFrameCap     = wsBridgeChunkSize + 32

	wsPoolReuseMaxAge = 30.0

	cfproxyCacheFileName    = "cfproxy-domains-cache.txt"
	cfproxyActiveFileName   = "cfproxy-active-domain.txt"
	cfproxyRefreshInterval = 12 * time.Hour
	// Upstream gives both Cloudflare tiers 10s per attempt: the edge TLS+WS
	// handshake on a mobile link regularly needs more than 3-4s, and cutting
	// it shorter made every attempt abort before the 101 ever arrived.
	cfproxyDialTimeout  = 10 * time.Second
	cfWorkerDialTimeout = 10 * time.Second
	// Whole-tier budget, so a blocked Cloudflare costs each Telegram
	// connection at most this long before the next tier gets a turn instead
	// of walking all ~20 public domains one timeout at a time.
	cfTierBudget            = 20 * time.Second
	cfproxyFallbackParallel = 2
	cfproxy429Cooldown      = 45 * time.Second
	cfproxy429MaxCooldown   = 5 * time.Minute
	cfproxyGlobalParallel   = 4
)

var (
	recvBuf    = defaultRecvBuf
	sendBuf    = defaultSendBuf
	poolSize   atomic.Int32
	logVerbose = false
)

type cfproxy429State struct {
	until   time.Time
	strikes int
}

func init() {
	poolSize.Store(defaultPoolSz)
}

// Cloudflare proxy config
var (
	cfproxyEnabled    = true
	cfproxyUserDomain = ""
	// Domains the user typed in Settings. The fetched list is obfuscated
	// (".com" entries Caesar-decode to ".co.uk"), but a user's own domain is
	// literal — decoding it would mangle it, and the ".co.uk" requirement
	// would reject every other TLD outright. Upstream applies no TLD
	// restriction at all, so neither should we.
	cfproxyUserDomainSet    = map[string]bool{}
	cfproxyUserDomainMu     sync.RWMutex
	cfproxyDomains          []string
	activeCfDomain          string
	cfproxyCacheDir         = ""
	cfproxyMu               sync.RWMutex
	cfproxy429StateByDomain = make(map[string]cfproxy429State)
	cfproxy429Mu            sync.RWMutex
	cfproxyAttemptSem       = make(chan struct{}, cfproxyGlobalParallel)
)

// Cloudflare Worker config — an independent routing tier from the CF CDN
// (cfproxy) fleet above. In the fallback chain it goes first, as upstream
// does: Worker -> CDN -> raw TCP.
var (
	cfWorkerEnabled = false
	cfWorkerURL     = ""
	// Parsed form of cfWorkerURL: upstream lets several worker domains be
	// listed comma-separated so one dead worker doesn't kill the tier.
	cfWorkerURLs []string
	cfWorkerMu   sync.RWMutex
	cfWorkerSem  = make(chan struct{}, cfproxyGlobalParallel)
)

// Which route a new connection tries first. Auto is upstream's behaviour:
// Direct WS for DCs that have an address configured, everything else (and
// every Direct failure) goes down the fallback chain. The other two modes
// put one Cloudflare tier in front of Direct.
const (
	routeAuto        = 0
	routeCdnFirst    = 1
	routeWorkerFirst = 2
)

var (
	routeMode   = routeAuto
	routeModeMu sync.RWMutex
)

func currentRouteMode() int {
	routeModeMu.RLock()
	defer routeModeMu.RUnlock()
	return routeMode
}

// Routes a connection can take. Used to key per-DC cooldowns for routes that
// have just proven dead, so the next connection skips straight past them.
const (
	tierDirect = "direct"
	tierCdn    = "cdn"
	tierWorker = "worker"
)

type tierKey struct {
	tier    string
	dc      int
	isMedia bool
}

var (
	tierFailMu    sync.Mutex
	tierFailUntil = make(map[tierKey]time.Time)
	// Dead sessions in a row since the route last carried data. One silent
	// session isn't enough to condemn a route: Telegram opens several
	// connections in parallel and some just idle out, and switching a working
	// CDN off for 10 minutes over that is worse than the silence itself.
	tierStrikes = make(map[tierKey]int)
)

const deadStrikesToDisable = 3

// noteDeadSession counts one silent session against the route and reports
// whether that was the strike that switched it off.
func noteDeadSession(tier string, dc int, isMedia bool) (int, bool) {
	key := tierKey{tier, dc, isMedia}
	tierFailMu.Lock()
	defer tierFailMu.Unlock()
	tierStrikes[key]++
	strikes := tierStrikes[key]
	if strikes < deadStrikesToDisable {
		return strikes, false
	}
	delete(tierStrikes, key)
	tierFailUntil[key] = time.Now().Add(deadRouteCooldown)
	return strikes, true
}

func tierCoolingDown(tier string, dc int, isMedia bool) (time.Duration, bool) {
	tierFailMu.Lock()
	defer tierFailMu.Unlock()
	until, ok := tierFailUntil[tierKey{tier, dc, isMedia}]
	if !ok {
		return 0, false
	}
	remaining := time.Until(until)
	if remaining <= 0 {
		delete(tierFailUntil, tierKey{tier, dc, isMedia})
		return 0, false
	}
	return remaining, true
}

func markTierDead(tier string, dc int, isMedia bool, d time.Duration) {
	tierFailMu.Lock()
	tierFailUntil[tierKey{tier, dc, isMedia}] = time.Now().Add(d)
	tierFailMu.Unlock()
}

func clearTierDead(tier string, dc int, isMedia bool) {
	tierFailMu.Lock()
	delete(tierFailUntil, tierKey{tier, dc, isMedia})
	delete(tierStrikes, tierKey{tier, dc, isMedia})
	tierFailMu.Unlock()
}

func resetTierCooldowns() {
	tierFailMu.Lock()
	tierFailUntil = make(map[tierKey]time.Time)
	tierStrikes = make(map[tierKey]int)
	tierFailMu.Unlock()
}

func tierName(tier string) string {
	switch tier {
	case tierDirect:
		return "Direct"
	case tierCdn:
		return "CDN"
	case tierWorker:
		return "Worker"
	}
	return tier
}

// bridgeResult is how a relayed session ended, so the caller can tell a
// working route from one that swallowed the client's data without answering.
type bridgeResult struct {
	up, down      int64
	elapsed       time.Duration
	upstreamEnded bool
}

func (r bridgeResult) looksDead() bool {
	return r.up > 0 && r.down == 0 && (r.upstreamEnded || r.elapsed >= deadSessionMinSilence)
}

// judgeSession updates the route's health from how its session went. A dead
// session can't be retried in place — the client's bytes are spent — but
// Telegram reconnects right away, and that next connection now skips this
// route instead of hanging on it again.
func judgeSession(tier string, dc int, isMedia bool, r bridgeResult) {
	mTag := mediaTag(isMedia)
	if !r.looksDead() {
		if r.down > 0 {
			clearTierDead(tier, dc, isMedia)
		}
		return
	}
	why := "сервер закрыл соединение"
	if !r.upstreamEnded {
		why = fmt.Sprintf("тишина %.0fс", r.elapsed.Seconds())
	}
	strikes, disabled := noteDeadSession(tier, dc, isMedia)
	if !disabled {
		logDebug.Printf(" DC%d%s: %s принял %s и не вернул ни байта (%s) — %d из %d до отключения",
			dc, mTag, tierName(tier), humanBytes(r.up), why, strikes, deadStrikesToDisable)
		return
	}
	logWarn.Printf(" DC%d%s: %s %d раза подряд не вернул ни байта (последний раз %s, %s) — маршрут отключён на %.0f мин",
		dc, mTag, tierName(tier), strikes, humanBytes(r.up), why, deadRouteCooldown.Minutes())
	if tier == tierWorker {
		logWarn.Printf(" DC%d%s: Worker отвечает, но Telegram за ним молчит — разверните свежий tgwsproxy-worker.js (старый терял все данные на новых Worker'ах) и посмотрите Workers → Logs: up=0B значит, что данные не доходят до Worker", dc, mTag)
	}
}

const cfproxyDomainsURL = "https://raw.githubusercontent.com/Flowseal/tg-ws-proxy/main/.github/cfproxy-domains.txt"

// MTProto proxy secret (hex, 32 chars = 16 bytes)
var (
	proxySecret   = "00000000000000000000000000000000"
	proxySecretMu sync.RWMutex
)

// FakeTLS config (ee-secret). Only meaningful when clients reach the proxy
// across a censored network — i.e. the app runs as a server behind nginx
// (see SetProxyProtocol). Between Telegram and 127.0.0.1 there's no DPI.
var (
	fakeTlsEnabled = false
	fakeTlsDomain  = ""
	// Where a connection that fails the FakeTLS check is forwarded, so an
	// active prober sees a real website instead of a dead socket. Empty means
	// "just close it": masking to fakeTlsDomain itself would loop straight
	// back through nginx (which routes that SNI here) into this proxy.
	fakeTlsMaskHost = ""
	fakeTlsMu       sync.RWMutex
)

// PROXY protocol v1 (nginx `proxy_protocol on;`). When on, every accepted
// connection must start with a "PROXY ..." line carrying the real client
// address; without it all clients would look like the nginx host.
var (
	proxyProtocolEnabled = false
	proxyProtocolMu      sync.RWMutex
)

// DNS over HTTPS (DoH) Cache and Clients
type dohCacheEntry struct {
	ip  string
	exp time.Time
}

var (
	dohCache  sync.Map
	dohClient = &http.Client{
		Timeout: 1500 * time.Millisecond,
		Transport: &http.Transport{
			MaxIdleConns:        10,
			IdleConnTimeout:     90 * time.Second,
			TLSHandshakeTimeout: 1 * time.Second,
		},
	}
	githubClient = &http.Client{
		Timeout: 10 * time.Second,
	}
)

func connectOneWS(ctx context.Context, ip string, domains []string) *RawWebSocket {
	for _, d := range domains {
		ws, err := wsConnect(ctx, ip, d, "/apiws", 5.0)
		if err == nil {
			return ws
		}
	}
	return nil
}

// The DCs' own addresses, which speak raw obfuscated MTProto on :443. Every
// route that ends in a plain TCP connection to Telegram — the TCP fallback
// and the Worker, which is just a remote TCP dialer — must use these. The
// user's DC->IP settings (149.154.167.220 by default) point at the
// kwsN.web.telegram.org WebSocket gateway instead: a TLS server that drops
// raw MTProto on the floor.
var dcDefaultIPs = map[int]string{
	1:   "149.154.175.50",
	2:   "149.154.167.51",
	3:   "149.154.175.100",
	4:   "149.154.167.91",
	5:   "149.154.171.5",
	203: "91.105.192.100",
}

func resolveConfiguredTarget(dc int, isMedia bool) (string, bool) {
	dcOptMu.RLock()
	defer dcOptMu.RUnlock()

	if isMedia {
		if target, ok := dcOpt[-dc]; ok && target != "" {
			return target, true
		}
	}
	if target, ok := dcOpt[dc]; ok && target != "" {
		return target, true
	}
	return "", false
}

func resolveFallbackTarget(dc int, isMedia bool) string {
	return dcDefaultIPs[dc]
}

// ---------------------------------------------------------------------------
// Logger
// ---------------------------------------------------------------------------

var (
	logInfo  *log.Logger
	logWarn  *log.Logger
	logError *log.Logger
	logDebug *log.Logger
)

type iosLogWriter struct{}

const logRingCap = 500

var (
	logRingMu sync.Mutex
	logRing   []string
)

func (w iosLogWriter) Write(p []byte) (n int, err error) {
	_, _ = os.Stderr.Write(p)
	cs := C.CString(string(p))
	C.iosLogProxy(cs)
	C.free(unsafe.Pointer(cs))

	line := strings.TrimRight(string(p), "\n")
	if line != "" {
		logRingMu.Lock()
		logRing = append(logRing, line)
		if len(logRing) > logRingCap {
			logRing = logRing[len(logRing)-logRingCap:]
		}
		logRingMu.Unlock()
	}

	return len(p), nil
}

func initLogging(verbose bool) {
	logVerbose = verbose
	flags := 0
	out := iosLogWriter{}
	logInfo = log.New(out, "", flags)
	logWarn = log.New(out, "[WARN] ", flags)
	logError = log.New(out, "[ERROR] ", flags)
	if verbose {
		logDebug = log.New(out, "[DEBUG] ", flags)
	} else {
		logDebug = log.New(io.Discard, "", 0)
	}
	signal.Ignore(syscall.SIGPIPE)
}

// ---------------------------------------------------------------------------
// Cloudflare proxy domain decoding
// ---------------------------------------------------------------------------

// Same built-in list upstream ships (proxy/config.py); the live list is still
// refreshed from GitHub on top of this.
var cfproxyEnc = []string{
	"virkgj.com", "vmmzovy.com", "mkuosckvso.com", "zaewayzmplad.com", "twdmbzcm.com",
	"awzwsldi.com", "clngqrflngqin.com", "tjacxbqtj.com", "bxaxtxmrw.com", "dmohrsgmohcrwb.com",
	"vwbmtmoi.com", "khgrre.com", "ulihssf.com", "tmhqsdqmfpmk.com", "xwuwoqbm.com",
	"orgcnunpj.com", "zhkuldz.com", "zypoljnslxa.com", "efabnxaowuzs.com", "zaftuzsftqdq.com",
}

// parseCfUserDomains splits the "own domain" setting the way upstream's
// coerce_domain_list does: comma, semicolon or whitespace separated,
// lowercased, de-duplicated, order kept.
func parseCfUserDomains(raw string) []string {
	fields := strings.FieldsFunc(raw, func(r rune) bool {
		return r == ',' || r == ';' || r == ' ' || r == '\t' || r == '\n' || r == '\r'
	})
	var list []string
	seen := map[string]bool{}
	for _, part := range fields {
		d := strings.ToLower(strings.TrimSpace(part))
		d = strings.TrimSuffix(d, ".")
		if d == "" || seen[d] {
			continue
		}
		seen[d] = true
		list = append(list, d)
	}
	return list
}

func decodeCfDomain(s string) string {
	if !strings.HasSuffix(s, ".com") {
		return s
	}
	suffix := string([]byte{46, 99, 111, 46, 117, 107})
	p := s[:len(s)-4]
	n := 0
	for _, c := range p {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			n++
		}
	}
	var result []byte
	for _, c := range []byte(p) {
		if c >= 'a' && c <= 'z' {
			result = append(result, byte((int(c-'a')-n%26+26)%26+'a'))
		} else if c >= 'A' && c <= 'Z' {
			result = append(result, byte((int(c-'A')-n%26+26)%26+'A'))
		} else {
			result = append(result, c)
		}
	}
	return string(result) + suffix
}

func normalizeCfDomain(s string) string {
	trimmed := strings.ToLower(strings.TrimSpace(s))
	trimmed = strings.TrimSuffix(trimmed, ".")
	if trimmed == "" {
		return ""
	}

	// Deliberately NOT cfproxyMu: normalizeCfDomain is called from paths that
	// already hold it (setActiveCfproxyDomainLocked), and Go's RWMutex isn't
	// reentrant — taking it here deadlocked the whole CDN tier.
	cfproxyUserDomainMu.RLock()
	isUser := cfproxyUserDomainSet[trimmed]
	cfproxyUserDomainMu.RUnlock()

	if isUser {
		// Any TLD is fine; just reject obviously malformed input.
		if strings.Contains(trimmed, "://") || strings.Contains(trimmed, "/") ||
			!strings.Contains(trimmed, ".") {
			return ""
		}
		return trimmed
	}

	d := strings.ToLower(strings.TrimSpace(decodeCfDomain(s)))
	d = strings.TrimSuffix(d, ".")
	if d == "" || !strings.HasSuffix(d, ".co.uk") {
		return ""
	}
	return d
}

func defaultCfproxyDomains() []string {
	domains := make([]string, 0, len(cfproxyEnc))
	for _, enc := range cfproxyEnc {
		if domain := normalizeCfDomain(enc); domain != "" {
			domains = append(domains, domain)
		}
	}
	return domains
}

func mergeCfproxyDomains(lists ...[]string) []string {
	seen := make(map[string]struct{})
	merged := make([]string, 0)
	for _, list := range lists {
		for _, raw := range list {
			domain := normalizeCfDomain(raw)
			if domain == "" {
				continue
			}
			if _, ok := seen[domain]; ok {
				continue
			}
			seen[domain] = struct{}{}
			merged = append(merged, domain)
		}
	}
	return merged
}

func clearCfproxy429Cooldowns() {
	cfproxy429Mu.Lock()
	cfproxy429StateByDomain = make(map[string]cfproxy429State)
	cfproxy429Mu.Unlock()
}

func clearCfproxy429Cooldown(domain string) {
	domain = normalizeCfDomain(domain)
	if domain == "" {
		return
	}

	cfproxy429Mu.Lock()
	delete(cfproxy429StateByDomain, domain)
	cfproxy429Mu.Unlock()
}

func retryAfterDelay(err error) time.Duration {
	var wsErr *WsHandshakeError
	if !errors.As(err, &wsErr) || wsErr == nil {
		return 0
	}

	retryAfter := strings.TrimSpace(wsErr.Headers["retry-after"])
	if retryAfter == "" {
		return 0
	}

	if seconds, convErr := strconv.Atoi(retryAfter); convErr == nil && seconds > 0 {
		return time.Duration(seconds) * time.Second
	}

	if when, convErr := http.ParseTime(retryAfter); convErr == nil {
		if delay := time.Until(when); delay > 0 {
			return delay
		}
	}

	return 0
}

func nextCfproxy429CooldownDelay(prev cfproxy429State, retryAfter time.Duration) time.Duration {
	if retryAfter > 0 {
		if retryAfter > cfproxy429MaxCooldown {
			return cfproxy429MaxCooldown
		}
		return retryAfter
	}

	strikes := prev.strikes
	if prev.until.IsZero() || time.Since(prev.until) > cfproxy429MaxCooldown {
		strikes = 0
	}

	delay := cfproxy429Cooldown
	for i := 0; i < strikes; i++ {
		delay *= 2
		if delay >= cfproxy429MaxCooldown {
			return cfproxy429MaxCooldown
		}
	}

	if delay > cfproxy429MaxCooldown {
		return cfproxy429MaxCooldown
	}
	return delay
}

func markCfproxy429Cooldown(domain string, err error) {
	domain = normalizeCfDomain(domain)
	if domain == "" {
		return
	}

	retryAfter := retryAfterDelay(err)
	cfproxy429Mu.Lock()
	prev := cfproxy429StateByDomain[domain]
	delay := nextCfproxy429CooldownDelay(prev, retryAfter)
	strikes := prev.strikes + 1
	if prev.until.IsZero() || time.Since(prev.until) > cfproxy429MaxCooldown {
		strikes = 1
	}
	cfproxy429StateByDomain[domain] = cfproxy429State{
		until:   time.Now().Add(delay),
		strikes: strikes,
	}
	cfproxy429Mu.Unlock()

	logDebug.Printf(" CF cooldown %s: %.0fs after 429", domain, math.Ceil(delay.Seconds()))
}

func cfproxy429CooldownRemaining(domain string) time.Duration {
	domain = normalizeCfDomain(domain)
	if domain == "" {
		return 0
	}

	cfproxy429Mu.RLock()
	state, ok := cfproxy429StateByDomain[domain]
	cfproxy429Mu.RUnlock()
	if !ok {
		return 0
	}

	remaining := time.Until(state.until)
	if remaining <= 0 {
		cfproxy429Mu.Lock()
		delete(cfproxy429StateByDomain, domain)
		cfproxy429Mu.Unlock()
		return 0
	}
	return remaining
}

func acquireCfproxyAttemptSlot(ctx context.Context) bool {
	select {
	case cfproxyAttemptSem <- struct{}{}:
		return true
	case <-ctx.Done():
		return false
	}
}

func releaseCfproxyAttemptSlot() {
	select {
	case <-cfproxyAttemptSem:
	default:
	}
}

func cfproxyCachePath() string {
	cfproxyMu.RLock()
	cacheDir := strings.TrimSpace(cfproxyCacheDir)
	cfproxyMu.RUnlock()
	if cacheDir == "" {
		return ""
	}
	return filepath.Join(cacheDir, cfproxyCacheFileName)
}

func cfproxyActiveDomainPath() string {
	cfproxyMu.RLock()
	cacheDir := strings.TrimSpace(cfproxyCacheDir)
	cfproxyMu.RUnlock()
	if cacheDir == "" {
		return ""
	}
	return filepath.Join(cacheDir, cfproxyActiveFileName)
}

func loadCfproxyDomainsFromCache() []string {
	cachePath := cfproxyCachePath()
	if cachePath == "" {
		return nil
	}

	data, err := os.ReadFile(cachePath)
	if err != nil {
		return nil
	}

	return mergeCfproxyDomains(strings.Split(string(data), "\n"))
}

func loadActiveCfproxyDomain() string {
	activePath := cfproxyActiveDomainPath()
	if activePath == "" {
		return ""
	}

	data, err := os.ReadFile(activePath)
	if err != nil {
		return ""
	}
	return normalizeCfDomain(string(data))
}

func saveCfproxyDomainsToCache(domains []string) {
	cachePath := cfproxyCachePath()
	if cachePath == "" || len(domains) == 0 {
		return
	}

	if err := os.MkdirAll(filepath.Dir(cachePath), 0o755); err != nil {
		logDebug.Printf(" CF: кеш создать не удалось: %s", err)
		return
	}

	data := strings.Join(domains, "\n")
	if err := os.WriteFile(cachePath, []byte(data), 0o644); err != nil {
		logDebug.Printf(" CF: кеш сохранить не удалось: %s", err)
	}
}

func saveActiveCfproxyDomain(domain string) {
	activePath := cfproxyActiveDomainPath()
	domain = normalizeCfDomain(domain)
	if activePath == "" || domain == "" {
		return
	}

	if err := os.MkdirAll(filepath.Dir(activePath), 0o755); err != nil {
		logDebug.Printf(" CF: active-domain кеш создать не удалось: %s", err)
		return
	}

	if err := os.WriteFile(activePath, []byte(domain), 0o644); err != nil {
		logDebug.Printf(" CF: active-domain кеш сохранить не удалось: %s", err)
	}
}

func shouldRefreshCfproxyDomains() bool {
	cachePath := cfproxyCachePath()
	if cachePath == "" {
		return true
	}

	info, err := os.Stat(cachePath)
	if err != nil {
		return true
	}

	return time.Since(info.ModTime()) >= cfproxyRefreshInterval
}

func setActiveCfproxyDomainLocked(preferred string) {
	if len(cfproxyDomains) == 0 {
		activeCfDomain = ""
		return
	}
	preferred = normalizeCfDomain(preferred)
	for _, domain := range cfproxyDomains {
		if domain == preferred {
			activeCfDomain = domain
			return
		}
	}
	activeCfDomain = cfproxyDomains[0]
}

func initCfproxyDomains() {
	defaults := defaultCfproxyDomains()
	cached := loadCfproxyDomainsFromCache()
	persistedActive := loadActiveCfproxyDomain()

	cfproxyMu.Lock()
	defer cfproxyMu.Unlock()
	if cfproxyUserDomain != "" {
		// The raw setting may hold several comma-separated domains; using it
		// verbatim produced a single bogus "a.com, b.com" entry.
		if list := parseCfUserDomains(cfproxyUserDomain); len(list) > 0 {
			cfproxyDomains = list
			activeCfDomain = list[0]
			return
		}
	}

	if len(cached) > 0 {
		cfproxyDomains = mergeCfproxyDomains(cached, defaults)
		logInfo.Printf(" CF: кеш доменов загружен (%d шт.)", len(cached))
	} else {
		cfproxyDomains = defaults
	}
	setActiveCfproxyDomainLocked(persistedActive)
}

func startCfproxyRefresh(ctx context.Context) {
	if !shouldRefreshCfproxyDomains() {
		logDebug.Printf(" CF: кеш свежий, пропускаю обновление списка")
		return
	}

	go func() {
		for i := 0; i < 3; i++ {
			if tryRefreshCfproxyDomains(ctx) {
				return
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(10 * time.Second):
				continue
			}
		}
		logDebug.Printf(" CF: обновить список доменов не удалось, остаюсь на кеше/встроенном списке")
	}()
}

func tryRefreshCfproxyDomains(ctx context.Context) bool {
	cfproxyMu.RLock()
	hasUserDomain := cfproxyUserDomain != ""
	cfproxyMu.RUnlock()
	if hasUserDomain {
		return true
	}

	req, err := http.NewRequestWithContext(ctx, "GET", cfproxyDomainsURL, nil)
	if err != nil {
		return false
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 tg-ws-proxy-ios")

	resp, err := githubClient.Do(req)
	if err != nil {
		logDebug.Printf(" CF: GitHub недоступен: %s", err)
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		logDebug.Printf(" CF: GitHub вернул %d", resp.StatusCode)
		return false
	}

	var newDomains []string
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if domain := normalizeCfDomain(line); domain != "" {
			newDomains = append(newDomains, domain)
		}
	}
	if err := scanner.Err(); err != nil {
		logDebug.Printf(" CF: список доменов прочитать не удалось: %s", err)
		return false
	}

	if len(newDomains) > 0 {
		merged := mergeCfproxyDomains(newDomains, defaultCfproxyDomains())
		cfproxyMu.Lock()
		if cfproxyUserDomain != "" {
			cfproxyMu.Unlock()
			return true
		}
		currentActive := activeCfDomain
		cfproxyDomains = merged
		setActiveCfproxyDomainLocked(currentActive)
		cfproxyMu.Unlock()

		saveCfproxyDomainsToCache(merged)
		logInfo.Printf(" CF: список доменов обновлен (%d шт.)", len(newDomains))
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// Telegram IP ranges & DC mapping
// ---------------------------------------------------------------------------

var validProtos = map[uint32]bool{
	0xEFEFEFEF: true,
	0xEEEEEEEE: true,
	0xDDDDDDDD: true,
}

// Only for the web.telegram.org gateway hostnames (wsDomains): DC203 has no
// kws203.web.telegram.org and is served under kws2. The Cloudflare tier is
// different — its kwsN records are the user's own, and the setup guide
// creates kws203 pointing at DC203 itself.
var dcOverrides = map[int]int{
	203: 2,
}

// ---------------------------------------------------------------------------
// Global state
// ---------------------------------------------------------------------------

var (
	dcOpt   map[int]string
	dcOptMu sync.RWMutex

	wsBlackMu   sync.RWMutex
	wsBlacklist = make(map[[2]int]bool)

	dcFailMu    sync.RWMutex
	dcFailUntil = make(map[[2]int]float64)

	zero64 = make([]byte, 64)
)

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

type Stats struct {
	connectionsTotal       atomic.Int64
	connectionsActive      atomic.Int64
	connectionsWs          atomic.Int64
	connectionsTcpFallback atomic.Int64
	connectionsCfproxy     atomic.Int64
	connectionsCfWorker    atomic.Int64
	connectionsHttpReject  atomic.Int64
	connectionsPassthrough atomic.Int64
	connectionsBad         atomic.Int64
	wsErrors               atomic.Int64
	bytesUp                atomic.Int64
	bytesDown              atomic.Int64
	poolHits               atomic.Int64
	poolMisses             atomic.Int64
}

func (s *Stats) Summary() string {
	ph := s.poolHits.Load()
	pm := s.poolMisses.Load()
	return fmt.Sprintf(
		// upb/downb are exact byte counts: the app derives live speeds from
		// them, which the rounded up/down strings are far too coarse for.
		"total=%d active=%d ws=%d tcp_fb=%d cf=%d cfw=%d bad=%d err=%d pool=%d/%d up=%s down=%s upb=%d downb=%d",
		s.connectionsTotal.Load(), s.connectionsActive.Load(), s.connectionsWs.Load(),
		s.connectionsTcpFallback.Load(), s.connectionsCfproxy.Load(), s.connectionsCfWorker.Load(), s.connectionsBad.Load(),
		s.wsErrors.Load(), ph, ph+pm, humanBytes(s.bytesUp.Load()), humanBytes(s.bytesDown.Load()),
		s.bytesUp.Load(), s.bytesDown.Load(),
	)
}

func (s *Stats) SummaryRu() string {
	parts := []string{fmt.Sprintf("акт:%d", s.connectionsActive.Load())}
	if ws := s.connectionsWs.Load(); ws > 0 {
		parts = append(parts, fmt.Sprintf("ws:%d", ws))
	}
	if cf := s.connectionsCfproxy.Load(); cf > 0 {
		parts = append(parts, fmt.Sprintf("cf:%d", cf))
	}
	if cfw := s.connectionsCfWorker.Load(); cfw > 0 {
		parts = append(parts, fmt.Sprintf("cfw:%d", cfw))
	}
	if tcp := s.connectionsTcpFallback.Load(); tcp > 0 {
		parts = append(parts, fmt.Sprintf("tcp:%d", tcp))
	}
	if errCount := s.wsErrors.Load(); errCount > 0 {
		parts = append(parts, fmt.Sprintf("ош:%d", errCount))
	}
	parts = append(parts, fmt.Sprintf("↑%s ↓%s", humanBytes(s.bytesUp.Load()), humanBytes(s.bytesDown.Load())))
	return strings.Join(parts, " | ")
}

func (s *Stats) Reset() {
	s.connectionsTotal.Store(0)
	s.connectionsActive.Store(0)
	s.connectionsWs.Store(0)
	s.connectionsTcpFallback.Store(0)
	s.connectionsCfproxy.Store(0)
	s.connectionsCfWorker.Store(0)
	s.connectionsHttpReject.Store(0)
	s.connectionsPassthrough.Store(0)
	s.connectionsBad.Store(0)
	s.wsErrors.Store(0)
	s.bytesUp.Store(0)
	s.bytesDown.Store(0)
	s.poolHits.Store(0)
	s.poolMisses.Store(0)
}

var stats Stats

func humanBytes(n int64) string {
	units := []string{"B", "KB", "MB", "GB", "TB"}
	f := float64(n)
	for i, u := range units {
		if math.Abs(f) < 1024 || i == len(units)-1 {
			return fmt.Sprintf("%.1f%s", f, u)
		}
		f /= 1024
	}
	return fmt.Sprintf("%.1f%s", f, "TB")
}

// ---------------------------------------------------------------------------
// Socket helpers
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// ClientHello fragmentation (zapret's --dpi-desync=split2, done from userspace)
//
// DPI that blocks by SNI usually parses only the FIRST TCP segment of a
// connection. If the TLS ClientHello is delivered in one write it lands in one
// segment and the hostname is trivially readable. Splitting that first write
// into several segments — so the SNI straddles a boundary — makes a
// single-segment parser fail to find a hostname at all.
//
// zapret does this by rewriting packets in the kernel (WinDivert/NFQUEUE),
// which iOS forbids. But we own the socket that sends the handshake, so the
// same effect is achievable with plain Write calls: with TCP_NODELAY set (see
// setSockOpts) each Write becomes its own segment.
//
// Only the first write is split. Everything after the handshake is left alone,
// so throughput is unaffected.
type fragmentConn struct {
	net.Conn
	once      sync.Once
	firstSize int
	delay     time.Duration
}

func (c *fragmentConn) Write(b []byte) (int, error) {
	split := false
	c.once.Do(func() { split = true })

	// Too short to be a ClientHello worth splitting.
	if !split || len(b) <= c.firstSize+1 {
		return c.Conn.Write(b)
	}

	first := c.firstSize
	if first <= 0 || first >= len(b) {
		first = 1
	}

	if _, err := c.Conn.Write(b[:first]); err != nil {
		return 0, err
	}
	if c.delay > 0 {
		time.Sleep(c.delay)
	}

	// Second cut lands in the middle of the remainder, which is where the SNI
	// extension normally sits — a parser that only reassembles two segments
	// still comes up short.
	rest := b[first:]
	mid := len(rest) / 2
	if mid > 0 && mid < len(rest) {
		if _, err := c.Conn.Write(rest[:mid]); err != nil {
			return first, err
		}
		if c.delay > 0 {
			time.Sleep(c.delay)
		}
		rest = rest[mid:]
	}

	n, err := c.Conn.Write(rest)
	return len(b) - len(rest) + n, err
}

var (
	fragmentEnabled   = false
	fragmentFirstSize = 2
	fragmentDelayMs   = 10
	fragmentMu        sync.RWMutex
)

func maybeFragment(conn net.Conn) net.Conn {
	fragmentMu.RLock()
	on, size, delay := fragmentEnabled, fragmentFirstSize, fragmentDelayMs
	fragmentMu.RUnlock()

	if !on {
		return conn
	}
	return &fragmentConn{
		Conn:      conn,
		firstSize: size,
		delay:     time.Duration(delay) * time.Millisecond,
	}
}

func setSockOpts(conn net.Conn) {
	if tc, ok := conn.(*net.TCPConn); ok {
		if tcpNodelay {
			_ = tc.SetNoDelay(true)
		}
		_ = tc.SetKeepAlive(true)
		_ = tc.SetKeepAlivePeriod(30 * time.Second)
		_ = tc.SetReadBuffer(recvBuf)
		_ = tc.SetWriteBuffer(sendBuf)
	}
}

// ---------------------------------------------------------------------------
// XOR mask
// ---------------------------------------------------------------------------

func xorMaskInPlace(data, mask []byte) {
	n := len(data)
	if n == 0 {
		return
	}
	mask8 := uint64(mask[0]) | uint64(mask[1])<<8 | uint64(mask[2])<<16 | uint64(mask[3])<<24 |
		uint64(mask[0])<<32 | uint64(mask[1])<<40 | uint64(mask[2])<<48 | uint64(mask[3])<<56

	i := 0
	for ; i+8 <= n; i += 8 {
		v := binary.LittleEndian.Uint64(data[i:])
		binary.LittleEndian.PutUint64(data[i:], v^mask8)
	}
	for ; i < n; i++ {
		data[i] ^= mask[i&3]
	}
}

// ---------------------------------------------------------------------------
// RawWebSocket
// ---------------------------------------------------------------------------

var bytesPool = sync.Pool{
	New: func() any { return make([]byte, 131072) },
}

func SafeClose(conn net.Conn) {
	if conn == nil {
		return
	}
	if tc, ok := conn.(*net.TCPConn); ok {
		_ = tc.SetLinger(0)
	}
	_ = conn.Close()
}

var tlsConfigPool = &tls.Config{
	ClientSessionCache: tls.NewLRUClientSessionCache(100),
}

// Separate cache: utls.Config takes utls's own ClientSessionCache type.
var utlsSessionCache = utls.NewLRUClientSessionCache(100)

// TLS fingerprint selection. uTLS hides the fact that this isn't a browser,
// but a mimicked ClientHello can also be rejected outright by some edges —
// which looks like an instant EOF on connect. Keeping the Go standard stack
// selectable means a bad profile is one toggle away from being ruled out
// instead of requiring a rebuild.
const (
	tlsFpGo      = 0
	tlsFpFirefox = 1
	tlsFpChrome  = 2
	tlsFpSafari  = 3
	tlsFpRandom  = 4
)

var (
	tlsFingerprint   = tlsFpGo
	tlsFingerprintMu sync.RWMutex
)

// Fake SNI: send an innocuous server name in the TLS handshake while keeping
// the real destination in the HTTP Host header.
//
// This works because the two are used by different layers. DPI reads the SNI
// out of the cleartext ClientHello and blocks on it; Cloudflare's edge routes
// the request by the Host header, which is inside the encrypted stream and
// invisible from outside. Certificate mismatch is irrelevant here since the
// client already runs with InsecureSkipVerify.
//
// Serverless by construction — nothing to deploy, it only changes what this
// client puts on the wire.
// Fires the "bad decoy" hint once per proxy run rather than once per attempt.
var warnFakeSniOnce sync.Once

var (
	fakeSniEnabled = false
	fakeSniValue   = ""
	fakeSniMu      sync.RWMutex
)

// sniFor returns the server name to advertise in the handshake for a given
// real destination host.
func sniFor(realHost string) string {
	fakeSniMu.RLock()
	on, v := fakeSniEnabled, fakeSniValue
	fakeSniMu.RUnlock()
	if on && v != "" {
		return v
	}
	return realHost
}

func currentFingerprint() int {
	tlsFingerprintMu.RLock()
	defer tlsFingerprintMu.RUnlock()
	return tlsFingerprint
}

func fingerprintName(fp int) string {
	switch fp {
	case tlsFpFirefox:
		return "Firefox"
	case tlsFpChrome:
		return "Chrome"
	case tlsFpSafari:
		return "Safari"
	case tlsFpRandom:
		return "случайный"
	default:
		return "стандартный (Go)"
	}
}

func utlsHelloID(fp int) utls.ClientHelloID {
	switch fp {
	case tlsFpChrome:
		return utls.HelloChrome_Auto
	case tlsFpSafari:
		return utls.HelloSafari_Auto
	case tlsFpRandom:
		return utls.HelloRandomizedALPN
	default:
		return utls.HelloFirefox_Auto
	}
}

// Both *tls.Conn and *utls.UConn satisfy this.
type tlsHandshakeConn interface {
	net.Conn
	HandshakeContext(ctx context.Context) error
}

const (
	opText   = 0x1
	opBinary = 0x2
	opClose  = 0x8
	opPing   = 0x9
	opPong   = 0xA
)

type WsHandshakeError struct {
	StatusCode int
	StatusLine string
	Headers    map[string]string
	Location   string
}

func (e *WsHandshakeError) Error() string {
	return fmt.Sprintf("HTTP %d: %s", e.StatusCode, e.StatusLine)
}
func (e *WsHandshakeError) IsRedirect() bool {
	switch e.StatusCode {
	case 301, 302, 303, 307, 308:
		return true
	}
	return false
}

type RawWebSocket struct {
	conn      net.Conn
	bufReader *bufio.Reader
	writeMu   sync.Mutex
	closed    atomic.Bool
}

type dohResponse struct {
	Answer []struct {
		Data string `json:"data"`
		Type int    `json:"type"`
	} `json:"Answer"`
}

func pickPreferredIP(candidates []string) string {
	var fallbackV6 string
	for _, candidate := range candidates {
		ip := net.ParseIP(strings.TrimSpace(candidate))
		if ip == nil {
			continue
		}
		if ip4 := ip.To4(); ip4 != nil {
			return ip4.String()
		}
		if fallbackV6 == "" {
			fallbackV6 = ip.String()
		}
	}
	return fallbackV6
}

// Configurable DoH provider list, set via SetDohConfig from the app. Defaults
// match what always shipped before this was configurable.
var (
	dohConfigMu  sync.RWMutex
	dohEndpoints = []string{
		"https://cloudflare-dns.com/dns-query",
		"https://dns.google/dns-query",
		"https://dns.quad9.net/dns-query",
		"https://dns.adguard-dns.com/dns-query",
	}
)

func resolveDoH(ctx context.Context, domain string) string {
	if val, ok := dohCache.Load(domain); ok {
		entry := val.(dohCacheEntry)
		if time.Now().Before(entry.exp) {
			return entry.ip
		}
	}

	dohConfigMu.RLock()
	endpoints := append([]string(nil), dohEndpoints...)
	dohConfigMu.RUnlock()

	// Phase 1: DoH only. Plain UDP:53 is unauthenticated cleartext — an
	// on-path attacker/censor can forge a response, and with no signature to
	// check, a forged reply that arrives before the real (slower, TLS-
	// protected) DoH answer would silently win a race on equal footing.
	// That defeats the entire point of doing DoH. So UDP is never raced
	// against DoH here — it only gets tried afterwards, as phase 2, and only
	// if every DoH endpoint failed or timed out.
	if len(endpoints) > 0 {
		resCh := make(chan string, len(endpoints))
		dohCtx, dohCancel := context.WithTimeout(ctx, 1500*time.Millisecond)

		for _, url := range endpoints {
			go func(u string) {
				fullURL := fmt.Sprintf("%s?name=%s&type=A", u, domain)
				req, err := http.NewRequestWithContext(dohCtx, "GET", fullURL, nil)
				if err != nil {
					return
				}
				req.Header.Set("Accept", "application/dns-json")
				resp, err := dohClient.Do(req)
				if err != nil {
					return
				}
				defer resp.Body.Close()
				if resp.StatusCode != 200 {
					return
				}
				var r dohResponse
				if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
					return
				}
				for _, ans := range r.Answer {
					if ans.Type == 1 {
						select {
						case resCh <- ans.Data:
						default:
						}
						return
					}
				}
			}(url)
		}

		select {
		case ip := <-resCh:
			dohCancel()
			dohCache.Store(domain, dohCacheEntry{ip: ip, exp: time.Now().Add(5 * time.Minute)})
			logDebug.Printf(" DoH: %s → %s", domain, ip)
			return ip
		case <-dohCtx.Done():
			dohCancel()
			// Surfaced as a warning, not debug: losing DoH means the next
			// answer comes from plaintext UDP that nothing can authenticate.
			logWarn.Printf(" DoH: все резолверы не ответили для %s — переход на UDP:53", domain)
		}
	}

	if ctx.Err() != nil {
		return ""
	}

	// Phase 2: last-resort plain UDP, reached only once every configured DoH
	// endpoint has failed or timed out. Yandex (77.88.8.8) intentionally
	// dropped — RU jurisdiction/SORM, not worth the metadata exposure for a
	// resolver whose whole purpose here is reaching circumvention domains.
	udpCtx, udpCancel := context.WithTimeout(ctx, 800*time.Millisecond)
	defer udpCancel()

	udpServers := []string{"1.1.1.1:53", "8.8.8.8:53"}
	udpCh := make(chan string, len(udpServers))
	for _, srv := range udpServers {
		go func(s string) {
			r := &net.Resolver{
				PreferGo: true,
				Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
					d := net.Dialer{Timeout: 800 * time.Millisecond}
					return d.DialContext(ctx, "udp", s)
				},
			}
			ips, err := r.LookupHost(udpCtx, domain)
			if preferred := pickPreferredIP(ips); err == nil && preferred != "" {
				select {
				case udpCh <- preferred:
				default:
				}
			}
		}(srv)
	}

	select {
	case ip := <-udpCh:
		// Short TTL — this answer is unauthenticated, don't let a possibly
		// poisoned entry stick around as long as a verified DoH one would.
		dohCache.Store(domain, dohCacheEntry{ip: ip, exp: time.Now().Add(30 * time.Second)})
		logWarn.Printf(" DNS: %s → %s через UDP:53 (без проверки подлинности)", domain, ip)
		return ip
	case <-udpCtx.Done():
		logError.Printf(" DNS: не удалось разрешить %s (ни DoH, ни UDP)", domain)
		return ""
	}
}

func wsConnectTimeout(timeout float64) time.Duration {
	if timeout <= 0 {
		return 5 * time.Second
	}
	return time.Duration(timeout * float64(time.Second))
}

func contextRemainingTimeout(ctx context.Context, fallback time.Duration) time.Duration {
	if deadline, ok := ctx.Deadline(); ok {
		remaining := time.Until(deadline)
		if remaining > 0 {
			return remaining
		}
		return time.Millisecond
	}
	return fallback
}

func newTimedAttemptContext(parent context.Context, timeout time.Duration) (context.Context, context.CancelFunc, time.Duration) {
	effective := timeout
	if effective <= 0 {
		effective = 5 * time.Second
	}
	if deadline, ok := parent.Deadline(); ok {
		if remaining := time.Until(deadline); remaining > 0 && remaining < effective {
			effective = remaining
		}
	}
	ctx, cancel := context.WithTimeout(parent, effective)
	return ctx, cancel, effective
}

func compactConnError(err error) string {
	if err == nil {
		return ""
	}
	if errors.Is(err, context.Canceled) {
		return "canceled"
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return "timeout"
	}
	var wsErr *WsHandshakeError
	if errors.As(err, &wsErr) {
		return fmt.Sprintf("http %d", wsErr.StatusCode)
	}
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return "timeout"
	}
	return err.Error()
}

func isHTTPStatusError(err error, statusCode int) bool {
	var wsErr *WsHandshakeError
	return errors.As(err, &wsErr) && wsErr.StatusCode == statusCode
}

func logCfConnError(format string, err error, args ...any) {
	if isHTTPStatusError(err, http.StatusTooManyRequests) {
		logWarn.Printf(format, args...)
		return
	}
	logError.Printf(format, args...)
}

func wsConnectOnce(ctx context.Context, dialAddr, domain, path string, timeout time.Duration) (*RawWebSocket, error) {
	if dialAddr == "" {
		return nil, fmt.Errorf("empty dial address")
	}

	dialer := &net.Dialer{
		Timeout: timeout,
	}

	// uTLS instead of crypto/tls. Go's standard ClientHello has a very
	// distinctive cipher/extension ordering — its JA3/JA4 hash identifies the
	// connection as "not a browser" before the SNI is even considered, which
	// is exactly what DPI looks for. HelloFirefox_Auto emits a ClientHello
	// matching a current Firefox build instead.
	//
	// InsecureSkipVerify stays on: several CDN relays terminate TLS with
	// certificates that don't match the kwsN.<domain> name being dialed.
	targetAddr := net.JoinHostPort(dialAddr, "443")
	rawConn, err := dialer.DialContext(ctx, "tcp", targetAddr)
	if err != nil {
		return nil, err
	}

	setSockOpts(rawConn)

	// Wrap before the TLS handshake so the ClientHello is what gets split.
	fragConn := maybeFragment(rawConn)

	if sni := sniFor(domain); sni != domain {
		logDebug.Printf(" SNI подменён: %s -> %s (Host остаётся %s)", domain, sni, domain)
	}

	fp := currentFingerprint()
	var tlsConn tlsHandshakeConn
	if fp == tlsFpGo {
		goCfg := tlsConfigPool.Clone()
		goCfg.ServerName = sniFor(domain)
		goCfg.InsecureSkipVerify = true
		tlsConn = tls.Client(fragConn, goCfg)
	} else {
		uCfg := &utls.Config{
			ServerName:         sniFor(domain),
			InsecureSkipVerify: true,
			ClientSessionCache: utlsSessionCache,
		}
		uConn := utls.UClient(fragConn, uCfg, utlsHelloID(fp))

		// Force ALPN down to http/1.1.
		//
		// Browser ClientHello profiles advertise "h2" first, so Cloudflare
		// negotiates HTTP/2 — but everything below writes a hand-rolled
		// HTTP/1.1 request. To an h2 server that's garbage, and the
		// connection is dropped instantly: this is what made every uTLS
		// fingerprint fail with a bare EOF while the Go stdlib path (which
		// sends no ALPN at all, so the server defaults to HTTP/1.1) worked.
		if err := uConn.BuildHandshakeState(); err == nil {
			for _, ext := range uConn.Extensions {
				if alpn, ok := ext.(*utls.ALPNExtension); ok {
					alpn.AlpnProtocols = []string{"http/1.1"}
				}
			}
			// Re-marshal so the edited extension is what actually goes out.
			if err := uConn.MarshalClientHello(); err != nil {
				logDebug.Printf(" uTLS: не удалось пересобрать ClientHello: %v", err)
			}
		}
		tlsConn = uConn
	}
	// The whole attempt budget, not a fixed 3s: on a mobile link the TLS
	// handshake to a Cloudflare edge alone often takes longer than that.
	handshakeTimeout := contextRemainingTimeout(ctx, timeout)
	handshakeCtx, cancel := context.WithTimeout(ctx, handshakeTimeout)
	defer cancel()

	_ = tlsConn.SetDeadline(time.Now().Add(handshakeTimeout))
	if err := tlsConn.HandshakeContext(handshakeCtx); err != nil {
		rawConn.Close()
		logDebug.Printf(" ws tls fail %s via %s: %s", domain, dialAddr, compactConnError(err))

		// A decoy SNI that isn't itself served by the same edge gets the
		// handshake rejected before the Host header is ever read, which takes
		// down every domain at once and looks like a total outage. Say so
		// explicitly instead of leaving the user staring at 20 identical
		// failures.
		if sni := sniFor(domain); sni != domain &&
			strings.Contains(err.Error(), "handshake failure") {
			warnFakeSniOnce.Do(func() {
				logError.Printf(" Подмена SNI (%s) отвергнута — приманка должна сама быть за Cloudflare. Отключите её или укажите CF-домен", sni)
			})
		}
		return nil, err
	}
	_ = tlsConn.SetDeadline(time.Time{})
	rawConn = tlsConn

	wsKeyBytes := make([]byte, 16)
	_, _ = rand.Read(wsKeyBytes)
	wsKey := base64.StdEncoding.EncodeToString(wsKeyBytes)

	req := fmt.Sprintf(
		"GET %s HTTP/1.1\r\n"+
			"Host: %s\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Key: %s\r\n"+
			"Sec-WebSocket-Version: 13\r\n"+
			"Sec-WebSocket-Protocol: binary\r\n"+
			"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) "+
			"AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36\r\n\r\n",
		path, domain, wsKey,
	)

	_ = rawConn.SetWriteDeadline(time.Now().Add(timeout))
	if _, err = rawConn.Write([]byte(req)); err != nil {
		rawConn.Close()
		return nil, err
	}
	_ = rawConn.SetWriteDeadline(time.Time{})

	bufReader := bufio.NewReaderSize(rawConn, 4096)
	_ = rawConn.SetReadDeadline(time.Now().Add(timeout))

	var responseLines []string
	for {
		line, err := bufReader.ReadString('\n')
		if err != nil {
			rawConn.Close()
			return nil, err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		responseLines = append(responseLines, line)
		if len(responseLines) > 100 {
			rawConn.Close()
			return nil, fmt.Errorf("too many HTTP headers")
		}
	}
	_ = rawConn.SetReadDeadline(time.Time{})

	if len(responseLines) == 0 {
		rawConn.Close()
		return nil, &WsHandshakeError{StatusCode: 0, StatusLine: "empty response"}
	}

	firstLine := responseLines[0]
	parts := strings.SplitN(firstLine, " ", 3)
	statusCode := 0
	if len(parts) >= 2 {
		statusCode, _ = strconv.Atoi(parts[1])
	}

	if statusCode == 101 {
		return &RawWebSocket{conn: rawConn, bufReader: bufReader}, nil
	}
	headers := make(map[string]string)
	for _, hl := range responseLines[1:] {
		if idx := strings.IndexByte(hl, ':'); idx >= 0 {
			headers[strings.TrimSpace(strings.ToLower(hl[:idx]))] = strings.TrimSpace(hl[idx+1:])
		}
	}
	rawConn.Close()
	return nil, &WsHandshakeError{
		StatusCode: statusCode,
		StatusLine: firstLine,
		Headers:    headers,
		Location:   headers["location"],
	}
}

// failedBeforeConnect reports whether a dial never got a TCP connection up:
// a DNS failure, refused or unreachable address. Only then can a different IP
// from DoH help — a TLS or HTTP failure already reached Cloudflare's anycast
// edge, and DoH would just hand back the same edge.
func failedBeforeConnect(err error) bool {
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		return true
	}
	var opErr *net.OpError
	return errors.As(err, &opErr) && opErr.Op == "dial"
}

func cfConnectDomain(ctx context.Context, domain, path string, timeout time.Duration) (*RawWebSocket, string, error) {
	if path == "" {
		path = "/apiws"
	}

	hostCtx, cancelHost, hostTimeout := newTimedAttemptContext(ctx, timeout)
	ws, hostErr := wsConnectOnce(hostCtx, domain, domain, path, hostTimeout)
	cancelHost()
	if hostErr == nil {
		return ws, "", nil
	}
	if ctx.Err() != nil || !failedBeforeConnect(hostErr) {
		return nil, "", hostErr
	}

	resolvedIP := resolveDoH(ctx, domain)
	if resolvedIP == "" {
		logDebug.Printf(" CF DNS %s -> no result", domain)
		return nil, "", hostErr
	}

	logDebug.Printf(" CF DNS %s -> %s", domain, resolvedIP)
	ipCtx, cancelIP, ipTimeout := newTimedAttemptContext(ctx, timeout)
	ws, err := wsConnectOnce(ipCtx, resolvedIP, domain, path, ipTimeout)
	cancelIP()
	if err == nil {
		return ws, resolvedIP, nil
	}
	if ctx.Err() == nil {
		logCfConnError(" CF IP fail %s (%s): %s", err, domain, resolvedIP, compactConnError(err))
	}
	return nil, resolvedIP, err
}

func wsConnect(ctx context.Context, ip, domain, path string, timeout float64) (*RawWebSocket, error) {
	if path == "" {
		path = "/apiws"
	}

	attemptTimeout := wsConnectTimeout(timeout)
	attemptCtx, cancel := context.WithTimeout(ctx, attemptTimeout)
	defer cancel()

	primaryAddr := strings.TrimSpace(ip)
	if primaryAddr == "" {
		primaryAddr = domain
	}

	ws, err := wsConnectOnce(attemptCtx, primaryAddr, domain, path, attemptTimeout)
	if err == nil {
		return ws, nil
	}

	if primaryAddr == domain && net.ParseIP(primaryAddr) == nil {
		if resolvedIP := resolveDoH(attemptCtx, domain); resolvedIP != "" && resolvedIP != primaryAddr {
			return wsConnectOnce(attemptCtx, resolvedIP, domain, path, attemptTimeout)
		}
	}

	return nil, err
}

// connectDirectWS returns the socket plus (anyRedirect, allRedirects,
// timedOut). Like upstream, a timeout stops the walk: every domain goes to the
// same IP, so the next one would just burn another full timeout.
func connectDirectWS(ctx context.Context, target string, domains []string, timeout float64) (*RawWebSocket, bool, bool, bool) {
	if len(domains) == 0 {
		return nil, false, false, false
	}

	wsFailedRedirect := false
	allRedirects := true

	for _, dom := range domains {
		ws, err := wsConnect(ctx, target, dom, "/apiws", timeout)
		if err == nil {
			return ws, wsFailedRedirect, false, false
		}

		stats.wsErrors.Add(1)
		logDebug.Printf(" Direct %s via %s: %s", dom, target, compactConnError(err))
		var wsErr *WsHandshakeError
		if errors.As(err, &wsErr) {
			if wsErr.IsRedirect() {
				wsFailedRedirect = true
			} else {
				allRedirects = false
			}
			continue
		}
		allRedirects = false
		if ctx.Err() == nil && compactConnError(err) == "timeout" {
			return nil, wsFailedRedirect, false, true
		}
	}

	return nil, wsFailedRedirect, allRedirects, false
}

func (ws *RawWebSocket) writeFrame(frame []byte, timeout time.Duration) error {
	ws.writeMu.Lock()
	defer ws.writeMu.Unlock()
	defer recycleFrame(frame)

	if timeout > 0 {
		_ = ws.conn.SetWriteDeadline(time.Now().Add(timeout))
		defer ws.conn.SetWriteDeadline(time.Time{})
	}

	_, err := ws.conn.Write(frame)
	if err != nil {
		ws.closed.Store(true)
	}
	return err
}

func (ws *RawWebSocket) Send(data []byte) error {
	if ws.closed.Load() {
		return fmt.Errorf("WebSocket closed")
	}
	frame := ws.buildFrame(opBinary, data, true)
	return ws.writeFrame(frame, wsWriteTimeout)
}

func (ws *RawWebSocket) SendBatch(parts [][]byte) error {
	if ws.closed.Load() {
		return fmt.Errorf("WebSocket closed")
	}
	ws.writeMu.Lock()
	defer ws.writeMu.Unlock()
	_ = ws.conn.SetWriteDeadline(time.Now().Add(wsWriteTimeout))
	defer ws.conn.SetWriteDeadline(time.Time{})
	for _, part := range parts {
		frame := ws.buildFrame(opBinary, part, true)
		if _, err := ws.conn.Write(frame); err != nil {
			recycleFrame(frame)
			ws.closed.Store(true)
			return err
		}
		recycleFrame(frame)
	}
	return nil
}

func (ws *RawWebSocket) SendPing() error {
	if ws.closed.Load() {
		return fmt.Errorf("WebSocket closed")
	}
	frame := ws.buildFrame(opPing, nil, true)
	return ws.writeFrame(frame, wsControlTimeout)
}

func (ws *RawWebSocket) probe(timeout time.Duration) error {
	if ws.closed.Load() {
		return fmt.Errorf("WebSocket closed")
	}
	if err := ws.SendPing(); err != nil {
		return err
	}
	_ = ws.conn.SetReadDeadline(time.Now().Add(timeout))
	defer ws.conn.SetReadDeadline(time.Time{})

	for !ws.closed.Load() {
		opcode, payload, err := ws.readFrame()
		if err != nil {
			ws.closed.Store(true)
			return err
		}
		switch opcode {
		case opPong:
			return nil
		case opPing:
			if err := ws.writeFrame(ws.buildFrame(opPong, payload, true), wsControlTimeout); err != nil {
				return err
			}
		case opClose:
			ws.closed.Store(true)
			return io.EOF
		default:
			return fmt.Errorf("unexpected frame %d during pool probe", opcode)
		}
	}
	return io.EOF
}

func (ws *RawWebSocket) Recv() ([]byte, error) {
	for !ws.closed.Load() {
		opcode, payload, err := ws.readFrame()
		if err != nil {
			ws.closed.Store(true)
			return nil, err
		}
		switch opcode {
		case opClose:
			ws.closed.Store(true)
			closePayload := payload
			if len(closePayload) > 2 {
				closePayload = closePayload[:2]
			}
			reply := ws.buildFrame(opClose, closePayload, true)
			_ = ws.writeFrame(reply, wsControlTimeout)
			return nil, io.EOF
		case opPing:
			pong := ws.buildFrame(opPong, payload, true)
			_ = ws.writeFrame(pong, wsControlTimeout)
			continue
		case opText, opBinary:
			return payload, nil
		}
	}
	return nil, io.EOF
}

func (ws *RawWebSocket) Close() {
	if ws.closed.Swap(true) {
		return
	}
	frame := ws.buildFrame(opClose, nil, true)
	_ = ws.writeFrame(frame, wsControlTimeout)
	_ = ws.conn.Close()
}

var framePool = sync.Pool{
	New: func() any { return make([]byte, 0, pooledFrameCap) },
}

func recycleFrame(frame []byte) {
	if cap(frame) == pooledFrameCap {
		framePool.Put(frame[:0])
	}
}

func (ws *RawWebSocket) buildFrame(opcode int, data []byte, mask bool) []byte {
	length := len(data)
	fb := byte(0x80 | opcode)

	headerSize := 2
	if mask {
		headerSize += 4
	}
	if length >= 126 && length < 65536 {
		headerSize += 2
	} else if length >= 65536 {
		headerSize += 8
	}

	totalSize := headerSize + length
	var result []byte
	if totalSize <= pooledFrameCap {
		result = framePool.Get().([]byte)[:0]
	} else {
		result = make([]byte, 0, totalSize)
	}
	result = result[:totalSize]

	pos := 0
	result[pos] = fb
	pos++

	var maskKey [4]byte
	if mask {
		_, _ = rand.Read(maskKey[:])
	}

	if length < 126 {
		lb := byte(length)
		if mask {
			lb |= 0x80
		}
		result[pos] = lb
		pos++
	} else if length < 65536 {
		lb := byte(126)
		if mask {
			lb |= 0x80
		}
		result[pos] = lb
		pos++
		binary.BigEndian.PutUint16(result[pos:], uint16(length))
		pos += 2
	} else {
		lb := byte(127)
		if mask {
			lb |= 0x80
		}
		result[pos] = lb
		pos++
		binary.BigEndian.PutUint64(result[pos:], uint64(length))
		pos += 8
	}

	if mask {
		copy(result[pos:], maskKey[:])
		pos += 4
		payloadStart := pos
		copy(result[payloadStart:], data)
		xorMaskInPlace(result[payloadStart:payloadStart+length], maskKey[:])
	} else {
		copy(result[pos:], data)
	}
	return result
}

func (ws *RawWebSocket) readFrame() (int, []byte, error) {
	var hdr [2]byte
	if _, err := io.ReadFull(ws.bufReader, hdr[:]); err != nil {
		return 0, nil, err
	}

	opcode := int(hdr[0] & 0x0F)
	length := uint64(hdr[1] & 0x7F)

	if length == 126 {
		var buf [2]byte
		if _, err := io.ReadFull(ws.bufReader, buf[:]); err != nil {
			return 0, nil, err
		}
		length = uint64(binary.BigEndian.Uint16(buf[:]))
	} else if length == 127 {
		var buf [8]byte
		if _, err := io.ReadFull(ws.bufReader, buf[:]); err != nil {
			return 0, nil, err
		}
		length = binary.BigEndian.Uint64(buf[:])
	}

	hasMask := (hdr[1] & 0x80) != 0
	var maskKey [4]byte
	if hasMask {
		if _, err := io.ReadFull(ws.bufReader, maskKey[:]); err != nil {
			return 0, nil, err
		}
	}

	const maxFramePayload = 16 * 1024 * 1024
	if length > maxFramePayload {
		return 0, nil, fmt.Errorf("frame too large: %d bytes", length)
	}
	payload := make([]byte, length)
	if length > 0 {
		if _, err := io.ReadFull(ws.bufReader, payload); err != nil {
			return 0, nil, err
		}
	}

	if hasMask {
		xorMaskInPlace(payload, maskKey[:])
	}

	return opcode, payload, nil
}

// ---------------------------------------------------------------------------
// Crypto & MTProto Splitter
// ---------------------------------------------------------------------------

type TrackedStream struct {
	key       []byte
	iv        []byte
	processed uint64
	stream    cipher.Stream
}

func newTrackedCTR(key, iv []byte) (*TrackedStream, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return &TrackedStream{
		key:       append([]byte(nil), key...),
		iv:        append([]byte(nil), iv...),
		processed: 0,
		stream:    cipher.NewCTR(block, iv),
	}, nil
}

func (t *TrackedStream) XORKeyStream(dst, src []byte) {
	t.stream.XORKeyStream(dst, src)
	t.processed += uint64(len(src))
}

func (t *TrackedStream) Clone() cipher.Stream {
	block, _ := aes.NewCipher(t.key)
	cloneStream := cipher.NewCTR(block, t.iv)
	tClone := &TrackedStream{
		key:       t.key,
		iv:        t.iv,
		processed: t.processed,
		stream:    cloneStream,
	}
	var dummy [16384]byte
	rem := t.processed
	for rem > 0 {
		n := rem
		if n > 16384 {
			n = 16384
		}
		tClone.stream.XORKeyStream(dummy[:n], dummy[:n])
		rem -= n
	}
	return tClone
}

func newAESCTR(key, iv []byte) (cipher.Stream, error) {
	return newTrackedCTR(key, iv)
}

const (
	protoAbridged           = 0
	protoIntermediate       = 1
	protoPaddedIntermediate = 2
)

type MsgSplitter struct {
	stream    cipher.Stream
	protoType int
	cipherBuf []byte
	plainBuf  []byte
	disabled  bool
}

func protoTagToType(proto uint32) int {
	switch proto {
	case 0xEEEEEEEE:
		return protoIntermediate
	case 0xDDDDDDDD:
		return protoPaddedIntermediate
	default:
		return protoAbridged
	}
}

func newMsgSplitter(initData []byte, proto uint32) (*MsgSplitter, error) {
	if len(initData) < 56 {
		return nil, fmt.Errorf("init data too short")
	}
	stream, err := newAESCTR(initData[8:40], initData[40:56])
	if err != nil {
		return nil, err
	}
	skip := make([]byte, 64)
	stream.XORKeyStream(skip, zero64)

	return &MsgSplitter{
		stream:    stream,
		protoType: protoTagToType(proto),
	}, nil
}

func (s *MsgSplitter) Split(chunk []byte) [][]byte {
	if len(chunk) == 0 {
		return nil
	}
	if s.disabled {
		return [][]byte{chunk}
	}

	s.cipherBuf = append(s.cipherBuf, chunk...)
	decrypted := make([]byte, len(chunk))
	s.stream.XORKeyStream(decrypted, chunk)
	s.plainBuf = append(s.plainBuf, decrypted...)

	var parts [][]byte
	for len(s.cipherBuf) > 0 {
		pktLen := s.nextPacketLen()
		if pktLen < 0 {
			break
		}
		if pktLen == 0 {
			parts = append(parts, append([]byte(nil), s.cipherBuf...))
			s.cipherBuf = nil
			s.plainBuf = nil
			s.disabled = true
			break
		}
		if len(s.cipherBuf) < pktLen {
			break
		}
		parts = append(parts, append([]byte(nil), s.cipherBuf[:pktLen]...))
		s.cipherBuf = s.cipherBuf[pktLen:]
		s.plainBuf = s.plainBuf[pktLen:]
	}

	if len(s.cipherBuf) == 0 {
		s.cipherBuf = nil
		s.plainBuf = nil
	}
	if len(parts) == 0 {
		return nil
	}
	return parts
}

func (s *MsgSplitter) Flush() [][]byte {
	if len(s.cipherBuf) == 0 {
		return nil
	}
	tail := append([]byte(nil), s.cipherBuf...)
	s.cipherBuf = nil
	s.plainBuf = nil
	return [][]byte{tail}
}

func (s *MsgSplitter) nextPacketLen() int {
	if len(s.plainBuf) == 0 {
		return -1
	}
	switch s.protoType {
	case protoAbridged:
		first := s.plainBuf[0] & 0x7F
		var headerLen, payloadLen int
		if first == 0x7F {
			if len(s.plainBuf) < 4 {
				return -1
			}
			payloadLen = int(uint32(s.plainBuf[1])|uint32(s.plainBuf[2])<<8|uint32(s.plainBuf[3])<<16) * 4
			headerLen = 4
		} else {
			payloadLen = int(first) * 4
			headerLen = 1
		}
		if payloadLen <= 0 {
			return 0
		}
		pktLen := headerLen + payloadLen
		if len(s.plainBuf) < pktLen {
			return -1
		}
		return pktLen

	case protoIntermediate, protoPaddedIntermediate:
		if len(s.plainBuf) < 4 {
			return -1
		}
		payloadLen := int(binary.LittleEndian.Uint32(s.plainBuf[:4]) & 0x7FFFFFFF)
		if payloadLen <= 0 {
			return 0
		}
		pktLen := 4 + payloadLen
		if len(s.plainBuf) < pktLen {
			return -1
		}
		return pktLen
	}
	return 0
}

// ---------------------------------------------------------------------------
// WsPool & Bridging
// ---------------------------------------------------------------------------

func wsDomains(dc int, isMedia bool) []string {
	effectiveDC := dc
	if override, ok := dcOverrides[dc]; ok {
		effectiveDC = override
	}

	if isMedia {
		return []string{
			fmt.Sprintf("kws%d-1.web.telegram.org", effectiveDC),
			fmt.Sprintf("kws%d.web.telegram.org", effectiveDC),
		}
	}
	return []string{
		fmt.Sprintf("kws%d.web.telegram.org", effectiveDC),
		fmt.Sprintf("kws%d-1.web.telegram.org", effectiveDC),
	}
}

type dcSlot struct {
	dc      int
	isMedia int
}

type poolEntry struct {
	ws      *RawWebSocket
	created int64
}

type WsPool struct {
	queues sync.Map
	status sync.Map
}

func newWsPool() *WsPool { return &WsPool{} }

func (p *WsPool) getQueue(slot dcSlot) (chan *poolEntry, *atomic.Int32) {
	q, _ := p.queues.LoadOrStore(slot, make(chan *poolEntry, 16)) // Max size safely handled
	s, _ := p.status.LoadOrStore(slot, &atomic.Int32{})
	return q.(chan *poolEntry), s.(*atomic.Int32)
}

func isMediaInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func isPoolEntryUsable(e *poolEntry, now int64) bool {
	if e == nil || e.ws == nil || e.ws.closed.Load() {
		return false
	}
	if now-e.created > int64(wsPoolReuseMaxAge) {
		return false
	}
	return true
}

func (p *WsPool) Get(ctx context.Context, dc int, isMedia bool, targetIP string, domains []string) *RawWebSocket {
	slot := dcSlot{dc, isMediaInt(isMedia)}
	q, s := p.getQueue(slot)
	now := time.Now().Unix()
	var ws *RawWebSocket

	for {
		select {
		case e := <-q:
			if !isPoolEntryUsable(e, now) {
				if e != nil && e.ws != nil {
					SafeClose(e.ws.conn)
				}
				continue
			}
			ws = e.ws
			stats.poolHits.Add(1)
		default:
			stats.poolMisses.Add(1)
		}
		break
	}

	if s.CompareAndSwap(0, 1) {
		go p.refill(ctx, slot, q, s, targetIP, domains)
	}
	return ws
}

func (p *WsPool) refill(ctx context.Context, slot dcSlot, q chan *poolEntry, s *atomic.Int32, targetIP string, domains []string) {
	defer s.Store(0)
	needed := int(poolSize.Load()) - len(q)
	if needed <= 0 {
		return
	}

	var wg sync.WaitGroup
	for i := 0; i < needed; i++ {
		select {
		case <-ctx.Done():
			return
		default:
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			if ws := connectOneWS(ctx, targetIP, domains); ws != nil {
				now := time.Now().Unix()
				// select picks randomly among ready cases, so a stopped proxy
				// could still park a socket in the queue without this check.
				if ctx.Err() != nil {
					SafeClose(ws.conn)
					return
				}
				select {
				case q <- &poolEntry{ws: ws, created: now}:
				case <-ctx.Done():
					SafeClose(ws.conn)
				default:
					SafeClose(ws.conn)
				}
			}
		}()
	}
	wg.Wait()
}

func (p *WsPool) Warmup(ctx context.Context, dcOptMap map[int]string) {
	for dc := range dcOptMap {
		// Negative keys are media overrides ("-2:IP"); they're picked up by
		// resolveConfiguredTarget below rather than warmed as a "DC-2".
		if dc <= 0 {
			continue
		}
		for _, isMedia := range []bool{false, true} {
			select {
			case <-ctx.Done():
				return
			default:
			}
			targetIP, ok := resolveConfiguredTarget(dc, isMedia)
			if !ok {
				continue
			}
			domains := wsDomains(dc, isMedia)
			slot := dcSlot{dc, isMediaInt(isMedia)}
			q, s := p.getQueue(slot)
			if s.CompareAndSwap(0, 1) {
				go p.refill(ctx, slot, q, s, targetIP, domains)
			}
		}
	}
}

func (p *WsPool) IdleCount() int {
	count := 0
	p.queues.Range(func(_, val interface{}) bool {
		count += len(val.(chan *poolEntry))
		return true
	})
	return count
}

func (p *WsPool) CloseAll() {
	p.queues.Range(func(_, val interface{}) bool {
		q := val.(chan *poolEntry)
		for {
			select {
			case e := <-q:
				SafeClose(e.ws.conn)
			default:
				return true
			}
		}
	})
}

var wsPool = newWsPool()

func mediaTag(isMedia bool) string {
	if isMedia {
		return "m"
	}
	return ""
}

func isHTTPTransport(data []byte) bool {
	if len(data) < 4 {
		return false
	}
	return string(data[:4]) == "POST" || string(data[:3]) == "GET" ||
		string(data[:4]) == "HEAD" || string(data[:7]) == "OPTIONS"
}

const (
	endNone int32 = iota
	endClient
	endUpstream
)

func bridgeWS(ctx context.Context, conn net.Conn, ws *RawWebSocket,
	label string, dc int, dst string, port int, isMedia bool,
	splitter *MsgSplitter, cltDec, cltEnc, tgEnc, tgDec cipher.Stream) bridgeResult {

	ctx2, cancel := context.WithCancel(ctx)
	defer cancel()

	start := time.Now()
	var upBytes, downBytes atomic.Int64
	// Which side ended the session first — the other side's error is just
	// the fallout of the cancel.
	var firstEnd atomic.Int32
	endedBy := func(side int32) { firstEnd.CompareAndSwap(endNone, side) }

	go func() {
		<-ctx2.Done()
		SafeClose(conn)
		ws.Close()
	}()

	var wg sync.WaitGroup
	wg.Add(2)

	// WS keepalive: periodic ping to detect dead connections
	lastActivity := time.Now()
	var activityMu sync.Mutex

	go func() {
		ticker := time.NewTicker(bridgePingInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx2.Done():
				return
			case <-ticker.C:
				activityMu.Lock()
				idle := time.Since(lastActivity)
				activityMu.Unlock()
				if idle > bridgePingInterval {
					if err := ws.SendPing(); err != nil {
						cancel()
						return
					}
				}
			}
		}
	}()

	go func() {
		defer wg.Done()
		defer cancel()
		buf := bytesPool.Get().([]byte)
		defer bytesPool.Put(buf)
		readLimit := cap(buf)
		if readLimit > wsBridgeChunkSize {
			readLimit = wsBridgeChunkSize
		}
		for {
			_ = conn.SetReadDeadline(time.Now().Add(bridgeReadTimeout))
			n, err := conn.Read(buf[:readLimit])
			if n > 0 {
				chunk := buf[:n]
				stats.bytesUp.Add(int64(n))
				upBytes.Add(int64(n))

				activityMu.Lock()
				lastActivity = time.Now()
				activityMu.Unlock()

				cltDec.XORKeyStream(chunk, chunk)
				tgEnc.XORKeyStream(chunk, chunk)

				var sendErr error
				if splitter != nil {
					parts := splitter.Split(chunk)
					if len(parts) > 1 {
						sendErr = ws.SendBatch(parts)
					} else if len(parts) == 1 {
						sendErr = ws.Send(parts[0])
					}
				} else {
					sendErr = ws.Send(chunk)
				}
				if sendErr != nil {
					endedBy(endUpstream)
					return
				}
			}
			if err != nil {
				endedBy(endClient)
				if splitter != nil {
					tail := splitter.Flush()
					if len(tail) > 0 {
						if len(tail) > 1 {
							if sendErr := ws.SendBatch(tail); sendErr != nil {
								return
							}
						} else {
							if sendErr := ws.Send(tail[0]); sendErr != nil {
								return
							}
						}
					}
				}
				return
			}
		}
	}()

	go func() {
		defer wg.Done()
		defer cancel()
		for {
			_ = ws.conn.SetReadDeadline(time.Now().Add(bridgeReadTimeout))
			data, err := ws.Recv()
			if err != nil || data == nil {
				endedBy(endUpstream)
				return
			}
			n := len(data)
			stats.bytesDown.Add(int64(n))
			downBytes.Add(int64(n))

			activityMu.Lock()
			lastActivity = time.Now()
			activityMu.Unlock()

			tgDec.XORKeyStream(data, data)
			cltEnc.XORKeyStream(data, data)
			if _, werr := conn.Write(data); werr != nil {
				endedBy(endClient)
				return
			}
		}
	}()

	wg.Wait()

	res := bridgeResult{
		up:            upBytes.Load(),
		down:          downBytes.Load(),
		elapsed:       time.Since(start),
		upstreamEnded: firstEnd.Load() == endUpstream,
	}
	logDebug.Printf(" DC%d%s сессия через %s закрыта: ↑%s ↓%s за %.1fс",
		dc, mediaTag(isMedia), dst, humanBytes(res.up), humanBytes(res.down), res.elapsed.Seconds())
	return res
}

func bridgeTCP(ctx context.Context, client, remote net.Conn,
	label string, dc int, dst string, port int, isMedia bool, cltDec, cltEnc, tgEnc, tgDec cipher.Stream) {

	ctx2, cancel := context.WithCancel(ctx)

	go func() {
		<-ctx2.Done()
		SafeClose(client)
		SafeClose(remote)
	}()

	var wg sync.WaitGroup
	wg.Add(2)

	forward := func(src, dstW net.Conn, isUp bool) {
		defer wg.Done()
		defer cancel()
		buf := bytesPool.Get().([]byte)
		defer bytesPool.Put(buf)
		for {
			_ = src.SetReadDeadline(time.Now().Add(bridgeReadTimeout))
			n, err := src.Read(buf[:cap(buf)])
			if n > 0 {
				chunk := buf[:n]
				if isUp {
					stats.bytesUp.Add(int64(n))
					cltDec.XORKeyStream(chunk, chunk)
					tgEnc.XORKeyStream(chunk, chunk)
				} else {
					stats.bytesDown.Add(int64(n))
					tgDec.XORKeyStream(chunk, chunk)
					cltEnc.XORKeyStream(chunk, chunk)
				}
				if _, werr := dstW.Write(chunk); werr != nil {
					return
				}
			}
			if err != nil {
				return
			}
		}
	}

	go forward(client, remote, true)
	go forward(remote, client, false)

	wg.Wait()
}

func tcpFallback(ctx context.Context, client net.Conn, dst string, port int,
	init []byte, label string, dc int, isMedia bool, cltDec, cltEnc, tgEnc, tgDec cipher.Stream) bool {

	dialer := &net.Dialer{
		Timeout:   10 * time.Second,
		KeepAlive: 60 * time.Second,
	}
	remote, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(dst, strconv.Itoa(port)))
	if err != nil {
		return false
	}

	stats.connectionsTcpFallback.Add(1)
	logInfo.Printf(" DC%d%s подключен по TCP", dc, mediaTag(isMedia))
	_, _ = remote.Write(init)
	bridgeTCP(ctx, client, remote, label, dc, dst, port, isMedia, cltDec, cltEnc, tgEnc, tgDec)
	return true
}

func tryCfproxyBaseDomain(ctx context.Context, dc int, baseDomain string) (*RawWebSocket, string) {
	baseDomain = normalizeCfDomain(baseDomain)
	if baseDomain == "" {
		return nil, ""
	}
	if remaining := cfproxy429CooldownRemaining(baseDomain); remaining > 0 {
		logDebug.Printf(" CF skip %s: 429 cooldown %.0fs", baseDomain, math.Ceil(remaining.Seconds()))
		return nil, ""
	}
	if !acquireCfproxyAttemptSlot(ctx) {
		return nil, ""
	}
	defer releaseCfproxyAttemptSlot()

	// kws{dc} literally, as upstream does — including kws203. The kwsN
	// records belong to the CF domain (the setup guide creates all six), so
	// the web.telegram.org 203->2 mapping doesn't apply here: it sent DC203
	// traffic to DC2's server.
	domain := fmt.Sprintf("kws%d.%s", dc, baseDomain)
	logDebug.Printf(" CDN: пробуем wss://%s/apiws", domain)

	ws, resolvedIP, err := cfConnectDomain(ctx, domain, "/apiws", cfproxyDialTimeout)
	if err != nil {
		if ctx.Err() == nil && isHTTPStatusError(err, http.StatusTooManyRequests) {
			markCfproxy429Cooldown(baseDomain, err)
		}
		if ctx.Err() == nil {
			if resolvedIP != "" {
				logCfConnError(" CF fail %s via %s: %s", err, domain, resolvedIP, compactConnError(err))
			} else {
				logCfConnError(" CF fail %s: %s", err, domain, compactConnError(err))
			}
		}
		return nil, ""
	}

	clearCfproxy429Cooldown(baseDomain)
	if resolvedIP != "" {
		logDebug.Printf(" CF ok %s via %s", domain, resolvedIP)
	} else {
		logDebug.Printf(" CF ok %s via hostname", domain)
	}
	return ws, baseDomain
}

func cfproxyFallback(ctx context.Context, conn net.Conn, relayInit []byte, label string,
	dc int, isMedia bool, splitter *MsgSplitter,
	cltDec, cltEnc, tgEnc, tgDec cipher.Stream) bool {

	cfproxyMu.RLock()
	if !cfproxyEnabled || len(cfproxyDomains) == 0 {
		cfproxyMu.RUnlock()
		return false
	}
	active := activeCfDomain
	domains := make([]string, len(cfproxyDomains))
	copy(domains, cfproxyDomains)
	cfproxyMu.RUnlock()

	ordered := []string{active}
	for _, d := range domains {
		if d != active {
			ordered = append(ordered, d)
		}
	}

	mTag := mediaTag(isMedia)
	logDebug.Printf(" CF fallback DC%d%s: %d домен(ов)", dc, mTag, len(ordered))

	// Connecting (not the session itself) is capped for the whole tier.
	tierCtx, cancelTier := context.WithTimeout(ctx, cfTierBudget)
	defer cancelTier()

	var ws *RawWebSocket
	var chosenDomain string

	if len(ordered) > 0 && ordered[0] != "" {
		ws, chosenDomain = tryCfproxyBaseDomain(tierCtx, dc, ordered[0])
	}

	if ws == nil && len(ordered) > 1 && tierCtx.Err() == nil {
		remainingDomains := ordered[1:]

		type wsResult struct {
			ws     *RawWebSocket
			domain string
		}
		attemptCtx, cancelAttempts := context.WithCancel(tierCtx)
		defer cancelAttempts()

		ch := make(chan wsResult, len(remainingDomains))
		sem := make(chan struct{}, cfproxyFallbackParallel)
		for _, baseDomain := range remainingDomains {
			go func(bd string) {
				select {
				case sem <- struct{}{}:
				case <-attemptCtx.Done():
					ch <- wsResult{}
					return
				}
				defer func() { <-sem }()

				nextWS, nextDomain := tryCfproxyBaseDomain(attemptCtx, dc, bd)
				if nextWS != nil {
					select {
					case ch <- wsResult{ws: nextWS, domain: nextDomain}:
					case <-attemptCtx.Done():
						go nextWS.Close()
						ch <- wsResult{}
					}
					return
				}
				ch <- wsResult{}
			}(baseDomain)
		}

		for i := 0; i < len(remainingDomains); i++ {
			r := <-ch
			if r.ws != nil && ws == nil {
				ws = r.ws
				chosenDomain = r.domain
				cancelAttempts()
				remaining := len(remainingDomains) - i - 1
				if remaining > 0 {
					go func(left int) {
						for j := 0; j < left; j++ {
							rr := <-ch
							if rr.ws != nil {
								go rr.ws.Close()
							}
						}
					}(remaining)
				}
				break
			} else if r.ws != nil {
				go r.ws.Close()
			}
		}
	}

	if ws == nil {
		if tierCtx.Err() == context.DeadlineExceeded {
			logWarn.Printf(" CF fallback DC%d%s: за %.0fс ни один CF домен не ответил", dc, mTag, cfTierBudget.Seconds())
		} else {
			logWarn.Printf(" CF fallback DC%d%s: все CF домены недоступны", dc, mTag)
		}
		return false
	}

	if chosenDomain != "" && chosenDomain != active {
		cfproxyMu.Lock()
		activeCfDomain = chosenDomain
		cfproxyMu.Unlock()
		saveActiveCfproxyDomain(chosenDomain)
		logInfo.Printf(" CF домен  %s", chosenDomain)
	}

	stats.connectionsCfproxy.Add(1)
	logInfo.Printf(" DC%d%s подключен через CF", dc, mTag)

	if err := ws.Send(relayInit); err != nil {
		logWarn.Printf(" CDN: не удалось отправить handshake (%d Б) для DC%d%s: %v",
			len(relayInit), dc, mediaTag(isMedia), err)
		ws.Close()
		return false
	}
	logDebug.Printf(" CDN: handshake отправлен (%d Б) для DC%d%s через %s",
		len(relayInit), dc, mediaTag(isMedia), chosenDomain)

	res := bridgeWS(ctx, conn, ws, label, dc, chosenDomain, 443, isMedia, splitter, cltDec, cltEnc, tgEnc, tgDec)
	judgeSession(tierCdn, dc, isMedia, res)
	return true
}

// workerDialTarget resolves the configured Cloudflare Worker URL into a
// (host, path) pair suitable for wsConnectOnce/cfConnectDomain, with the
// query string upstream's Worker expects: /apiws?dst=<DC IP>&dc=<n>.
// media=0|1 is extra, only used for the fork Worker's logging.
func workerDialTarget(rawURL string, dc int, isMedia bool) (host, path string, ok bool) {
	rawURL = strings.TrimSpace(rawURL)
	if rawURL == "" {
		return "", "", false
	}
	if !strings.Contains(rawURL, "://") {
		// Upstream's docs hand out bare hostnames like
		// "name-1234.user.workers.dev"; accept those as https.
		rawURL = "https://" + rawURL
	}

	u, err := url.Parse(rawURL)
	if err != nil || u.Host == "" {
		return "", "", false
	}

	p := u.Path
	if p == "" || p == "/" {
		p = "/apiws"
	}

	// The Worker opens a plain TCP socket to dst:443 and pipes raw MTProto
	// into it, so dst must be the DC's own address — exactly what upstream
	// passes (DC_DEFAULT_IPS). The DC->IP settings / 149.154.167.220 are the
	// WebSocket gateway, which speaks TLS: sending it raw MTProto got the
	// session dropped every time, which is why the Worker "never worked"
	// for DC2/DC4.
	dst := resolveFallbackTarget(dc, isMedia)
	if dst == "" {
		return "", "", false
	}

	mediaFlag := 0
	if isMedia {
		mediaFlag = 1
	}
	sep := "?"
	if strings.Contains(p, "?") {
		sep = "&"
	}
	if u.RawQuery != "" {
		p = p + sep + u.RawQuery
		sep = "&"
	}
	// dst is what the relay actually dials; dc/media are kept for logging and
	// for relays that still route by DC number.
	path = fmt.Sprintf("%s%sdst=%s&dc=%d&media=%d", p, sep, url.QueryEscape(dst), dc, mediaFlag)
	return u.Host, path, true
}

func tryCfWorker(ctx context.Context, dc int, isMedia bool) *RawWebSocket {
	cfWorkerMu.RLock()
	enabled := cfWorkerEnabled
	urls := append([]string(nil), cfWorkerURLs...)
	cfWorkerMu.RUnlock()

	if !enabled || len(urls) == 0 {
		return nil
	}

	select {
	case cfWorkerSem <- struct{}{}:
	case <-ctx.Done():
		return nil
	}
	defer func() { <-cfWorkerSem }()

	tierCtx, cancelTier := context.WithTimeout(ctx, cfTierBudget)
	defer cancelTier()

	// Try each configured worker in turn: one of them being down or rate
	// limited shouldn't take the whole tier with it.
	for _, raw := range urls {
		if tierCtx.Err() != nil {
			return nil
		}
		host, path, ok := workerDialTarget(raw, dc, isMedia)
		if !ok {
			logWarn.Printf(" Worker: не удалось разобрать адрес %q", raw)
			continue
		}

		logDebug.Printf(" Worker: пробуем wss://%s%s (таймаут %.0fс)", host, path, cfWorkerDialTimeout.Seconds())
		ws, resolvedIP, err := cfConnectDomain(tierCtx, host, path, cfWorkerDialTimeout)
		if err != nil {
			if ctx.Err() == nil {
				logCfConnError(" Worker fail %s: %s", err, host, compactConnError(err))
			}
			continue
		}

		if resolvedIP != "" {
			logDebug.Printf(" Worker ok %s via %s", host, resolvedIP)
		} else {
			logDebug.Printf(" Worker ok %s", host)
		}
		return ws
	}

	return nil
}

func workerFallback(ctx context.Context, conn net.Conn, relayInit []byte, label string,
	dc int, isMedia bool, splitter *MsgSplitter,
	cltDec, cltEnc, tgEnc, tgDec cipher.Stream) bool {

	ws := tryCfWorker(ctx, dc, isMedia)
	if ws == nil {
		logWarn.Printf(" Worker недоступен для DC%d%s — пробуем другие маршруты", dc, mediaTag(isMedia))
		return false
	}

	stats.connectionsCfWorker.Add(1)
	logInfo.Printf(" DC%d%s подключен через CF Worker", dc, mediaTag(isMedia))

	if err := ws.Send(relayInit); err != nil {
		logWarn.Printf(" Worker: не удалось отправить handshake (%d Б) для DC%d%s: %v",
			len(relayInit), dc, mediaTag(isMedia), err)
		ws.Close()
		return false
	}
	logDebug.Printf(" Worker: handshake отправлен (%d Б) для DC%d%s", len(relayInit), dc, mediaTag(isMedia))

	// splitter MUST be nil here, unlike the CDN tier above.
	//
	// The CDN/gateway path talks to Telegram's own WebSocket endpoint, which
	// delivers one complete MTProto message per WS frame — the splitter
	// relies on that framing. The Worker is a raw TCP relay: it forwards
	// whatever TCP chunks happen to arrive, so message boundaries are
	// arbitrary. Running the splitter over that stream re-frames it wrongly
	// and corrupts the session — the tunnel connects, the handshake goes
	// through, and then Telegram spins forever on mangled data.
	//
	// Upstream does the same (bridge_ws_reencrypt(..., splitter=None) in its
	// worker fallback), which is what confirmed this.
	res := bridgeWS(ctx, conn, ws, label, dc, "cf-worker", 443, isMedia, nil, cltDec, cltEnc, tgEnc, tgDec)
	judgeSession(tierWorker, dc, isMedia, res)
	return true
}

func cfproxyAvailable() bool {
	cfproxyMu.RLock()
	defer cfproxyMu.RUnlock()
	return cfproxyEnabled && len(cfproxyDomains) > 0
}

func cfWorkerAvailable() bool {
	cfWorkerMu.RLock()
	defer cfWorkerMu.RUnlock()
	return cfWorkerEnabled && len(cfWorkerURLs) > 0
}

// tryTier runs one Cloudflare tier. It returns true once the client has been
// bridged (whatever happened during the session), false if the tier couldn't
// connect at all — the client's bytes are untouched then, so the caller can
// move on to the next tier.
func tryTier(tier string, ctx context.Context, conn net.Conn, relayInit []byte, label string,
	dc int, isMedia bool, splitter *MsgSplitter,
	cltDec, cltEnc, tgEnc, tgDec cipher.Stream) bool {
	switch tier {
	case tierCdn:
		return cfproxyFallback(ctx, conn, relayInit, label, dc, isMedia, splitter, cltDec, cltEnc, tgEnc, tgDec)
	case tierWorker:
		return workerFallback(ctx, conn, relayInit, label, dc, isMedia, splitter, cltDec, cltEnc, tgEnc, tgDec)
	}
	return false
}

func tierAvailable(tier string) bool {
	switch tier {
	case tierCdn:
		return cfproxyAvailable()
	case tierWorker:
		return cfWorkerAvailable()
	}
	return false
}

// doFallback walks upstream's fallback chain: Worker -> CDN -> raw TCP.
// Tiers in `skip` were already attempted for this connection. A tier whose
// last session came back dead is skipped while its cooldown runs, but still
// gets a last-chance attempt if everything else fails too.
func doFallback(ctx context.Context, conn net.Conn, relayInit []byte, label string,
	dc int, isMedia bool, splitter *MsgSplitter,
	cltDec, cltEnc, tgEnc, tgDec cipher.Stream, skip map[string]bool) bool {

	if t, ok := cltDec.(interface{ Clone() cipher.Stream }); ok {
		cltDec = t.Clone()
	}
	if t, ok := cltEnc.(interface{ Clone() cipher.Stream }); ok {
		cltEnc = t.Clone()
	}
	if t, ok := tgEnc.(interface{ Clone() cipher.Stream }); ok {
		tgEnc = t.Clone()
	}
	if t, ok := tgDec.(interface{ Clone() cipher.Stream }); ok {
		tgDec = t.Clone()
	}

	fallbackDst := resolveFallbackTarget(dc, isMedia)
	mTag := mediaTag(isMedia)

	var deferred []string
	for _, tier := range []string{tierWorker, tierCdn} {
		if skip[tier] || !tierAvailable(tier) {
			continue
		}
		if left, cooling := tierCoolingDown(tier, dc, isMedia); cooling {
			logDebug.Printf(" DC%d%s: %s пропущен, ещё %.0fс после мёртвой сессии", dc, mTag, tierName(tier), left.Seconds())
			deferred = append(deferred, tier)
			continue
		}
		if tryTier(tier, ctx, conn, relayInit, label, dc, isMedia, splitter, cltDec, cltEnc, tgEnc, tgDec) {
			return true
		}
		if ctx.Err() != nil {
			return false
		}
	}

	if fallbackDst != "" {
		if tcpFallback(ctx, conn, fallbackDst, 443, relayInit, label, dc, isMedia, cltDec, cltEnc, tgEnc, tgDec) {
			return true
		}
		logWarn.Printf(" DC%d%s: TCP до %s:443 недоступен", dc, mTag, fallbackDst)
	}

	for _, tier := range deferred {
		if ctx.Err() != nil {
			return false
		}
		logInfo.Printf(" DC%d%s: остальные маршруты не сработали — повторяем %s", dc, mTag, tierName(tier))
		if tryTier(tier, ctx, conn, relayInit, label, dc, isMedia, splitter, cltDec, cltEnc, tgEnc, tgDec) {
			return true
		}
	}

	logWarn.Printf(" DC%d%s: ни один маршрут не доступен", dc, mTag)
	return false
}

// ---------------------------------------------------------------------------
// Fake TLS support (ee-secret)
// ---------------------------------------------------------------------------

const (
	tlsRecordHandshake = 0x16
	tlsRecordCCS       = 0x14
	tlsRecordAppData   = 0x17
	clientRandomOffset = 11
	clientRandomLen    = 32
	sessionIdOffset    = 44
	sessionIdLen       = 32
	timestampTolerance = 120
)

func verifyClientHello(data, secret []byte) ([]byte, []byte, bool) {
	n := len(data)
	if n < 43 {
		return nil, nil, false
	}
	if data[0] != tlsRecordHandshake || data[5] != 0x01 {
		return nil, nil, false
	}

	clientRandom := make([]byte, clientRandomLen)
	copy(clientRandom, data[clientRandomOffset:clientRandomOffset+clientRandomLen])

	zeroed := make([]byte, n)
	copy(zeroed, data)
	for i := 0; i < clientRandomLen; i++ {
		zeroed[clientRandomOffset+i] = 0
	}

	mac := hmacSHA256(secret, zeroed)

	for i := 0; i < 28; i++ {
		if mac[i] != clientRandom[i] {
			return nil, nil, false
		}
	}

	tsXor := make([]byte, 4)
	for i := 0; i < 4; i++ {
		tsXor[i] = clientRandom[28+i] ^ mac[28+i]
	}
	timestamp := binary.LittleEndian.Uint32(tsXor)
	now := uint32(time.Now().Unix())
	diff := int64(now) - int64(timestamp)
	if diff < 0 {
		diff = -diff
	}
	if diff > timestampTolerance {
		return nil, nil, false
	}

	sessionId := make([]byte, sessionIdLen)
	if n >= sessionIdOffset+sessionIdLen && data[43] == 0x20 {
		copy(sessionId, data[sessionIdOffset:sessionIdOffset+sessionIdLen])
	}

	return clientRandom, sessionId, true
}

func hmacSHA256(key, data []byte) []byte {
	h := hmac.New(sha256.New, key)
	h.Write(data)
	return h.Sum(nil)
}

var serverHelloTemplate = []byte{
	0x16, 0x03, 0x03, 0x00, 0x7a, 0x02, 0x00, 0x00, 0x76, 0x03, 0x03,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0x20,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0x13, 0x01, 0x00, 0x00, 0x2e, 0x00, 0x33, 0x00, 0x24, 0x00, 0x1d, 0x00, 0x20,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0x00, 0x2b, 0x00, 0x02, 0x03, 0x04,
}

func buildServerHello(secret, clientRandom, sessionId []byte) []byte {
	sh := make([]byte, len(serverHelloTemplate))
	copy(sh, serverHelloTemplate)
	copy(sh[44:44+32], sessionId)

	pubKey := make([]byte, 32)
	rand.Read(pubKey)
	copy(sh[89:89+32], pubKey)

	ccsFrame := []byte{0x14, 0x03, 0x03, 0x00, 0x01, 0x01}

	encSize := 1900 + int(time.Now().UnixNano()%200)
	encData := make([]byte, encSize)
	rand.Read(encData)
	appRecord := make([]byte, 5+encSize)
	appRecord[0] = 0x17
	appRecord[1] = 0x03
	appRecord[2] = 0x03
	binary.BigEndian.PutUint16(appRecord[3:5], uint16(encSize))
	copy(appRecord[5:], encData)

	response := make([]byte, 0, len(sh)+len(ccsFrame)+len(appRecord))
	response = append(response, sh...)
	response = append(response, ccsFrame...)
	response = append(response, appRecord...)

	hmacInput := make([]byte, 0, len(clientRandom)+len(response))
	hmacInput = append(hmacInput, clientRandom...)
	hmacInput = append(hmacInput, response...)
	serverRandom := hmacSHA256(secret, hmacInput)

	copy(response[11:11+32], serverRandom)

	return response
}

type FakeTlsConn struct {
	conn     net.Conn
	readLeft int
}

func newFakeTlsConn(conn net.Conn) *FakeTlsConn {
	return &FakeTlsConn{conn: conn}
}

func (f *FakeTlsConn) Read(p []byte) (int, error) {
	if f.readLeft > 0 {
		toRead := f.readLeft
		if toRead > len(p) {
			toRead = len(p)
		}
		n, err := f.conn.Read(p[:toRead])
		f.readLeft -= n
		return n, err
	}

	for {
		hdr := make([]byte, 5)
		if _, err := io.ReadFull(f.conn, hdr); err != nil {
			return 0, err
		}

		rtype := hdr[0]
		recLen := int(binary.BigEndian.Uint16(hdr[3:5]))

		if rtype == tlsRecordCCS {
			if recLen > 0 {
				discard := make([]byte, recLen)
				if _, err := io.ReadFull(f.conn, discard); err != nil {
					return 0, err
				}
			}
			continue
		}

		if rtype != tlsRecordAppData {
			return 0, fmt.Errorf("unexpected TLS record type 0x%02X", rtype)
		}

		toRead := recLen
		if toRead > len(p) {
			toRead = len(p)
		}
		n, err := f.conn.Read(p[:toRead])
		f.readLeft = recLen - n
		return n, err
	}
}

func (f *FakeTlsConn) Write(p []byte) (int, error) {
	var parts []byte
	offset := 0
	for offset < len(p) {
		end := offset + 16384
		if end > len(p) {
			end = len(p)
		}
		chunk := p[offset:end]
		hdr := []byte{0x17, 0x03, 0x03, 0, 0}
		binary.BigEndian.PutUint16(hdr[3:5], uint16(len(chunk)))
		parts = append(parts, hdr...)
		parts = append(parts, chunk...)
		offset = end
	}
	_, err := f.conn.Write(parts)
	return len(p), err
}

func (f *FakeTlsConn) Close() error                       { return f.conn.Close() }
func (f *FakeTlsConn) LocalAddr() net.Addr                { return f.conn.LocalAddr() }
func (f *FakeTlsConn) RemoteAddr() net.Addr               { return f.conn.RemoteAddr() }
func (f *FakeTlsConn) SetDeadline(t time.Time) error      { return f.conn.SetDeadline(t) }
func (f *FakeTlsConn) SetReadDeadline(t time.Time) error  { return f.conn.SetReadDeadline(t) }
func (f *FakeTlsConn) SetWriteDeadline(t time.Time) error { return f.conn.SetWriteDeadline(t) }

var warnNoProxyHeaderOnce sync.Once

// readProxyProtocolV1 consumes a PROXY protocol v1 header ("PROXY TCP4 src
// dst sport dport\r\n", at most 107 bytes) and returns the real client
// address. Read byte by byte so nothing past the header is swallowed.
func readProxyProtocolV1(conn net.Conn) (string, error) {
	const maxLen = 107
	line := make([]byte, 0, maxLen)
	one := make([]byte, 1)
	for len(line) < maxLen {
		if _, err := io.ReadFull(conn, one); err != nil {
			return "", err
		}
		line = append(line, one[0])
		if one[0] == '\n' {
			break
		}
	}
	text := strings.TrimRight(string(line), "\r\n")
	if !strings.HasPrefix(text, "PROXY ") {
		return "", fmt.Errorf("нет заголовка PROXY (%q)", text[:min(len(text), 16)])
	}
	parts := strings.Fields(text)
	if len(parts) >= 6 {
		return net.JoinHostPort(parts[2], parts[4]), nil
	}
	// "PROXY UNKNOWN" — valid, just no address to report.
	return "", nil
}

// proxyToMaskHost hands a connection that failed the FakeTLS check to a real
// web server, so a prober sees an ordinary site answer its ClientHello.
func proxyToMaskHost(ctx context.Context, conn net.Conn, initial []byte, maskHost, label string) {
	if maskHost == "" {
		return
	}
	addr := maskHost
	if _, _, err := net.SplitHostPort(addr); err != nil {
		addr = net.JoinHostPort(addr, "443")
	}

	d := net.Dialer{Timeout: 10 * time.Second}
	up, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		logDebug.Printf(" [%s] маскировка: %s недоступен: %s", label, addr, compactConnError(err))
		return
	}
	defer up.Close()
	logDebug.Printf(" [%s] маскировка -> %s", label, addr)

	_ = conn.SetDeadline(time.Time{})
	if len(initial) > 0 {
		if _, err := up.Write(initial); err != nil {
			return
		}
	}

	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(up, conn); done <- struct{}{} }()
	go func() { _, _ = io.Copy(conn, up); done <- struct{}{} }()
	select {
	case <-done:
	case <-ctx.Done():
	}
}

// PrefixConn replays bytes already read off the socket (the first byte we
// peeked at) before handing reads back to the connection.
type PrefixConn struct {
	net.Conn
	prefix []byte
}

func (c *PrefixConn) Read(p []byte) (int, error) {
	if len(c.prefix) > 0 {
		n := copy(p, c.prefix)
		c.prefix = c.prefix[n:]
		return n, nil
	}
	return c.Conn.Read(p)
}

func handleClient(ctx context.Context, conn net.Conn) {
	stats.connectionsTotal.Add(1)
	stats.connectionsActive.Add(1)
	defer func() {
		if stats.connectionsActive.Load() > 0 {
			stats.connectionsActive.Add(-1)
		}
	}()
	peer := conn.RemoteAddr().String()
	label := peer

	setSockOpts(conn)

	defer conn.Close()

	proxySecretMu.RLock()
	currentSecret := proxySecret
	proxySecretMu.RUnlock()
	secretBytes, _ := hex.DecodeString(currentSecret)

	// One snapshot per connection: the Swift side can rewrite these at any
	// moment, and reading them unlocked mid-handshake is a data race.
	fakeTlsMu.RLock()
	tlsDomain := ""
	if fakeTlsEnabled {
		tlsDomain = fakeTlsDomain
	}
	maskHost := fakeTlsMaskHost
	fakeTlsMu.RUnlock()

	proxyProtocolMu.RLock()
	expectProxyHeader := proxyProtocolEnabled
	proxyProtocolMu.RUnlock()

	if expectProxyHeader {
		_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
		realPeer, err := readProxyProtocolV1(conn)
		if err != nil {
			logDebug.Printf(" [%s] PROXY protocol: %s", label, err)
			warnNoProxyHeaderOnce.Do(func() {
				logWarn.Printf(" Включён режим nginx (PROXY protocol), но подключение пришло без заголовка PROXY — проверьте proxy_protocol on; в nginx или выключите режим")
			})
			return
		}
		if realPeer != "" {
			label = realPeer
		}
	}

	firstByte := make([]byte, 1)
	_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(conn, firstByte); err != nil {
		return
	}
	_ = conn.SetReadDeadline(time.Time{})

	var clientConn net.Conn = conn
	var handshake []byte

	if tlsDomain != "" {
		// FakeTLS on means only ee-clients are legitimate, exactly as upstream
		// treats it. Anything else is a scanner or active probe, and has to
		// get what a real web server would give it — not an MTProto socket.
		if firstByte[0] != tlsRecordHandshake {
			logDebug.Printf(" [%s] FakeTLS: не TLS (0x%02X) — HTTP-редирект на %s", label, firstByte[0], tlsDomain)
			_, _ = conn.Write([]byte("HTTP/1.1 301 Moved Permanently\r\nLocation: https://" + tlsDomain +
				"/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"))
			return
		}

		hdrRest := make([]byte, 4)
		_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
		if _, err := io.ReadFull(conn, hdrRest); err != nil {
			return
		}
		tlsHeader := append(firstByte, hdrRest...)
		recordLen := int(binary.BigEndian.Uint16(tlsHeader[3:5]))
		if recordLen > 16384 {
			proxyToMaskHost(ctx, conn, tlsHeader, maskHost, label)
			return
		}

		recordBody := make([]byte, recordLen)
		if _, err := io.ReadFull(conn, recordBody); err != nil {
			return
		}
		_ = conn.SetReadDeadline(time.Time{})
		clientHello := append(tlsHeader, recordBody...)
		clientRandom, sessionId, ok := verifyClientHello(clientHello, secretBytes)
		if !ok {
			// Wrong secret, a stale timestamp (clock >2 min off) or a prober.
			logDebug.Printf(" [%s] FakeTLS: ClientHello не прошёл проверку (%d Б) — маскировка", label, len(clientHello))
			proxyToMaskHost(ctx, conn, clientHello, maskHost, label)
			return
		}

		serverHello := buildServerHello(secretBytes, clientRandom, sessionId)
		if _, err := conn.Write(serverHello); err != nil {
			return
		}
		logDebug.Printf(" [%s] FakeTLS: рукопожатие принято (%d Б), SNI %s", label, len(clientHello), tlsDomain)
		clientConn = newFakeTlsConn(conn)
	} else {
		clientConn = &PrefixConn{Conn: conn, prefix: firstByte}
	}

	handshake = make([]byte, 64)
	_ = clientConn.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.ReadFull(clientConn, handshake); err != nil {
		return
	}
	_ = clientConn.SetReadDeadline(time.Time{})

	if isHTTPTransport(handshake) {
		stats.connectionsHttpReject.Add(1)
		_, _ = conn.Write([]byte("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n"))
		return
	}

	cltDecPrekey := handshake[8:40]
	cltDecIv := handshake[40:56]
	hashDec := sha256.New()
	hashDec.Write(cltDecPrekey)
	hashDec.Write(secretBytes)
	cltDecryptor, _ := newAESCTR(hashDec.Sum(nil), cltDecIv)

	decrypted := make([]byte, 64)
	cltDecryptor.XORKeyStream(decrypted, handshake)

	protoTag := decrypted[56:60]
	proto := binary.LittleEndian.Uint32(protoTag)
	if !validProtos[proto] {
		stats.connectionsBad.Add(1)
		return
	}

	dcRaw := int16(binary.LittleEndian.Uint16(decrypted[60:62]))
	dc := int(dcRaw)
	if dc < 0 {
		dc = -dc
	}
	isMedia := dcRaw < 0
	mTag := mediaTag(isMedia)

	cltEncPrekeyAndIv := make([]byte, 48)
	for i := 0; i < 48; i++ {
		cltEncPrekeyAndIv[i] = handshake[8+47-i]
	}
	hashEnc := sha256.New()
	hashEnc.Write(cltEncPrekeyAndIv[:32])
	hashEnc.Write(secretBytes)
	cltEncryptor, _ := newAESCTR(hashEnc.Sum(nil), cltEncPrekeyAndIv[32:])

	relayInit := make([]byte, 64)
	for {
		rand.Read(relayInit)
		if relayInit[0] == 0xEF {
			continue
		}
		s := string(relayInit[:4])
		if s == "HEAD" || s == "POST" || s == "GET " || s == "\xee\xee\xee\xee" || s == "\xdd\xdd\xdd\xdd" {
			continue
		}
		if relayInit[0] == 0x16 && relayInit[1] == 0x03 && relayInit[2] == 0x01 && relayInit[3] == 0x02 {
			continue
		}
		if relayInit[4] == 0 && relayInit[5] == 0 && relayInit[6] == 0 && relayInit[7] == 0 {
			continue
		}
		break
	}

	tgDecPrekeyAndIv := make([]byte, 48)
	for i := 0; i < 48; i++ {
		tgDecPrekeyAndIv[i] = relayInit[8+47-i]
	}

	tgEncryptor, _ := newAESCTR(relayInit[8:40], relayInit[40:56])
	tgDecryptor, _ := newAESCTR(tgDecPrekeyAndIv[:32], tgDecPrekeyAndIv[32:])

	dcBytes := make([]byte, 2)
	dcIdx := dc
	if isMedia {
		dcIdx = -dc
	}
	binary.LittleEndian.PutUint16(dcBytes, uint16(dcIdx))

	tailPlain := make([]byte, 8)
	copy(tailPlain[0:4], protoTag)
	copy(tailPlain[4:6], dcBytes)
	rand.Read(tailPlain[6:8])

	encryptedFull := make([]byte, 64)
	tgEncryptor.XORKeyStream(encryptedFull, relayInit)

	keystreamTail := make([]byte, 8)
	for i := 0; i < 8; i++ {
		keystreamTail[i] = encryptedFull[56+i] ^ relayInit[56+i]
		relayInit[56+i] = tailPlain[i] ^ keystreamTail[i]
	}

	dcKey := [2]int{dc, isMediaInt(isMedia)}
	now := float64(time.Now().UnixNano()) / 1e9

	newSplitter := func() *MsgSplitter {
		s, _ := newMsgSplitter(relayInit, proto)
		return s
	}
	fallback := func(skip map[string]bool) bool {
		return doFallback(ctx, clientConn, relayInit, label, dc, isMedia, newSplitter(), cltDecryptor, cltEncryptor, tgEncryptor, tgDecryptor, skip)
	}

	// Optional "X first" modes put one Cloudflare tier ahead of Direct. If it
	// can't connect, the connection carries on exactly as in Auto, minus the
	// tier already tried.
	tried := map[string]bool{}
	var first string
	switch currentRouteMode() {
	case routeCdnFirst:
		first = tierCdn
	case routeWorkerFirst:
		first = tierWorker
	}
	if first != "" && tierAvailable(first) {
		if _, cooling := tierCoolingDown(first, dc, isMedia); !cooling {
			tried[first] = true
			if tryTier(first, ctx, clientConn, relayInit, label, dc, isMedia, newSplitter(), cltDecryptor, cltEncryptor, tgEncryptor, tgDecryptor) {
				return
			}
		}
	}

	target, dcConfigured := resolveConfiguredTarget(dc, isMedia)

	wsBlackMu.RLock()
	blacklisted := wsBlacklist[dcKey]
	wsBlackMu.RUnlock()

	if !dcConfigured || blacklisted {
		if !dcConfigured {
			logDebug.Printf(" DC%d%s: адрес для Direct не задан — резервные маршруты", dc, mTag)
		}
		fallback(tried)
		return
	}

	// Direct timed out or went silent recently: don't make every new
	// connection wait for it again, go straight to the fallback chain — and
	// only come back to Direct if that chain has nothing left.
	if left, cooling := tierCoolingDown(tierDirect, dc, isMedia); cooling {
		logDebug.Printf(" DC%d%s: Direct на паузе ещё %.0fс — резервные маршруты", dc, mTag, left.Seconds())
		if fallback(tried) {
			return
		}
		logInfo.Printf(" DC%d%s: резервы не сработали — пробуем Direct несмотря на паузу", dc, mTag)
	}

	dcFailMu.RLock()
	failUntil := dcFailUntil[dcKey]
	dcFailMu.RUnlock()

	wsTimeout := wsDirectTimeout
	if now < failUntil {
		wsTimeout = wsFailTimeout
	}

	domains := wsDomains(dc, isMedia)

	fromPool := false
	ws := wsPool.Get(ctx, dc, isMedia, target, domains)
	if ws != nil {
		fromPool = true
		logDebug.Printf(" DC%d%s: соединение из пула", dc, mTag)
	}

	var wsFailedRedirect, allRedirects, timedOut bool
	if ws == nil {
		ws, wsFailedRedirect, allRedirects, timedOut = connectDirectWS(ctx, target, domains, wsTimeout)
	}

	if ws == nil {
		logWarn.Printf(" DC%d%s: все попытки WS провалены (DPI/Интернет)", dc, mTag)
		if wsFailedRedirect && allRedirects {
			wsBlackMu.Lock()
			wsBlacklist[dcKey] = true
			wsBlackMu.Unlock()
			logWarn.Printf(" DC%d%s заблокирован (302)", dc, mTag)
		} else if timedOut {
			markTierDead(tierDirect, dc, isMedia, ipFailCooldown*time.Second)
			logWarn.Printf(" DC%d%s: Direct не отвечает — пауза %.0f мин, пока идём резервом", dc, mTag, ipFailCooldown/60)
		} else {
			dcFailMu.Lock()
			dcFailUntil[dcKey] = now + dcFailCooldown
			dcFailMu.Unlock()
		}

		fallback(tried)
		return
	}

	sendDirectInit := func(activeWS *RawWebSocket) error {
		if err := activeWS.Send(relayInit); err != nil {
			return err
		}
		logDebug.Printf(" direct relayInit sent DC%d%s", dc, mTag)
		return nil
	}

	if err := sendDirectInit(ws); err != nil {
		logWarn.Printf(" direct relayInit write fail DC%d%s: %s", dc, mTag, compactConnError(err))
		ws.Close()
		wasPooled := fromPool
		fromPool = false

		// A pooled socket going stale says nothing about the route.
		if !wasPooled {
			dcFailMu.Lock()
			dcFailUntil[dcKey] = now + dcFailCooldown
			dcFailMu.Unlock()
		}

		logWarn.Printf(" direct retry fresh ws DC%d%s", dc, mTag)
		retryWS, retryFailedRedirect, retryAllRedirects, _ := connectDirectWS(ctx, target, domains, wsTimeout)
		if retryWS == nil {
			if retryFailedRedirect && retryAllRedirects {
				wsBlackMu.Lock()
				wsBlacklist[dcKey] = true
				wsBlackMu.Unlock()
				logWarn.Printf(" DC%d%s заблокирован (302)", dc, mTag)
			}
			logWarn.Printf(" direct fallback DC%d%s", dc, mTag)
			fallback(tried)
			return
		}

		ws = retryWS
		if err = sendDirectInit(ws); err != nil {
			logWarn.Printf(" direct relayInit write fail DC%d%s: %s", dc, mTag, compactConnError(err))
			ws.Close()
			logWarn.Printf(" direct fallback DC%d%s", dc, mTag)
			fallback(tried)
			return
		}
	}

	dcFailMu.Lock()
	delete(dcFailUntil, dcKey)
	dcFailMu.Unlock()

	stats.connectionsWs.Add(1)
	logInfo.Printf(" DC%d%s подключен напрямую", dc, mTag)

	res := bridgeWS(ctx, clientConn, ws, label, dc, target, 443, isMedia, newSplitter(), cltDecryptor, cltEncryptor, tgEncryptor, tgDecryptor)
	// A pooled socket the server had already closed dies instantly on first
	// use; that's a stale pool entry, not DPI eating the route.
	if fromPool && res.upstreamEnded && res.elapsed < deadSessionMinSilence {
		logDebug.Printf(" DC%d%s: соединение из пула оказалось закрытым", dc, mTag)
		return
	}
	judgeSession(tierDirect, dc, isMedia, res)
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

func runProxy(ctx context.Context, host string, port int, dcOptMap map[int]string, started chan<- error) error {
	dcOptMu.Lock()
	dcOpt = dcOptMap
	dcOptMu.Unlock()

	addr := net.JoinHostPort(host, strconv.Itoa(port))
	lc := net.ListenConfig{}

	listener, err := lc.Listen(ctx, "tcp", addr)
	if err != nil {
		signalProxyStart(started, fmt.Errorf("listen on %s: %w", addr, err))
		return fmt.Errorf("listen on %s: %w", addr, err)
	}
	signalProxyStart(started, nil)

	srvCtx, srvCancel := context.WithCancel(ctx)
	defer srvCancel()

	startCfproxyRefresh(srvCtx)

	logInfo.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	logInfo.Println("  TG WS Proxy запущен")
	logInfo.Printf("  Адрес: %s:%d", host, port)

	// Configuration summary. Without this the Journal never showed whether
	// FakeTLS/DoH/Worker were actually engaged, so a misconfigured tier was
	// indistinguishable from a working one.
	mode := currentRouteMode()
	switch mode {
	case routeCdnFirst:
		logInfo.Println("  Маршрут: сначала CDN → Direct → Worker → TCP")
	case routeWorkerFirst:
		logInfo.Println("  Маршрут: сначала Worker → Direct → CDN → TCP")
	default:
		logInfo.Println("  Маршрут: авто (Direct → Worker → CDN → TCP)")
	}

	var directDCs []string
	for dc, ip := range dcOptMap {
		directDCs = append(directDCs, fmt.Sprintf("DC%d:%s", dc, ip))
	}
	if len(directDCs) > 0 {
		logInfo.Printf("  Direct: %s", strings.Join(directDCs, ", "))
	} else {
		logInfo.Println("  Direct: адреса DC не заданы — только резервные маршруты")
	}

	cfproxyMu.RLock()
	cfOn, cfDom, cfCount := cfproxyEnabled, cfproxyUserDomain, len(cfproxyDomains)
	cfproxyMu.RUnlock()

	if cfOn {
		if cfDom != "" {
			logInfo.Printf("  CDN: вкл, свой домен: %s", cfDom)
		} else {
			logInfo.Printf("  CDN: вкл, публичные домены (%d шт.)", cfCount)
		}
	} else {
		logInfo.Println("  CDN: выкл")
	}

	cfWorkerMu.RLock()
	wOn, wURL, wCount := cfWorkerEnabled, cfWorkerURL, len(cfWorkerURLs)
	cfWorkerMu.RUnlock()

	if wOn && wCount > 0 {
		logInfo.Printf("  Worker: вкл, %d шт. — %s", wCount, wURL)
	} else {
		logInfo.Println("  Worker: выкл")
	}
	if mode == routeWorkerFirst && !(wOn && wCount > 0) {
		logWarn.Println("  Выбран режим «сначала Worker», но Worker не настроен — работает как авто")
	}
	if mode == routeCdnFirst && !cfOn {
		logWarn.Println("  Выбран режим «сначала CDN», но CDN выключен — работает как авто")
	}

	logInfo.Printf("  TLS-отпечаток: %s", fingerprintName(currentFingerprint()))

	fakeSniMu.RLock()
	sniOn, sniVal := fakeSniEnabled, fakeSniValue
	fakeSniMu.RUnlock()
	if sniOn && sniVal != "" {
		logInfo.Printf("  Fake SNI: вкл — в рукопожатии видно %s", sniVal)
	} else {
		logInfo.Println("  Fake SNI: выкл")
	}

	fragmentMu.RLock()
	fragOn, fragSize, fragDelay := fragmentEnabled, fragmentFirstSize, fragmentDelayMs
	fragmentMu.RUnlock()
	if fragOn {
		logInfo.Printf("  Фрагментация: вкл (%d Б + деление пополам, пауза %d мс)", fragSize, fragDelay)
	} else {
		logInfo.Println("  Фрагментация: выкл")
	}

	fakeTlsMu.RLock()
	fOn, fDom, fMask := fakeTlsEnabled, fakeTlsDomain, fakeTlsMaskHost
	fakeTlsMu.RUnlock()

	if fOn && fDom != "" {
		if fMask != "" {
			logInfo.Printf("  FakeTLS: вкл, SNI %s (секрет ee...), чужие подключения -> %s", fDom, fMask)
		} else {
			logInfo.Printf("  FakeTLS: вкл, SNI %s (секрет ee...), чужие подключения закрываются", fDom)
		}
	} else if fOn {
		logInfo.Println("  FakeTLS: ВКЛ, но домен не задан — маскировка не активна")
	} else {
		logInfo.Println("  FakeTLS: выкл")
	}

	proxyProtocolMu.RLock()
	ppOn := proxyProtocolEnabled
	proxyProtocolMu.RUnlock()
	if ppOn {
		logInfo.Println("  nginx: ждём заголовок PROXY protocol v1 на каждом подключении")
	}

	dohConfigMu.RLock()
	dohList := append([]string(nil), dohEndpoints...)
	dohConfigMu.RUnlock()

	if len(dohList) > 0 {
		names := make([]string, 0, len(dohList))
		for _, e := range dohList {
			if u, err := url.Parse(e); err == nil && u.Host != "" {
				names = append(names, u.Host)
			}
		}
		logInfo.Printf("  DoH: %d резолвер(ов) — %s", len(dohList), strings.Join(names, ", "))
	} else {
		logInfo.Println("  DoH: нет резолверов — только обычный UDP:53")
	}
	logInfo.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	go func() {
		ticker := time.NewTicker(60 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-srvCtx.Done():
				return
			case <-ticker.C:
				logInfo.Printf(" %s", stats.SummaryRu())
			}
		}
	}()

	// Pre-open Direct sockets so the first connections don't wait on a TLS
	// handshake (upstream does the same warmup).
	wsPool.Warmup(srvCtx, dcOptMap)

	var activeConns sync.WaitGroup
	var listenerMu sync.Mutex
	currentListener := listener

	go func() {
		ln := listener
		for {
			conn, err := ln.Accept()
			if err != nil {
				if srvCtx.Err() != nil {
					return
				}
				if ne, ok := err.(net.Error); ok && ne.Timeout() {
					continue
				}
				// iOS can invalidate the listening socket while the app is
				// suspended. Without this the proxy looked "on" but never
				// accepted again; upstream restarts its listener the same way.
				logWarn.Printf(" Слушающий сокет упал (%s) — перезапуск", compactConnError(err))
				_ = ln.Close()
				for srvCtx.Err() == nil {
					select {
					case <-srvCtx.Done():
						return
					case <-time.After(time.Second):
					}
					nl, lerr := lc.Listen(srvCtx, "tcp", addr)
					if lerr != nil {
						logWarn.Printf(" Не удалось снова занять %s: %s", addr, compactConnError(lerr))
						continue
					}
					listenerMu.Lock()
					if srvCtx.Err() != nil {
						// Stopped while we were re-binding: don't leave the
						// port held for the next StartProxy.
						listenerMu.Unlock()
						_ = nl.Close()
						return
					}
					currentListener = nl
					listenerMu.Unlock()
					ln = nl
					logInfo.Printf(" Сокет восстановлен, слушаем %s", addr)
					break
				}
				continue
			}
			activeConns.Add(1)
			go func() {
				defer activeConns.Done()
				handleClient(srvCtx, conn)
			}()
		}
	}()

	<-srvCtx.Done()
	listenerMu.Lock()
	_ = currentListener.Close()
	listenerMu.Unlock()

	done := make(chan struct{})
	go func() {
		activeConns.Wait()
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(30 * time.Second):
	}

	// The pool itself is drained by StopProxy: doing it here, up to 30s
	// later, closed the pool of a proxy that had already been restarted.
	return nil
}

func parseCIDRPool(cidrsStr string) (map[int]string, error) {
	result := make(map[int]string)
	if strings.TrimSpace(cidrsStr) == "" {
		return result, nil
	}
	pairs := strings.Split(cidrsStr, ",")
	for _, pair := range pairs {
		parts := strings.Split(pair, ":")
		if len(parts) == 2 {
			dcRaw := strings.TrimSpace(parts[0])
			ipRaw := strings.TrimSpace(parts[1])
			if dc, err := strconv.Atoi(dcRaw); err == nil && ipRaw != "" {
				if parsedIP := net.ParseIP(ipRaw); parsedIP != nil {
					result[dc] = parsedIP.String()
				}
			}
		}
	}
	return result, nil
}

func signalProxyStart(started chan<- error, err error) {
	if started == nil {
		return
	}
	select {
	case started <- err:
	default:
	}
}

// ---------------------------------------------------------------------------
// CGO exports
// ---------------------------------------------------------------------------

var (
	globalCtx    context.Context
	globalCancel context.CancelFunc
	globalMu     sync.Mutex
)

//export StartProxy
func StartProxy(cHost *C.char, port C.int, cDcIps *C.char, cSecret *C.char, verbose C.int) C.int {
	globalMu.Lock()
	defer globalMu.Unlock()

	if globalCancel != nil {
		return -1
	}

	host := C.GoString(cHost)
	goPort := int(port)
	dcIpsStr := C.GoString(cDcIps)
	secretStr := C.GoString(cSecret)
	isVerbose := int(verbose) != 0

	initLogging(isVerbose)
	clearCfproxy429Cooldowns()
	resetTierCooldowns()
	warnNoProxyHeaderOnce = sync.Once{}

	if len(secretStr) == 32 {
		if _, err := hex.DecodeString(secretStr); err == nil {
			proxySecretMu.Lock()
			proxySecret = secretStr
			proxySecretMu.Unlock()
		}
	}

	initCfproxyDomains()

	dcOptMap, err := parseCIDRPool(dcIpsStr)
	if err != nil {
		return -2
	}

	globalCtx, globalCancel = context.WithCancel(context.Background())
	started := make(chan error, 1)

	go func() {
		_ = runProxy(globalCtx, host, goPort, dcOptMap, started)
	}()

	if err := <-started; err != nil {
		globalCancel()
		globalCancel = nil
		globalCtx = nil
		return -3
	}

	return 0
}

//export StopProxy
func StopProxy() C.int {
	globalMu.Lock()
	defer globalMu.Unlock()

	// Also guards logInfo: it's nil until the first StartProxy.
	if globalCancel == nil {
		return -1
	}
	logInfo.Println(" Остановка прокси...")

	globalCancel()
	globalCancel = nil
	globalCtx = nil

	wsPool.CloseAll()
	stats.Reset()
	resetTierCooldowns()

	wsBlackMu.Lock()
	wsBlacklist = make(map[[2]int]bool)
	wsBlackMu.Unlock()

	dcFailMu.Lock()
	dcFailUntil = make(map[[2]int]float64)
	dcFailMu.Unlock()

	clearCfproxy429Cooldowns()

	return 0
}

//export SetPoolSize
func SetPoolSize(size C.int) {
	n := int32(size)
	if n < 2 {
		n = 2
	}
	if n > 16 {
		n = 16
	}
	poolSize.Store(n)
}

//export SetCfProxyCacheDir
func SetCfProxyCacheDir(cCacheDir *C.char) {
	cfproxyMu.Lock()
	cfproxyCacheDir = strings.TrimSpace(C.GoString(cCacheDir))
	cfproxyMu.Unlock()
}

//export SetCfProxyConfig
func SetCfProxyConfig(enabled C.int, cUserDomain *C.char) {
	cfproxyMu.Lock()
	defer cfproxyMu.Unlock()

	cfproxyEnabled = int(enabled) != 0

	userDomain := strings.TrimSpace(C.GoString(cUserDomain))
	cfproxyUserDomain = userDomain

	// Several base domains may be listed; they're tried in order.
	list := parseCfUserDomains(userDomain)
	newSet := make(map[string]bool, len(list))
	for _, d := range list {
		newSet[d] = true
	}
	cfproxyUserDomainMu.Lock()
	cfproxyUserDomainSet = newSet
	cfproxyUserDomainMu.Unlock()
	if len(list) > 0 {
		cfproxyDomains = list
		activeCfDomain = list[0]
	}
}

//export SetRouteMode
func SetRouteMode(mode C.int) {
	m := int(mode)
	if m != routeCdnFirst && m != routeWorkerFirst {
		m = routeAuto
	}
	routeModeMu.Lock()
	routeMode = m
	routeModeMu.Unlock()
}

//export SetProxyProtocol
func SetProxyProtocol(enabled C.int) {
	proxyProtocolMu.Lock()
	proxyProtocolEnabled = int(enabled) != 0
	proxyProtocolMu.Unlock()
}

//export SetCfWorkerConfig
func SetCfWorkerConfig(enabled C.int, cWorkerURL *C.char) {
	cfWorkerMu.Lock()
	defer cfWorkerMu.Unlock()

	cfWorkerEnabled = int(enabled) != 0
	cfWorkerURL = strings.TrimSpace(C.GoString(cWorkerURL))

	cfWorkerURLs = nil
	for _, part := range strings.Split(cfWorkerURL, ",") {
		if p := strings.TrimSpace(part); p != "" {
			cfWorkerURLs = append(cfWorkerURLs, p)
		}
	}
}

//export SetSecret
func SetSecret(cSecret *C.char) {
	s := C.GoString(cSecret)
	if len(s) != 32 {
		return
	}
	if _, err := hex.DecodeString(s); err != nil {
		return
	}
	proxySecretMu.Lock()
	proxySecret = s
	proxySecretMu.Unlock()
}

//export GetStats
func GetStats() *C.char {
	return C.CString(stats.Summary())
}

//export GetLogs
func GetLogs() *C.char {
	logRingMu.Lock()
	lines := logRing
	logRing = nil
	logRingMu.Unlock()

	return C.CString(strings.Join(lines, "\n"))
}

//export SetFakeSni
func SetFakeSni(enabled C.int, cValue *C.char) {
	fakeSniMu.Lock()
	defer fakeSniMu.Unlock()
	warnFakeSniOnce = sync.Once{}
	fakeSniEnabled = int(enabled) != 0
	fakeSniValue = strings.TrimSpace(C.GoString(cValue))
}

//export SetTlsFingerprint
func SetTlsFingerprint(fp C.int) {
	tlsFingerprintMu.Lock()
	defer tlsFingerprintMu.Unlock()
	if v := int(fp); v >= tlsFpGo && v <= tlsFpRandom {
		tlsFingerprint = v
	}
}

//export SetFragmentConfig
func SetFragmentConfig(enabled C.int, firstSize C.int, delayMs C.int) {
	fragmentMu.Lock()
	defer fragmentMu.Unlock()

	fragmentEnabled = int(enabled) != 0
	if v := int(firstSize); v > 0 && v < 64 {
		fragmentFirstSize = v
	}
	if v := int(delayMs); v >= 0 && v <= 200 {
		fragmentDelayMs = v
	}
}

//export SetFakeTls
func SetFakeTls(enabled C.int, cDomain *C.char, cMaskHost *C.char) {
	fakeTlsMu.Lock()
	defer fakeTlsMu.Unlock()

	fakeTlsEnabled = int(enabled) != 0
	fakeTlsDomain = strings.TrimSpace(C.GoString(cDomain))
	fakeTlsMaskHost = strings.TrimSpace(C.GoString(cMaskHost))
}

//export SetDohConfig
func SetDohConfig(cUseCloudflare, cUseGoogle, cUseQuad9, cUseAdguard C.int, cCustomURL *C.char) {
	dohConfigMu.Lock()
	defer dohConfigMu.Unlock()

	var eps []string
	if int(cUseCloudflare) != 0 {
		eps = append(eps, "https://cloudflare-dns.com/dns-query")
	}
	if int(cUseGoogle) != 0 {
		eps = append(eps, "https://dns.google/dns-query")
	}
	if int(cUseQuad9) != 0 {
		eps = append(eps, "https://dns.quad9.net/dns-query")
	}
	if int(cUseAdguard) != 0 {
		eps = append(eps, "https://dns.adguard-dns.com/dns-query")
	}
	custom := strings.TrimSpace(C.GoString(cCustomURL))
	if custom != "" {
		eps = append(eps, custom)
	}
	dohEndpoints = eps
}

//export GetSecretWithPrefix
func GetSecretWithPrefix() *C.char {
	proxySecretMu.RLock()
	sec := proxySecret
	proxySecretMu.RUnlock()

	fakeTlsMu.RLock()
	tlsOn := fakeTlsEnabled
	tlsDom := fakeTlsDomain
	fakeTlsMu.RUnlock()

	var result string
	if tlsOn && tlsDom != "" {
		domHex := hex.EncodeToString([]byte(tlsDom))
		result = "ee" + sec + domHex
	} else {
		result = "dd" + sec
	}
	return C.CString(result)
}

//export FreeString
func FreeString(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {
	runtime.LockOSThread()
	initLogging(true)
	initCfproxyDomains()

	dcOptMap := map[int]string{
		2: "149.154.167.220",
		4: "149.154.167.220",
	}

	ctx, cancel := context.WithCancel(context.Background())
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		cancel()
	}()

	_ = runProxy(ctx, "127.0.0.1", defaultPort, dcOptMap, nil)
}
