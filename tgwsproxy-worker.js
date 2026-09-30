// Cloudflare Worker — MTProto relay for tg-ws-proxy-ios.
//
//   GET /apiws?dst=<telegram-dc-ip>&dc=<n>&media=<0|1>  + WebSocket upgrade
//
// The app passes the DC's own MTProto address as `dst` (the same one its
// tcpFallback() uses — not the kwsN.web.telegram.org gateway from Settings,
// which only speaks TLS); this Worker stays a dumb byte relay: plain TCP to
// dst:443, no TLS, raw MTProto. It's compatible with upstream's query format,
// so upstream's Worker script works with the app too.
//
// IMPORTANT STRUCTURAL DETAIL: the "message" listener is attached on the very
// next line after connect(), with no `await` in between. connect() returns
// immediately (the TCP handshake finishes in the background), so nothing can
// arrive from the client while the socket is still being set up. An earlier
// revision awaited a write before attaching the listener, which lost the
// client's 64-byte MTProto handshake and hung the session forever.

import { connect } from "cloudflare:sockets";

// Only Telegram's published DC ranges may be dialed. Without this the Worker
// is an open TCP-CONNECT proxy to any host on :443 that anyone who finds the
// URL can abuse — which is both an abuse magnet and a Cloudflare ToS problem
// that gets accounts suspended.
//
// dst must be a literal IPv4 address: connect() also accepts hostnames, so a
// plain prefix check let "91.108.attacker.example" straight through.
const ALLOWED_CIDRS = [
  "149.154.160.0/20",
  "91.108.0.0/16",
  "95.161.64.0/20",
  "91.105.192.0/23",
  "185.76.151.0/24",
];

function ipv4ToInt(s) {
  const parts = s.split(".");
  if (parts.length !== 4) return null;
  let n = 0;
  for (const p of parts) {
    if (!/^\d{1,3}$/.test(p)) return null;
    const v = Number(p);
    if (v > 255) return null;
    n = n * 256 + v;
  }
  return n;
}

const ALLOWED_RANGES = ALLOWED_CIDRS.map((cidr) => {
  const [base, bits] = cidr.split("/");
  const size = 2 ** (32 - Number(bits));
  const start = Math.floor(ipv4ToInt(base) / size) * size;
  return [start, start + size];
});

function isAllowedDst(dst) {
  const ip = ipv4ToInt(dst);
  return ip !== null && ALLOWED_RANGES.some(([lo, hi]) => ip >= lo && ip < hi);
}

// Since the 2026-03-17 compatibility date (websocket_standard_binary_type)
// binary frames arrive as Blob unless binaryType is set to "arraybuffer".
// The old version of this function had no Blob branch and silently turned
// every frame into zero bytes: the Worker "connected" but Telegram never got
// a single byte (up=0B in the Worker logs). binaryType is set below; the Blob
// branch stays as a safety net.
async function toBytes(data) {
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (ArrayBuffer.isView(data)) {
    return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  }
  if (typeof data === "string") return new TextEncoder().encode(data);
  if (data && typeof data.arrayBuffer === "function") {
    return new Uint8Array(await data.arrayBuffer());
  }
  return new Uint8Array(0);
}

export default {
  async fetch(request) {
    if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
      return new Response("Expected websocket", { status: 426 });
    }

    const url = new URL(request.url);
    if (url.pathname !== "/apiws") {
      return new Response("Not found", { status: 404 });
    }

    const dst = url.searchParams.get("dst");
    if (!dst || !isAllowedDst(dst)) {
      console.log(`REJECT dst=${dst} (not a Telegram address)`);
      return new Response("Bad dst", { status: 400 });
    }

    const dc = url.searchParams.get("dc") || "?";
    const media = url.searchParams.get("media") === "1" ? "m" : "";
    const tag = `dc=${dc}${media}`;

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    // Must be set before accept(), see toBytes().
    server.binaryType = "arraybuffer";
    server.accept();

    const socket = connect({ hostname: dst, port: 443 });
    const tcpReader = socket.readable.getReader();
    const tcpWriter = socket.writable.getWriter();

    let up = 0;
    let down = 0;
    let failed = false;
    console.log(`[${tag}] relay open -> ${dst}:443`);

    // Nothing else awaits these two promises, so a socket error (Cloudflare
    // shedding a long-lived session, Telegram resetting) surfaced as an
    // unhandled "internal error" at the end of every session.
    socket.opened.then(
      () => console.log(`[${tag}] tcp connected`),
      (err) => console.log(`[${tag}] tcp connect failed: ${err}`),
    );
    socket.closed.catch(() => {});

    // MTProto is a byte stream: frames must reach the socket in the order
    // they arrived. Each handler runs as its own async task, so writes are
    // chained explicitly instead of racing each other through the awaits.
    let writes = Promise.resolve();
    server.addEventListener("message", (event) => {
      writes = writes.then(async () => {
        if (failed) return;
        const buf = await toBytes(event.data);
        if (buf.byteLength === 0) return;
        up += buf.byteLength;
        await tcpWriter.write(buf);
      }).catch((err) => {
        failed = true;
        console.log(`[${tag}] tcp write failed after up=${up}B: ${err}`);
        try { server.close(1011, "tcp write failed"); } catch {}
      });
    });

    server.addEventListener("close", async () => {
      console.log(`[${tag}] client closed (up=${up}B down=${down}B)`);
      try { await tcpWriter.close(); } catch {}
      try { socket.close(); } catch {}
    });

    (async () => {
      try {
        for (;;) {
          const { value, done } = await tcpReader.read();
          if (done) break;
          if (value) {
            down += value.byteLength;
            server.send(value);
          }
        }
        console.log(`[${tag}] upstream EOF (up=${up}B down=${down}B)`);
      } catch (err) {
        console.log(`[${tag}] upstream error (up=${up}B down=${down}B): ${err}`);
      } finally {
        try { server.close(); } catch {}
        try { tcpReader.releaseLock(); } catch {}
        try { socket.close(); } catch {}
      }
    })();

    return new Response(null, { status: 101, webSocket: client });
  },
};
