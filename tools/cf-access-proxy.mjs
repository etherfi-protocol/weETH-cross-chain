#!/usr/bin/env node
// Local proxy for an explorer behind Cloudflare Access.
//
// Arc's Blockscout (explorer.arc.io) is gated by Circle's Cloudflare Access, so an unauthenticated
// request 302s to circle.cloudflareaccess.com. `forge verify-contract` cannot send an auth header
// or cookie, so it can never reach the API directly. This proxy sits in front: forge talks to
// 127.0.0.1, the proxy attaches the Access credential and forwards upstream.
//
// Credential, whichever you have (env):
//   CF_AUTHORIZATION                            the CF_Authorization cookie from a logged-in browser
//   CF_ACCESS_CLIENT_ID + CF_ACCESS_CLIENT_SECRET   a Cloudflare Access service token
//
// Usage:
//   CF_AUTHORIZATION=<cookie> node tools/cf-access-proxy.mjs --upstream https://explorer.arc.io
//   forge verify-contract … --verifier blockscout --verifier-url http://127.0.0.1:8555/api/
import http from "node:http";

const arg = (name, dflt) => {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? dflt : process.argv[i + 1];
};

const UPSTREAM = (arg("upstream", "https://explorer.arc.io") || "").replace(/\/$/, "");
const PORT = Number(arg("port", "8555"));
const COOKIE = process.env.CF_AUTHORIZATION || "";
const CID = process.env.CF_ACCESS_CLIENT_ID || "";
const CSECRET = process.env.CF_ACCESS_CLIENT_SECRET || "";

if (!COOKIE && !(CID && CSECRET)) {
  console.error("ERROR: set CF_AUTHORIZATION, or both CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET");
  process.exit(1);
}

const MIN_GAP_MS = Number(arg("min-gap", "400"));
const MAX_RETRIES = Number(arg("max-retries", "6"));

/** Access credentials for the upstream request. A service token takes precedence over a cookie. */
function authHeaders() {
  if (CID && CSECRET) return { "CF-Access-Client-Id": CID, "CF-Access-Client-Secret": CSECRET };
  return { cookie: `CF_Authorization=${COOKIE}` };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Blockscout rate-limits per IP and answers 429 with a plain-text body. forge surfaces that as
// "Response result is unexpectedly empty", which points nowhere. Serialise upstream calls and
// back off here so a burst of verifications degrades into waiting rather than failing.
let chain = Promise.resolve();
let lastAt = 0;
function serialize(fn) {
  const run = chain.then(async () => {
    const gap = Date.now() - lastAt;
    if (gap < MIN_GAP_MS) await sleep(MIN_GAP_MS - gap);
    try { return await fn(); } finally { lastAt = Date.now(); }
  });
  chain = run.catch(() => {});
  return run;
}

async function fetchWithBackoff(url, init) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, init);
    if (res.status !== 429 || attempt >= MAX_RETRIES) return res;
    const retryAfter = Number(res.headers.get("retry-after"));
    const wait = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : Math.min(2 ** attempt * 1000, 30000);
    console.error(`  429 from upstream, retrying in ${wait}ms (attempt ${attempt + 1}/${MAX_RETRIES})`);
    await sleep(wait);
  }
}

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", async () => {
    const body = Buffer.concat(chunks);
    const url = UPSTREAM + req.url;
    // Drop hop-by-hop and host headers; the upstream must see its own host for Access to match.
    const headers = { ...req.headers, ...authHeaders() };
    delete headers.host;
    delete headers.connection;
    delete headers["content-length"];

    try {
      const upstream = await serialize(() =>
        fetchWithBackoff(url, {
          method: req.method,
          headers,
          body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
          redirect: "manual",
        })
      );

      // A 302 to cloudflareaccess.com means the credential was rejected. Say so loudly rather
      // than handing forge an HTML login page it will report as an opaque verification failure.
      const loc = upstream.headers.get("location") || "";
      if (upstream.status === 302 && loc.includes("cloudflareaccess.com")) {
        console.error(`AUTH FAILED on ${req.method} ${req.url} — credential rejected or expired`);
        res.writeHead(401, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "cloudflare access rejected the credential" }));
        return;
      }

      const buf = Buffer.from(await upstream.arrayBuffer());
      if (upstream.status === 429) {
        console.error(`STILL 429 after ${MAX_RETRIES} retries — raise --min-gap or wait for the window to reset`);
      }
      console.log(`${req.method} ${req.url} -> ${upstream.status} (${buf.length}b)`);
      res.writeHead(upstream.status, {
        "content-type": upstream.headers.get("content-type") || "application/json",
      });
      res.end(buf);
    } catch (e) {
      console.error(`proxy error on ${req.method} ${req.url}: ${e.message}`);
      res.writeHead(502, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: e.message }));
    }
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`cf-access-proxy -> ${UPSTREAM}`);
  console.log(`listening on http://127.0.0.1:${PORT}  (auth: ${CID ? "service token" : "browser cookie"})`);
  console.log(`use: --verifier blockscout --verifier-url http://127.0.0.1:${PORT}/api/`);
});
