#!/usr/bin/env node
// Generate a reviewer-facing DEPLOYMENT VERIFICATION REPORT (markdown) for a chain
// onboarded to the weETH OFT mesh. Reads live on-chain state via `cast` and writes,
// per check, a ✅/❌ with the expected value, the on-chain value, AND the command to
// re-run it — plus links to the relevant explorer / Safe app / external docs.
//
// Scope: the new chain in full (deployment, ownership/authority, timelock, controller
// Safe, per-pathway peers/limits/enforced-options/DVN) AND the reverse-peer acceptance
// on each existing peer chain (Eth/Base/OP) for the new chain's EID.
//
// Usage:
//   node tools/verify-deployment.mjs --chain robinhood
//     [--rpc <url>] [--peer-rpc ethereum=<url> --peer-rpc base=<url> --peer-rpc op=<url>]
//     [--out <path.md>]
//
// RPC resolution per chain: --rpc / --peer-rpc <key>=<url>  >  .env <KEY>_MAINNET_RPC_URL
//   >  built-in public fallback (eth/base/op only). The report is a point-in-time
//   snapshot; the generated-at timestamp makes staleness visible.

import {readFileSync, writeFileSync, mkdirSync, existsSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {execFileSync} from "node:child_process";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ENFORCED_OPTS = "0x00030100110100000000000000000000000000029810"; // 170k lzReceive, type-3
const ULN_CONFIRMATIONS = "45";
// EIP-1967 slots (TransparentUpgradeableProxy)
const IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
const ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
// OZ TimelockController role ids
const ROLES = {
  PROPOSER: "0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1",
  EXECUTOR: "0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63",
  CANCELLER: "0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783",
};
const ZERO = "0x0000000000000000000000000000000000000000";
const EXPLORERS = {
  1: "https://etherscan.io", 10: "https://optimistic.etherscan.io", 56: "https://bscscan.com",
  8453: "https://basescan.org", 4663: "https://8crv4vmq6tiu1yqr.blockscout.com",
};
const SAFE_PREFIX = {1: "eth", 10: "oeth", 56: "bnb", 8453: "base"}; // app.safe.global chain short-name
const PUBLIC_RPC = {1: "https://eth.llamarpc.com", 10: "https://mainnet.optimism.io", 8453: "https://mainnet.base.org"};
const ALCHEMY_HOST = {1: "eth-mainnet", 10: "opt-mainnet", 8453: "base-mainnet"};
const DOC_LINKS = [
  ["LayerZero V2 — deployed endpoints & message libraries", "https://docs.layerzero.network/v2/deployments/deployed-contracts"],
  ["LayerZero V2 — DVN addresses", "https://docs.layerzero.network/v2/deployments/dvn-addresses"],
  ["LayerZero V2 — security stack (DVNs / ULN config)", "https://docs.layerzero.network/v2/concepts/modular-security/security-stack-dvns"],
  ["OpenZeppelin TimelockController", "https://docs.openzeppelin.com/contracts/5.x/api/governance#TimelockController"],
  ["Safe — smart account docs", "https://docs.safe.global/"],
  ["weETH Cross-Chain L2 Roles (Notion)", "https://www.notion.so/etherfi/weETH-Cross-Chain-L2-Roles-11ab09527c4380148ed5ec6a4f869677"],
  ["LayerZero Scan (cross-chain message explorer)", "https://layerzeroscan.com/"],
];

function parseArgs(argv) {
  const a = {peerRpc: {}};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k === "--peer-rpc") {
      const [key, ...rest] = (argv[++i] || "").split("=");
      a.peerRpc[key] = rest.join("=");
    } else if (k.startsWith("--")) {
      a[k.slice(2)] = argv[++i];
    }
  }
  return a;
}
function loadEnv() {
  const p = resolve(REPO_ROOT, ".env");
  const env = {};
  if (!existsSync(p)) return env;
  for (const line of readFileSync(p, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
    if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, "").trim();
  }
  return env;
}
const cast = (args) => execFileSync("cast", args, {encoding: "utf8", stdio: ["ignore", "pipe", "ignore"]}).trim();
function call(to, sig, rpc, ...args) {
  try {
    return cast(["call", to, sig, ...args, "--rpc-url", rpc]);
  } catch {
    return null;
  }
}
const word = (out) => (out === null ? null : out.split(/\s+/)[0]);
const hasCode = (addr, rpc) => {
  try {
    return cast(["code", addr, "--rpc-url", rpc]).replace(/^0x/, "").length > 0;
  } catch {
    return null;
  }
};
const eqAddr = (a, b) => a !== null && b !== null && a.toLowerCase() === b.toLowerCase();
const bytes32Addr = (addr) => "0x" + "0".repeat(24) + addr.replace(/^0x/, "").toLowerCase();
const slotAddr = (val) => (val === null ? null : "0x" + val.replace(/^0x/, "").slice(24).toLowerCase());
const ulnExpected = (dvns) =>
  cast(["abi-encode", "f((uint64,uint8,uint8,uint8,address[],address[]))", `(${ULN_CONFIRMATIONS},4,0,0,[${dvns.join(",")}],[])`]);

// A check row: {name, expected, actual, ok, cmd}. ok: true|false|null (null = could not read).
const row = (name, expected, actual, ok, cmd) => ({name, expected, actual, ok, cmd});
const short = (v) => {
  if (v === null || v === undefined) return "—";
  const s = String(v);
  return s.length > 26 ? `${s.slice(0, 12)}…${s.slice(-8)}` : s;
};
const mark = (ok) => (ok === true ? "✅" : ok === false ? "❌" : "⚠️");

function rpcFor(key, chainId, overrides, env) {
  if (overrides[key]) return overrides[key];
  const named = env[`${key.toUpperCase()}_MAINNET_RPC_URL`];
  if (named) return named;
  // Build an Alchemy URL from the key in .env for the common peers (kept out of the report).
  if (env.ALCHEMY_API_KEY && ALCHEMY_HOST[chainId]) return `https://${ALCHEMY_HOST[chainId]}.g.alchemy.com/v2/${env.ALCHEMY_API_KEY}`;
  return PUBLIC_RPC[chainId] || null;
}
function explorerLink(chainId, addr, label) {
  const base = EXPLORERS[chainId];
  return base ? `[${label || short(addr)}](${base}/address/${addr})` : `\`${addr}\``;
}
function safeLink(chainId, safe) {
  const pre = SAFE_PREFIX[chainId];
  return pre ? `[Safe app](https://app.safe.global/home?safe=${pre}:${safe})` : "_no Safe web UI on this chain_";
}

// ---- check builders: each returns {title, rows} ----

function checkDeployment(c, rpc, policy) {
  const cid = Number(c.CHAIN_ID);
  const canon = policy.canonical;
  const rows = [];
  const codeRow = (label, addr) => {
    const present = hasCode(addr, rpc);
    return row(`${label} has code`, "deployed", present === null ? null : present ? "yes" : "no", present, `cast code ${addr} --rpc-url $RPC`);
  };
  rows.push(codeRow("OFT proxy", c.OFT));
  rows.push(codeRow("OFT implementation", c.OFT_IMPL));
  rows.push(codeRow("ProxyAdmin", c.PROXY_ADMIN));
  rows.push(codeRow("Timelock", c.TIMELOCK));
  rows.push(codeRow("Controller Safe", c.CONTROLLER_SAFE));
  if (cid !== 1) {
    // canonical CREATE3 address match (new L2 deploys only; L1 adapter predates the scheme)
    const m = (label, addr, want) => row(`${label} == canonical`, want, addr, eqAddr(addr, want), "# registry/chains.json vs policy.json canonical");
    rows.push(m("OFT", c.OFT, canon.oft));
    rows.push(m("OFT impl", c.OFT_IMPL, canon.oftImpl));
    rows.push(m("ProxyAdmin", c.PROXY_ADMIN, canon.proxyAdmin));
    rows.push(m("Timelock", c.TIMELOCK, canon.timelock));
  }
  // proxy wiring (EIP-1967 slots): implementation + admin
  const impl = slotAddr(loadSlot(c.OFT, IMPL_SLOT, rpc));
  const admin = slotAddr(loadSlot(c.OFT, ADMIN_SLOT, rpc));
  rows.push(row("proxy implementation slot", c.OFT_IMPL, impl, eqAddr(impl, c.OFT_IMPL),
    `cast storage ${c.OFT} ${IMPL_SLOT} --rpc-url $RPC`));
  rows.push(row("proxy admin slot", c.PROXY_ADMIN, admin, eqAddr(admin, c.PROXY_ADMIN),
    `cast storage ${c.OFT} ${ADMIN_SLOT} --rpc-url $RPC`));
  return {title: "1. Deployment & addresses", rows};
}
const loadSlot = (addr, slot, rpc) => {
  try {
    return cast(["storage", addr, slot, "--rpc-url", rpc]);
  } catch {
    return null;
  }
};

function checkAuthority(c, rpc) {
  const tl = c.TIMELOCK;
  const r = [];
  const owner = word(call(c.OFT, "owner()(address)", rpc));
  r.push(row("OFT.owner == timelock", tl, owner, eqAddr(owner, tl), `cast call ${c.OFT} 'owner()(address)' --rpc-url $RPC`));
  const paOwner = word(call(c.PROXY_ADMIN, "owner()(address)", rpc));
  r.push(row("ProxyAdmin.owner == timelock", tl, paOwner, eqAddr(paOwner, tl), `cast call ${c.PROXY_ADMIN} 'owner()(address)' --rpc-url $RPC`));
  const delegate = word(call(c.L2_ENDPOINT, "delegates(address)(address)", rpc, c.OFT));
  r.push(row("endpoint.delegates(OFT) == timelock", tl, delegate, eqAddr(delegate, tl),
    `cast call ${c.L2_ENDPOINT} 'delegates(address)(address)' ${c.OFT} --rpc-url $RPC`));
  // pauser = EOA, unpauser = Safe. These are held via the OFT's role registry (role ids are
  // small indices, not keccak hashes), which `cast` can't enumerate generically — defer to the
  // authoritative forge verifier rather than emit a brittle/incorrect read here.
  r.push(row("pauser (EOA) / unpauser (Safe)", "pauser=EOA, unpauser=controller Safe", "verify via forge", null,
    `TARGET_CHAIN=${c.NAME} forge script scripts/oft-deployment/04_OFTVerification.s.sol:verifyOFT  # asserts pauser/unpauser holders`));
  return {title: "2. Ownership & authority (all config rights → timelock)", rows: r};
}

function checkTimelock(c, rpc) {
  const r = [];
  const safe = c.CONTROLLER_SAFE;
  const delay = word(call(c.TIMELOCK, "getMinDelay()(uint256)", rpc));
  r.push(row("timelock minDelay", "≥ 172800 (48h) [L1] / per-chain", delay, delay !== null ? null : null,
    `cast call ${c.TIMELOCK} 'getMinDelay()(uint256)' --rpc-url $RPC`));
  for (const [name, id] of Object.entries(ROLES)) {
    const has = word(call(c.TIMELOCK, "hasRole(bytes32,address)(bool)", rpc, id, safe));
    r.push(row(`Safe holds ${name}_ROLE`, "true", has, has === "true" ? true : has === "false" ? false : null,
      `cast call ${c.TIMELOCK} 'hasRole(bytes32,address)(bool)' ${id} ${safe} --rpc-url $RPC`));
  }
  return {title: "3. Timelock roles (controller Safe = proposer/executor/canceller)", rows: r};
}

function checkSafe(c, rpc, policy) {
  const cs = policy.controllerSafe;
  const r = [];
  const ver = word(call(c.CONTROLLER_SAFE, "VERSION()(string)", rpc));
  r.push(row("Safe VERSION", "1.3.0 / 1.4.1", ver, ver ? null : null, `cast call ${c.CONTROLLER_SAFE} 'VERSION()(string)' --rpc-url $RPC`));
  const th = word(call(c.CONTROLLER_SAFE, "getThreshold()(uint256)", rpc));
  r.push(row("Safe threshold", String(cs.finalThreshold), th, th === String(cs.finalThreshold) ? true : th !== null ? false : null,
    `cast call ${c.CONTROLLER_SAFE} 'getThreshold()(uint256)' --rpc-url $RPC`));
  const owners = call(c.CONTROLLER_SAFE, "getOwners()(address[])", rpc);
  const want = new Set(cs.finalOwners.map((a) => a.toLowerCase()));
  const got = owners ? (owners.match(/0x[0-9a-fA-F]{40}/g) || []).map((a) => a.toLowerCase()) : null;
  const ownersOk = got ? got.length === want.size && got.every((a) => want.has(a)) : null;
  r.push(row(`Safe owners == final set (${cs.finalOwners.length})`, `${cs.finalOwners.length} owners`,
    got ? `${got.length} owners` : null, ownersOk, `cast call ${c.CONTROLLER_SAFE} 'getOwners()(address[])' --rpc-url $RPC`));
  return {title: "4. Controller Safe composition (migrated 2-of-5 → 4-of-7)", rows: r};
}

// One pathway: OApp on `oappChain` must accept `peerEid` (peer OFT = expectedPeer).
function checkPathway(oappC, rpc, peerEid, expectedPeer, limit, window, dvns, sendLib, recvLib) {
  const oapp = oappC.OFT;
  const ep = oappC.L2_ENDPOINT;
  const cid = Number(oappC.CHAIN_ID);
  const r = [];
  const peer = word(call(oapp, "peers(uint32)(bytes32)", rpc, String(peerEid)));
  r.push(row(`peers(${peerEid})`, bytes32Addr(expectedPeer), peer, peer && peer.toLowerCase() === bytes32Addr(expectedPeer) ? true : peer !== null ? false : null,
    `cast call ${oapp} 'peers(uint32)(bytes32)' ${peerEid} --rpc-url $RPC`));
  for (const t of [1, 2]) {
    const eo = word(call(oapp, "enforcedOptions(uint32,uint16)(bytes)", rpc, String(peerEid), String(t)));
    r.push(row(`enforcedOptions(${peerEid}, msgType ${t})`, ENFORCED_OPTS, eo, eo && eo.toLowerCase() === ENFORCED_OPTS ? true : eo !== null ? false : null,
      `cast call ${oapp} 'enforcedOptions(uint32,uint16)(bytes)' ${peerEid} ${t} --rpc-url $RPC`));
  }
  if (cid !== 1 && limit !== undefined) {
    for (const dir of ["inbound", "outbound"]) {
      const out = call(oapp, `${dir}RateLimits(uint32)(uint256,uint256,uint256,uint256)`, rpc, String(peerEid));
      // struct RateLimit{amountInFlight, lastUpdated, limit, window}; cast appends ` [1.7e9]`
      // scientific annotations — strip them before positional parse, then compare numerically.
      const nums = out ? out.replace(/\[[^\]]*\]/g, "").trim().split(/\s+/) : null;
      const gotLimit = nums ? nums[2] : null;
      const gotWindow = nums ? nums[3] : null;
      const ok = gotLimit != null ? Number(gotLimit) === Number(limit) && Number(gotWindow) === Number(window) : null;
      r.push(row(`${dir} rate limit (${peerEid})`, `${limit} / ${window}s`, nums ? `${gotLimit} / ${gotWindow}s` : null, ok,
        `cast call ${oapp} '${dir}RateLimits(uint32)(uint256,uint256,uint256,uint256)' ${peerEid} --rpc-url $RPC`));
    }
  }
  const expUln = ulnExpected(dvns).toLowerCase();
  for (const [name, lib] of [["SEND", sendLib], ["RECEIVE", recvLib]]) {
    const got = word(call(ep, "getConfig(address,address,uint32,uint32)(bytes)", rpc, oapp, lib, String(peerEid), "2"));
    r.push(row(`${name} ULN config (4-of-4 DVN @ ${ULN_CONFIRMATIONS})`, "4 req DVNs, 0 optional", got ? short(got) : null,
      got ? got.toLowerCase() === expUln : null,
      `cast call ${ep} 'getConfig(address,address,uint32,uint32)(bytes)' ${oapp} ${lib} ${peerEid} 2 --rpc-url $RPC`));
  }
  return r;
}

function renderSection(s, chainId, rpcLabel) {
  const lines = [`### ${s.title}`, "", "| Check | Expected | On-chain | Status |", "|---|---|---|---|"];
  for (const r of s.rows) lines.push(`| ${r.name} | ${short(r.expected)} | ${short(r.actual)} | ${mark(r.ok)} |`);
  lines.push("", "<details><summary>re-run commands</summary>", "", "```bash", `RPC=${rpcLabel}`);
  for (const r of s.rows) if (r.cmd) lines.push(r.cmd);
  lines.push("```", "</details>", "");
  return lines.join("\n");
}

function eidToKey(reg, eid) {
  for (const [k, c] of Object.entries(reg)) if (Number(c.L2_EID) === Number(eid)) return k;
  return null;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.chain) {
    console.error("error: --chain <key> is required");
    process.exit(1);
  }
  const reg = JSON.parse(readFileSync(resolve(REPO_ROOT, "registry/chains.json"), "utf8"));
  const policy = JSON.parse(readFileSync(resolve(REPO_ROOT, "registry/policy.json"), "utf8"));
  const c = reg[args.chain];
  if (!c) {
    console.error(`error: chain "${args.chain}" not in registry/chains.json`);
    process.exit(1);
  }
  const env = loadEnv();
  const cid = Number(c.CHAIN_ID);
  const rpc = args.rpc || rpcFor(args.chain, cid, args.peerRpc, env);
  if (!rpc) {
    console.error(`error: no RPC for ${args.chain}; pass --rpc or set ${args.chain.toUpperCase()}_MAINNET_RPC_URL in .env`);
    process.exit(1);
  }
  const rpcLabel = `<${args.chain.toUpperCase()}_MAINNET_RPC_URL>`;

  const sections = [
    checkDeployment(c, rpc, policy),
    checkAuthority(c, rpc),
    checkTimelock(c, rpc),
    checkSafe(c, rpc, policy),
  ];
  // Target-side pathways
  const eids = c.peerEids || [];
  const targetRows = [];
  for (let i = 0; i < eids.length; i++) {
    const peerKey = eidToKey(reg, eids[i]);
    targetRows.push({sub: `→ peer ${peerKey || eids[i]} (EID ${eids[i]})`,
      rows: checkPathway(c, rpc, eids[i], c.peerOfts[i], c.peerLimits[i], c.peerWindows[i], c.LZ_DVN, c.SEND_302, c.RECEIVE_302)});
  }

  // Peer-side acceptance (each existing peer accepts the new chain's EID)
  const peerSections = [];
  for (let i = 0; i < eids.length; i++) {
    const peerKey = eidToKey(reg, eids[i]);
    const pc = peerKey ? reg[peerKey] : null;
    if (!pc) continue;
    const prpc = rpcFor(peerKey, Number(pc.CHAIN_ID), args.peerRpc, env);
    if (!prpc) {
      peerSections.push({title: `peer ${peerKey}`, rows: [row("RPC available", "set", "missing", null,
        `# set ${peerKey.toUpperCase()}_MAINNET_RPC_URL or pass --peer-rpc ${peerKey}=<url>`)], rpc: "<unset>"});
      continue;
    }
    const limit = Number(pc.CHAIN_ID) === 1 ? undefined : c.peerLimits[i];
    peerSections.push({title: `peer ${peerKey} (EID ${c.L2_EID} = ${args.chain})`,
      rows: checkPathway(pc, prpc, c.L2_EID, c.OFT, limit, c.peerWindows[i], pc.LZ_DVN, pc.SEND_302, pc.RECEIVE_302),
      rpc: `<${peerKey.toUpperCase()}_MAINNET_RPC_URL>`, chainId: Number(pc.CHAIN_ID), safe: pc.CONTROLLER_SAFE});
  }

  const allRows = [...sections.flatMap((s) => s.rows), ...targetRows.flatMap((t) => t.rows), ...peerSections.flatMap((s) => s.rows)];
  const pass = allRows.filter((r) => r.ok === true).length;
  const fail = allRows.filter((r) => r.ok === false).length;
  const manual = allRows.filter((r) => r.ok === null).length;
  const stamp = new Date().toISOString();

  const out = [];
  out.push(`# weETH OFT deployment verification — ${args.chain} (chain ${cid})`, "");
  out.push(`> Point-in-time on-chain snapshot generated **${stamp}** by \`tools/verify-deployment.mjs\`.`,
    `> Re-run any check with the \`cast\` command in its section. ✅ pass · ❌ mismatch · ⚠️ read manually / informational.`, "");
  out.push(`**Result: ${pass} ✅ · ${fail} ❌ · ${manual} ⚠️** across ${allRows.length} checks.`, "");
  out.push("> Checks gated on a not-yet-executed proposal read as ❌ until it lands — the reverse-peer wiring",
    "> on each peer (3CP) and the controller Safe 2-of-5 → 4-of-7 migration (3CP). Here ❌ means **pending**;",
    "> re-run after the proposal executes and it should flip to ✅.", "");
  out.push("## Addresses", "", "| Contract | Address |", "|---|---|");
  out.push(`| OFT (proxy) | ${explorerLink(cid, c.OFT)} |`);
  out.push(`| OFT impl | ${explorerLink(cid, c.OFT_IMPL)} |`);
  out.push(`| ProxyAdmin | ${explorerLink(cid, c.PROXY_ADMIN)} |`);
  out.push(`| Timelock | ${explorerLink(cid, c.TIMELOCK)} |`);
  out.push(`| Controller Safe | ${explorerLink(cid, c.CONTROLLER_SAFE)} · ${safeLink(cid, c.CONTROLLER_SAFE)} |`);
  out.push(`| LZ endpoint | ${explorerLink(cid, c.L2_ENDPOINT)} |`, "");

  out.push("## New-chain checks", "");
  for (const s of sections) out.push(renderSection(s, cid, rpcLabel));
  out.push("### 5. Per-pathway security config (new chain accepts each peer)", "");
  for (const t of targetRows) out.push(renderSection({title: t.sub, rows: t.rows}, cid, rpcLabel));

  out.push("## Peer-side acceptance (reverse wiring for this chain's EID)", "");
  for (const s of peerSections) out.push(renderSection(s, s.chainId, s.rpc));

  out.push("## External references", "");
  for (const [label, url] of DOC_LINKS) out.push(`- [${label}](${url})`);
  out.push("- Onboarding runbook: `NEW-CHAIN-ONBOARDING.md` · skill `.claude/skills/onboard-oft-chain/SKILL.md`", "");

  const outPath = args.out || resolve(REPO_ROOT, "output", `verify-${args.chain}.md`);
  mkdirSync(dirname(outPath), {recursive: true});
  writeFileSync(outPath, out.join("\n") + "\n");
  console.log(`wrote ${outPath}`);
  console.log(`  ${pass} pass / ${fail} fail / ${manual} manual across ${allRows.length} checks`);
}

main();
