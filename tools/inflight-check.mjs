#!/usr/bin/env node
// In-flight LayerZero message check — RUN BEFORE severing a peer, zeroing a rate limit, or
// swapping the DVN set on a pathway.
//
// Two distinct hazards, two distinct metrics:
//
//   SEVER (setPeer=0 / inbound rate 0) strands any message already sent from the source (tokens
//   burned/locked) but not yet EXECUTED on the destination: lzReceive reverts (NoPeer / rate-limit).
//   Metric: source outboundNonce - destination lazyInboundNonce (highest executed nonce).
//
//   DVN SWAP (setConfig ULN type 2) strands any message not yet VERIFIED on the destination: the
//   receive library re-checks the CURRENT required-DVN set at commitVerification, so a packet the
//   outgoing DVN already attested no longer counts and the new DVN never saw it. A packet that is
//   verified but not yet executed is safe — execution does not re-check the DVN set.
//   Metric: source outboundNonce - destination inboundNonce (highest contiguous verified nonce).
//
//   node tools/inflight-check.mjs                 # #585 sever paths, both directions
//   node tools/inflight-check.mjs op:scroll bnb:swell
//   node tools/inflight-check.mjs --dvn           # every pathway in the Canary->P2P swap
// Exit code 1 if any checked path has in-flight messages.
import { execFile, execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
loadDotEnv(resolve(ROOT, ".env"));
const K = process.env.ALCHEMY_API_KEY;
const cast = (...a) => execFileSync("cast", a, { encoding: "utf8" }).trim();
const castAsync = async (...a) => (await execFileAsync("cast", a, { encoding: "utf8" })).stdout.trim();
const b32 = a => "0x000000000000000000000000" + a.slice(2).toLowerCase();
const u64 = s => BigInt(s.split(/\s+/)[0]);

/** Populate process.env from a .env file without overriding already-exported vars. */
function loadDotEnv(path) {
  let raw;
  try { raw = readFileSync(path, "utf8"); } catch { return; }
  for (const line of raw.split("\n")) {
    const m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!m || line.trimStart().startsWith("#")) continue;
    if (process.env[m[1]] === undefined) process.env[m[1]] = m[2].trim().replace(/^["']|["']$/g, "");
  }
}

const OFT = {op: "0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF", bnb: "0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A",
  linea: "0x1Bf74C010E6320bab11e2e5A532b5AC15e0b8aA6", unichain: "0x7DCC39B4d1C53CB31e1aBc0e358b43987FEF80f7",
  hyperEVM: "0xA3D68b74bF0528fdD07263c60d6488749044914b", base: "0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A",
  scroll: "0x01f0a31698C4d065659b9bdC21B3610292a1c506", swell: "0xA6cB988942610f6731e664379D15fFcfBf282b44",
  bera: "0x7DCC39B4d1C53CB31e1aBc0e358b43987FEF80f7", zksync: "0xc1Fa6E2E8667d9bE0Ca938a54c7E0285E9Df924a",
  mode: "0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A", blast: "0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A",
  morph: "0x7DCC39B4d1C53CB31e1aBc0e358b43987FEF80f7", sonic: "0xA3D68b74bF0528fdD07263c60d6488749044914b",
  ethereum: "0xcd2eb13D6831d4602D80E5db9230A57596CDCA63"};
const EID = {ethereum: 30101, base: 30184, op: 30111, bnb: 30102, blast: 30243, mode: 30260, linea: 30183,
  zksync: 30165, swell: 30335, morph: 30322, scroll: 30214, bera: 30362, unichain: 30320, hyperEVM: 30367, sonic: 30332};
const ALCHEMY = {op: "opt-mainnet", bnb: "bnb-mainnet", linea: "linea-mainnet", unichain: "unichain-mainnet",
  base: "base-mainnet", scroll: "scroll-mainnet", bera: "berachain-mainnet", mode: "mode-mainnet",
  blast: "blast-mainnet", sonic: "sonic-mainnet", ethereum: "eth-mainnet", zksync: "zksync-mainnet",
  avax: "avax-mainnet", ink: "ink-mainnet", monad: "monad-mainnet"};
const RPC = Object.fromEntries(Object.keys(OFT).map(c => [c, ALCHEMY[c] && K
  ? `https://${ALCHEMY[c]}.g.alchemy.com/v2/${K}` : undefined]));
Object.assign(RPC, {swell: "https://rpc.ankr.com/swell", morph: "https://rpc.morphl2.io",
  hyperEVM: "https://rpc.hyperliquid.xyz/evm"});
// #585 sever set (deprecated chain -> the peers it severs). Sonic full-sever includes ethereum.
const SEVER_DEP = {scroll: ["base", "op", "bnb", "linea", "unichain", "hyperEVM"], swell: ["base", "op", "bnb", "linea", "unichain"],
  bera: ["base", "op", "bnb", "linea", "unichain", "hyperEVM"], zksync: ["base", "op", "bnb", "linea", "unichain"],
  mode: ["base", "op", "bnb", "linea", "unichain"], blast: ["base", "op", "bnb", "linea", "unichain"],
  morph: ["base", "op", "bnb", "linea", "unichain"], sonic: ["base", "ethereum"]};

/**
 * Load the Canary->P2P swap scope from the fork-replay fixture, so the checked pathway set is the
 * same one the proposals actually reconfigure. Self-EIDs are read from each endpoint on-chain
 * rather than hardcoded.
 */
async function loadDvnScope() {
  const fx = JSON.parse(readFileSync(resolve(ROOT, "test/fixtures/dvn-canary-to-p2p.json"), "utf8"));
  for (const c of fx.chains) {
    OFT[c.name] = c.oft;
    RPC[c.name] = process.env[c.rpcEnv] || (ALCHEMY[c.name] && K
      ? `https://${ALCHEMY[c.name]}.g.alchemy.com/v2/${K}` : undefined) || c.rpcFallback;
    if (!RPC[c.name]) throw new Error(`no RPC for ${c.name} (set ${c.rpcEnv})`);
    epCache[c.name] = c.endpoint;
  }
  const selfEids = await Promise.all(fx.chains.map(c =>
    castAsync("call", c.endpoint, "eid()(uint32)", "--rpc-url", RPC[c.name]).then(u64)));
  fx.chains.forEach((c, i) => { EID[c.name] = Number(selfEids[i]); });
  const byEid = Object.fromEntries(fx.chains.map(c => [EID[c.name], c.name]));

  const pairs = [], seen = new Set();
  for (const c of fx.chains) {
    for (const eid of c.eids) {
      const peer = byEid[eid];
      if (!peer) throw new Error(`${c.name} configures eid ${eid}, which is not in the swap scope`);
      const key = [c.name, peer].sort().join(":");
      if (!seen.has(key)) { seen.add(key); pairs.push([c.name, peer]); }
    }
  }
  return pairs;
}

const epCache = {};
const endpoint = c => (epCache[c] ??= cast("call", OFT[c], "endpoint()(address)", "--rpc-url", RPC[c]));

/** Nonce triple for one direction: sent on src, verified on dst, executed on dst. */
async function probe(src, dst) {
  const [sent, verified, executed] = await Promise.all([
    castAsync("call", endpoint(src), "outboundNonce(address,uint32,bytes32)(uint64)",
      OFT[src], String(EID[dst]), b32(OFT[dst]), "--rpc-url", RPC[src]).then(u64),
    castAsync("call", endpoint(dst), "inboundNonce(address,uint32,bytes32)(uint64)",
      OFT[dst], String(EID[src]), b32(OFT[src]), "--rpc-url", RPC[dst]).then(u64),
    castAsync("call", endpoint(dst), "lazyInboundNonce(address,uint32,bytes32)(uint64)",
      OFT[dst], String(EID[src]), b32(OFT[src]), "--rpc-url", RPC[dst]).then(u64),
  ]);
  return {sent, verified, executed, unverified: sent - verified, undelivered: sent - executed};
}

/** Run `fn` over `items` with bounded concurrency, preserving input order. */
async function pool(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({length: Math.min(limit, items.length)}, async () => {
    while (next < items.length) { const i = next++; out[i] = await fn(items[i]); }
  }));
  return out;
}

const args = process.argv.slice(2);
const dvn = args.includes("--dvn");
const explicit = args.filter(a => a !== "--dvn");
const pairs = explicit.length ? explicit.map(a => a.split(":"))
  : dvn ? await loadDvnScope()
  : Object.entries(SEVER_DEP).flatMap(([d, ps]) => ps.map(p => [d, p]));

const directed = pairs.flatMap(([a, b]) => [[a, b], [b, a]]);
const rows = await pool(directed, 8, async ([src, dst]) => {
  const path = `${src} -> ${dst}`;
  if (!OFT[src] || !OFT[dst]) return {path, status: "unknown chain"};
  try {
    const r = await probe(src, dst);
    const risk = dvn ? r.unverified : r.undelivered;
    return {path, sent: r.sent.toString(), verified: r.verified.toString(), executed: r.executed.toString(),
      unverified: r.unverified.toString(), undelivered: r.undelivered.toString(),
      status: risk > 0n ? "⚠️ DRAIN FIRST" : "✅ clear"};
  } catch (e) { return {path, status: "err: " + e.message.split("\n")[0].slice(0, 60)}; }
});

const blocked = rows.filter(r => r.status?.startsWith("⚠️"));
const errored = rows.filter(r => r.status?.startsWith("err:") || r.status === "unknown chain");
console.table(rows);
console.log(`\n${rows.length} directed paths checked (${pairs.length} pathways).`);
if (errored.length) console.log(`⚠️  ${errored.length} path(s) could not be read — treat as UNKNOWN, not clear.`);
console.log(blocked.length
  ? dvn
    ? `\n⚠️  ${blocked.length} path(s) have UNVERIFIED messages — do NOT swap the DVN set yet. Wait for the destination to verify, then re-check.`
    : `\n⚠️  ${blocked.length} path(s) have UNDELIVERED messages — do NOT hard-sever. Zero OUTBOUND only, wait for drain, then sever.`
  : dvn
    ? "\n✅ Every pathway in the swap is fully verified (0 unverified) — safe to execute the DVN swap."
    : "\n✅ All checked paths are drained (0 in-flight) — safe to sever / zero rate limits.");
process.exit(blocked.length || errored.length ? 1 : 0);
