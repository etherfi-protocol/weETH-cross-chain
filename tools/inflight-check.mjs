#!/usr/bin/env node
// In-flight LayerZero message check — RUN BEFORE severing a peer or zeroing a rate limit on a path.
// A hard sever (setPeer=0 or inbound-rate=0) strands any message already sent from the source
// (tokens burned/locked) but not yet delivered on the destination: lzReceive reverts (NoPeer /
// rate-limit) and the transfer is stuck until governance restores the peer to deliver + re-severs.
// This tool compares, per path+direction, the source endpoint's outboundNonce vs the destination
// endpoint's lazyInboundNonce; a positive gap = undelivered (in-flight) messages → DO NOT hard-sever
// yet (drain first: zero OUTBOUND only, keep peer+inbound, wait, then sever).
//
//   node tools/inflight-check.mjs                 # checks all #585 sever paths (both directions)
//   node tools/inflight-check.mjs op:scroll bnb:swell   # check specific src:dst paths
// Exit code 1 if any path has in-flight messages.
import {execFileSync} from "node:child_process";
const K = process.env.ALCHEMY_API_KEY;
const cast = (...a) => execFileSync("cast", a, {encoding: "utf8"}).trim();
const b32 = a => "0x000000000000000000000000" + a.slice(2).toLowerCase();

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
const RPC = {op: `https://opt-mainnet.g.alchemy.com/v2/${K}`, bnb: `https://bnb-mainnet.g.alchemy.com/v2/${K}`,
  linea: `https://linea-mainnet.g.alchemy.com/v2/${K}`, unichain: `https://unichain-mainnet.g.alchemy.com/v2/${K}`,
  base: `https://base-mainnet.g.alchemy.com/v2/${K}`, scroll: `https://scroll-mainnet.g.alchemy.com/v2/${K}`,
  bera: `https://berachain-mainnet.g.alchemy.com/v2/${K}`, mode: `https://mode-mainnet.g.alchemy.com/v2/${K}`,
  blast: `https://blast-mainnet.g.alchemy.com/v2/${K}`, sonic: `https://sonic-mainnet.g.alchemy.com/v2/${K}`,
  ethereum: `https://eth-mainnet.g.alchemy.com/v2/${K}`, zksync: `https://zksync-mainnet.g.alchemy.com/v2/${K}`,
  swell: "https://rpc.ankr.com/swell", morph: "https://rpc.morphl2.io", hyperEVM: "https://rpc.hyperliquid.xyz/evm"};
// #585 sever set (deprecated chain -> the peers it severs). Sonic full-sever includes ethereum.
const SEVER_DEP = {scroll: ["base", "op", "bnb", "linea", "unichain", "hyperEVM"], swell: ["base", "op", "bnb", "linea", "unichain"],
  bera: ["base", "op", "bnb", "linea", "unichain", "hyperEVM"], zksync: ["base", "op", "bnb", "linea", "unichain"],
  mode: ["base", "op", "bnb", "linea", "unichain"], blast: ["base", "op", "bnb", "linea", "unichain"],
  morph: ["base", "op", "bnb", "linea", "unichain"], sonic: ["base", "ethereum"]};

const epCache = {};
const endpoint = c => (epCache[c] ??= cast("call", OFT[c], "endpoint()(address)", "--rpc-url", RPC[c]));
// undelivered messages src -> dst
function inflight(src, dst) {
  const sent = BigInt(cast("call", endpoint(src), "outboundNonce(address,uint32,bytes32)(uint64)", OFT[src], String(EID[dst]), b32(OFT[dst]), "--rpc-url", RPC[src]).split(" ")[0]);
  const got = BigInt(cast("call", endpoint(dst), "lazyInboundNonce(address,uint32,bytes32)(uint64)", OFT[dst], String(EID[src]), b32(OFT[src]), "--rpc-url", RPC[dst]).split(" ")[0]);
  return {sent, got, flight: sent - got};
}

const args = process.argv.slice(2);
const pairs = args.length
  ? args.map(a => a.split(":"))
  : Object.entries(SEVER_DEP).flatMap(([d, ps]) => ps.map(p => [d, p]));

let anyFlight = false;
const rows = [];
for (const [a, b] of pairs) {
  if (!OFT[a] || !OFT[b]) { rows.push({path: `${a}->${b}`, note: "unknown chain"}); continue; }
  for (const [src, dst] of [[a, b], [b, a]]) {
    try {
      const {sent, got, flight} = inflight(src, dst);
      if (flight > 0n) anyFlight = true;
      rows.push({path: `${src} -> ${dst}`, sent: sent.toString(), delivered: got.toString(),
        inflight: flight.toString(), status: flight > 0n ? "⚠️ DRAIN FIRST" : "✅ clear"});
    } catch (e) { rows.push({path: `${src} -> ${dst}`, status: "err: " + e.message.split("\n")[0].slice(0, 40)}); }
  }
}
console.table(rows);
console.log(anyFlight
  ? "\n⚠️  In-flight messages found — do NOT hard-sever these paths. Zero OUTBOUND only, wait for drain, then sever."
  : "\n✅ All checked paths are drained (0 in-flight) — safe to sever / zero rate limits.");
process.exit(anyFlight ? 1 : 0);
