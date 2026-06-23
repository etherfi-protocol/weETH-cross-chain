#!/usr/bin/env node
// Emit 3CP proposal folders (queued/<id>/<id>.json + .md) for the on-chain
// steps of onboarding a chain to the weETH OFT mesh. ABI encoding is delegated
// to `cast calldata` so there is no hand-rolled selector/encoding drift.
//
// Types (--type):
//   handoff         (default) new chain: setDelegate + transferOwnership -> timelock
//   safe-migration  new chain's controller Safe: 2-of-5 -> 4-of-7 (self-calls)
//   peer            existing peer chain accepts the new chain: setPeer (+ rate
//                   limits on L2s). Routed automatically: direct-Safe when the
//                   peer OFT is Safe-owned, timelock schedule+execute when it is
//                   timelock-owned (e.g. the L1 adapter).
//
// 3CP convention: folder = next-free GLOBAL proposal id (local queued/ + open
// PRs); Safe nonce is separate (--nonce, or read on-chain with --rpc).
//
// Usage:
//   node tools/make-3cp-folder.mjs --type handoff        --chain <key> [--rpc url] [--out repo]
//   node tools/make-3cp-folder.mjs --type safe-migration --chain <key>            [--out repo]
//   node tools/make-3cp-folder.mjs --type peer --chain <newKey> --peer <peerKey> --rpc <peerRpc> [--out repo]
//
// Defaults: --out $CP3_REPO or ../../3CP-secure ; multisend auto-resolved from the Safe's
// version via --rpc (MultiSendCallOnly, e.g. 0xA1dabEF3… for 1.3.0). Single-tx leaves are
// hashed as a direct call (operation 0) — no MultiSend. Override with --multisend.

import {readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {execFileSync} from "node:child_process";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
// MultiSendCallOnly 1.3.0 — the contract Safe{Wallet} actually wraps batches with, so the
// generated safeTxHash matches what signers sign. Two canonical deployments exist; the app
// uses whichever is deployed on the chain (resolveMultiSend picks it from --rpc). Do NOT use
// the plain MultiSend 0xA238CBeb… — it allows sub-call delegatecall and yields a different hash.
const MULTISEND_CALL_ONLY = "0xA1dabEF33b3B82c7814B6D82A79e50F4AC44102B"; // eip155 / Safe Singleton Factory
const MULTISEND_CALL_ONLY_CANONICAL = "0x40A2aCCbd92BCA938b02010E17A5b8929b49130D"; // Nick-factory variant
const GH_REPO = process.env.CP3_GH_REPO || "etherfi-protocol/3CP-secure";
const ZERO32 = "0x" + "0".repeat(64);
const DEFAULT_DELAY = 172800; // 2 days, fallback if timelock minDelay is unreadable

const parseArgs = (argv) => {
  const a = {};
  for (let i = 0; i < argv.length; i += 2) a[argv[i].replace(/^--/, "")] = argv[i + 1];
  return a;
};
const toBytes32 = (addr) => "0x" + "0".repeat(24) + addr.replace(/^0x/, "").toLowerCase();
const cast = (args) => execFileSync("cast", args, {encoding: "utf8", stdio: ["ignore", "pipe", "ignore"]}).trim();
const calldata = (sig, ...args) => cast(["calldata", sig, ...args]);
const abiEncode = (sig, ...args) => cast(["abi-encode", sig, ...args]);
// 170k lzReceive enforced option (type-3 options), msgType 1 & 2
const ENFORCED_OPTS = "0x00030100110100000000000000000000000000029810";
const ULN_CONFIRMATIONS = "45";
const callView = (to, sig, rpc, ...args) => {
  try {
    return cast(["call", to, sig, ...args, "--rpc-url", rpc]).split(/\s+/)[0];
  } catch {
    return null;
  }
};
const hasCode = (addr, rpc) => {
  try {
    return cast(["code", addr, "--rpc-url", rpc]).replace(/^0x/, "").length > 0;
  } catch {
    return false;
  }
};
// MultiSendCallOnly per Safe version — Safe{Wallet} wraps a batch with the MultiSendCallOnly
// matching THIS Safe's version, so the generated safeTxHash equals what signers sign. Read
// VERSION() off the Safe, then pick the candidate that's actually deployed on the chain.
const MSCO_BY_VERSION = {
  "1.3.0": ["0xA1dabEF33b3B82c7814B6D82A79e50F4AC44102B", "0x40A2aCCbd92BCA938b02010E17A5b8929b49130D"],
  "1.4.1": ["0x9641d764fc13c8B624c04430C7356C1C7C8102e2"],
};
const safeVersion = (safe, rpc) => (callView(safe, "VERSION()(string)", rpc) || "").replace(/"/g, "").trim();
const resolveMultiSend = (safe, rpc) => {
  if (!rpc) return MULTISEND_CALL_ONLY;
  const candidates = MSCO_BY_VERSION[safeVersion(safe, rpc)] || [MULTISEND_CALL_ONLY, MULTISEND_CALL_ONLY_CANONICAL];
  for (const c of candidates) if (hasCode(c, rpc)) return c;
  return candidates[0];
};

function loadRegistry() {
  return JSON.parse(readFileSync(resolve(REPO_ROOT, "registry/chains.json"), "utf8"));
}
function loadPolicy() {
  return JSON.parse(readFileSync(resolve(REPO_ROOT, "registry/policy.json"), "utf8"));
}
function requireChain(reg, key) {
  const c = reg[key];
  if (!c) {
    console.error(`error: chain "${key}" not found in registry/chains.json`);
    process.exit(1);
  }
  return c;
}

// ---- bundle builders: each returns [{label, safe, chainId, transactions, lines}] ----

function buildHandoff(c) {
  const oft = c.OFT.toLowerCase();
  return [{
    label: `${c.NAME}: OFT owner + delegate -> timelock`,
    safe: c.CONTROLLER_SAFE,
    chainId: String(c.CHAIN_ID),
    transactions: [
      {to: oft, value: "0", data: calldata("setDelegate(address)", c.TIMELOCK)},
      {to: oft, value: "0", data: calldata("transferOwnership(address)", c.TIMELOCK)},
    ],
    lines: [`1. setDelegate(${c.TIMELOCK}) -> OFT`, `2. transferOwnership(${c.TIMELOCK}) -> OFT`],
  }];
}

function buildSafeMigration(c, policy) {
  const cs = policy.controllerSafe;
  const safe = c.CONTROLLER_SAFE.toLowerCase();
  const initial = new Set(cs.initialOwners.map((a) => a.toLowerCase()));
  const toAdd = cs.finalOwners.filter((a) => !initial.has(a.toLowerCase()));
  const txs = toAdd.map((owner, i) => {
    const threshold = i === toAdd.length - 1 ? cs.finalThreshold : cs.initialThreshold;
    return {to: safe, value: "0", data: calldata("addOwnerWithThreshold(address,uint256)", owner, String(threshold))};
  });
  return [{
    label: `${c.NAME}: controller Safe ${cs.initialThreshold}-of-${cs.initialOwners.length} -> ${cs.finalThreshold}-of-${cs.finalOwners.length}`,
    safe,
    chainId: String(c.CHAIN_ID),
    transactions: txs,
    lines: txs.map((_, i) =>
      `${i + 1}. addOwnerWithThreshold(${toAdd[i]}, ${i === toAdd.length - 1 ? cs.finalThreshold : cs.initialThreshold})  [Safe self-call]`),
    note: "Signed by the initial owners. Safe self-calls (to == Safe).",
  }];
}

// Full-pathway inner calls that make `peer` accept `nc` (the new chain) with
// symmetric 4-of-4 DVN security. Owner-gated calls (setPeer / rate limits /
// enforced options) target the OFT; delegate-gated DVN config targets the
// endpoint. On every current peer owner == delegate, so they share one bundle.
// The L1 adapter has no pairwise rate limiter, so it skips the limit calls.
// True only while the pathway still rides LayerZero's DEFAULT lib. A pin on an
// already-pinned pathway reverts with LZ_SameValue (bit the 474 ETHFI/EURC batch),
// so pins MUST be generated from a live fork — never a static list.
function isDefaultSendLib(endpoint, oapp, eid, rpc) {
  return callView(endpoint, "isDefaultSendLibrary(address,uint32)(bool)", rpc, oapp, eid) === "true";
}
function isDefaultReceiveLib(endpoint, oapp, eid, rpc) {
  try {
    return /\btrue\b/.test(cast(["call", endpoint, "getReceiveLibrary(address,uint32)(address,bool)", oapp, eid, "--rpc-url", rpc]));
  } catch {
    return false;
  }
}

function peerInnerCalls(nc, peer, rpc) {
  const peerOft = peer.OFT.toLowerCase();
  const endpoint = peer.L2_ENDPOINT.toLowerCase();
  const eid = String(nc.L2_EID);
  const calls = [];

  // setPeer (owner)
  calls.push({to: peerOft, value: "0", data: calldata("setPeer(uint32,bytes32)", eid, toBytes32(nc.OFT)), desc: `setPeer(${eid}, ${nc.OFT})`});

  // per-pathway rate limits (owner) — mirrors the new chain's own limit; L1 adapter has none
  if (String(peer.CHAIN_ID) !== "1") {
    const limit = String(nc.peerLimits[0]);
    const window = String(nc.peerWindows[0]);
    const cfg = `[(${eid},${limit},${window})]`;
    calls.push({to: peerOft, value: "0", data: calldata("setInboundRateLimits((uint32,uint256,uint256)[])", cfg), desc: `setInboundRateLimits(${eid}, ${limit}, ${window})`});
    calls.push({to: peerOft, value: "0", data: calldata("setOutboundRateLimits((uint32,uint256,uint256)[])", cfg), desc: `setOutboundRateLimits(${eid}, ${limit}, ${window})`});
  }

  // enforced options (owner) — 170k lzReceive, msgType 1 & 2
  const eo = `[(${eid},1,${ENFORCED_OPTS}),(${eid},2,${ENFORCED_OPTS})]`;
  calls.push({to: peerOft, value: "0", data: calldata("setEnforcedOptions((uint32,uint16,bytes)[])", eo), desc: `setEnforcedOptions(${eid}, msgType 1&2, 170k)`});

  // Pin the message libraries for this pathway (delegate). Without this the new EID stays on
  // LayerZero's DEFAULT 302 lib, so if LZ ever rotates its default the pathway silently follows
  // it — i.e. the lib under our weETH pathway could change with no governance action on our side.
  // Emit a pin ONLY where the pathway is still on the default (else setSendLibrary reverts
  // LZ_SameValue). Requires a live fork; without --rpc skip + warn rather than emit a blind pin.
  if (!rpc) {
    console.error(`WARN: no --rpc — skipping message-library pin for ${peer.NAME} eid ${eid}. Pins must be generated from a live fork (a blind pin reverts LZ_SameValue if already pinned). Re-run with --rpc to include them.`);
  } else {
    if (isDefaultSendLib(endpoint, peerOft, eid, rpc)) {
      calls.push({to: endpoint, value: "0", data: calldata("setSendLibrary(address,uint32,address)", peerOft, eid, peer.SEND_302), desc: `endpoint.setSendLibrary(${eid}, SEND_302)`});
    } else {
      console.error(`WARN: ${peer.NAME} eid ${eid} send lib already pinned — omitting setSendLibrary (would revert LZ_SameValue).`);
    }
    if (isDefaultReceiveLib(endpoint, peerOft, eid, rpc)) {
      calls.push({to: endpoint, value: "0", data: calldata("setReceiveLibrary(address,uint32,address,uint256)", peerOft, eid, peer.RECEIVE_302, "0"), desc: `endpoint.setReceiveLibrary(${eid}, RECEIVE_302, grace 0)`});
    } else {
      console.error(`WARN: ${peer.NAME} eid ${eid} receive lib already pinned — omitting setReceiveLibrary (would revert LZ_SameValue).`);
    }
  }

  // 4-of-4 DVN ULN config (delegate) on send + receive libs — uses this chain's own DVN set
  const dvns = `[${peer.LZ_DVN.join(",")}]`;
  // UlnConfig is a dynamic struct -> the lib does abi.decode(config,(UlnConfig)),
  // which expects a single-struct encoding WITH a leading 0x20 offset. Encode it
  // as a tuple type, NOT 6 flat params (flat omits the offset -> setConfig reverts).
  const uln = abiEncode("f((uint64,uint8,uint8,uint8,address[],address[]))", `(${ULN_CONFIRMATIONS},4,0,0,${dvns},[])`);
  calls.push({to: endpoint, value: "0", data: calldata("setConfig(address,address,(uint32,uint32,bytes)[])", peerOft, peer.SEND_302, `[(${eid},2,${uln})]`), desc: `endpoint.setConfig(SEND lib, ${eid}, 4-of-4 DVN @ ${ULN_CONFIRMATIONS})`});
  calls.push({to: endpoint, value: "0", data: calldata("setConfig(address,address,(uint32,uint32,bytes)[])", peerOft, peer.RECEIVE_302, `[(${eid},2,${uln})]`), desc: `endpoint.setConfig(RECEIVE lib, ${eid}, 4-of-4 DVN @ ${ULN_CONFIRMATIONS})`});

  return calls;
}

function buildPeer(nc, peer, policy, args) {
  const inner = peerInnerCalls(nc, peer, args.rpc);
  const owner = args.rpc ? callView(peer.OFT, "owner()(address)", args.rpc) : null;
  const timelockOwned = owner && owner.toLowerCase() === peer.TIMELOCK.toLowerCase();

  if (!timelockOwned) {
    if (args.rpc && owner && owner.toLowerCase() !== peer.CONTROLLER_SAFE.toLowerCase()) {
      console.error(`error: ${peer.NAME} OFT owner ${owner} is neither its Safe nor its timelock; refusing to guess routing`);
      process.exit(1);
    }
    return [{
      label: `${peer.NAME}: accept ${nc.NAME} peer (direct Safe)`,
      safe: peer.CONTROLLER_SAFE,
      chainId: String(peer.CHAIN_ID),
      transactions: inner.map(({to, value, data}) => ({to, value, data})),
      lines: inner.map((c, i) => `${i + 1}. ${c.desc}`),
    }];
  }

  // timelock-owned: schedule + execute, submitted by the controlling Safe.
  const tl = peer.TIMELOCK.toLowerCase();
  const delay = (args.rpc && Number(callView(peer.TIMELOCK, "getMinDelay()(uint256)", args.rpc))) || DEFAULT_DELAY;
  const targets = `[${inner.map((c) => c.to).join(",")}]`;
  const values = `[${inner.map(() => "0").join(",")}]`;
  const datas = `[${inner.map((c) => c.data).join(",")}]`;
  const scheduleData = calldata("scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)", targets, values, datas, ZERO32, ZERO32, String(delay));
  const executeData = calldata("executeBatch(address[],uint256[],bytes[],bytes32,bytes32)", targets, values, datas, ZERO32, ZERO32);
  const lines = inner.map((c, i) => `   - ${i + 1}. ${c.desc}`);
  return [
    {
      label: `${peer.NAME}: schedule accept-${nc.NAME} (timelock, delay ${delay}s)`,
      safe: peer.CONTROLLER_SAFE,
      chainId: String(peer.CHAIN_ID),
      transactions: [{to: tl, value: "0", data: scheduleData}],
      lines: [`1. scheduleBatch(delay=${delay}s) on timelock ${tl}, batching:`, ...lines],
      note: `Execute after the ${delay}s delay with the matching execute proposal.`,
    },
    {
      label: `${peer.NAME}: execute accept-${nc.NAME} (timelock)`,
      safe: peer.CONTROLLER_SAFE,
      chainId: String(peer.CHAIN_ID),
      transactions: [{to: tl, value: "0", data: executeData}],
      lines: [`1. executeBatch() on timelock ${tl}, batching:`, ...lines],
      note: "Submit only after the schedule proposal has cleared the timelock delay.",
    },
  ];
}

// ---- folder-id + nonce + open-PR plumbing ----

function gh(args) {
  return execFileSync("gh", args, {encoding: "utf8", stdio: ["ignore", "pipe", "ignore"]});
}
function openPrFolders() {
  try {
    const prs = JSON.parse(gh(["pr", "list", "-R", GH_REPO, "--state", "open", "--limit", "200", "--json", "files,title"]));
    const ids = new Set();
    for (const pr of prs) for (const f of pr.files || []) {
      const m = f.path.match(/^queued\/(\d+)\//);
      if (m) ids.add(Number(m[1]));
    }
    return {ids, prs, ok: true};
  } catch {
    return {ids: new Set(), prs: [], ok: false};
  }
}
function localFolders(outRepo) {
  const dir = resolve(outRepo, "queued");
  if (!existsSync(dir)) return new Set();
  return new Set(readdirSync(dir).filter((d) => /^\d+$/.test(d)).map(Number));
}
function sameSafePrs(prs, safe) {
  const want = safe.toLowerCase();
  return prs.filter((pr) => (pr.title.match(/0x[0-9a-fA-F]{40}/g) || []).some((a) => a.toLowerCase() === want)).map((pr) => pr.title);
}
function readSafeNonce(safe, rpc) {
  const n = callView(safe, "nonce()(uint256)", rpc);
  return n === null ? 0 : Number(n);
}

function renderMd(p, id, nonce, multisend, chainKey, jsonPath) {
  const noteBlock = p.note ? `\n> ${p.note}\n` : "";
  return `# ${p.label}

| field | value |
|-------|-------|
| proposal | #${id} |
| chainId | ${p.chainId} |
| Safe | \`${p.safe.toLowerCase()}\` |
| Safe nonce | ${nonce} |
${noteBlock}
## Transactions

${p.lines.join("\n")}

## Verify

${p.transactions.length === 1
  ? `> Single transaction → Safe{Wallet} proposes it as a **direct call (operation 0)**, NOT MultiSend-wrapped.

\`\`\`bash
TO=$(jq -r '.transactions[0].to' ${jsonPath})
DATA=$(jq -r '.transactions[0].data' ${jsonPath})
./safe_hashes.sh --offline --network ${chainKey} --address ${p.safe.toLowerCase()} \\
  --to "$TO" --data "$DATA" --nonce ${nonce} --operation 0 --safe-version 1.3.0
\`\`\``
  : `> Multi-call batch → MultiSendCallOnly (operation 1). \`${multisend}\` is the MultiSendCallOnly matching this Safe's version (confirm it's the \`to\` your Safe app calls).

\`\`\`bash
./build_multisend.sh ${jsonPath} ${p.safe.toLowerCase()} \\
  --network ${chainKey} --multisend ${multisend} --nonce ${nonce}
\`\`\``}
`;
}

// "ethereum: schedule …" -> "schedule"; falls back to the index.
function leafSuffix(label, idx) {
  const m = label.match(/\b(schedule|execute)\b/i);
  return m ? m[1].toLowerCase() : String(idx + 1);
}

// Canonical-address lint — refuse to emit a proposal whose calls touch a non-canonical
// address. A wrong/attacker setPeer target, a stray DVN, or an ownership handoff to the
// wrong timelock reads as plausible calldata to a human reviewer; this fails the build
// instead. Sources of truth: registry/chains.json (per-chain) + policy.json (canonical).
const isAddr = (a) => /^0x[0-9a-fA-F]{40}$/.test(a || "");
function assertCanonical(type, chain, peerC, proposals, policy) {
  const errs = [];
  const msco = new Set(Object.values(MSCO_BY_VERSION).flat().map((a) => a.toLowerCase()));
  const known = new Set();
  for (const k of [chain, peerC]) {
    if (!k) continue;
    for (const a of [k.OFT, k.L2_ENDPOINT, k.TIMELOCK, k.CONTROLLER_SAFE]) if (a) known.add(a.toLowerCase());
  }
  for (const p of proposals) for (const t of p.transactions) {
    const to = (t.to || "").toLowerCase();
    if (!isAddr(to)) errs.push(`tx.to is not an address: ${t.to}`);
    else if (!known.has(to) && !msco.has(to)) errs.push(`tx.to ${t.to} is not a known OFT/endpoint/timelock/Safe/MultiSend for this proposal`);
  }
  if (type === "handoff" && String(chain.CHAIN_ID) !== "1" &&
      chain.TIMELOCK.toLowerCase() !== policy.canonical.timelock.toLowerCase()) {
    errs.push(`handoff target timelock ${chain.TIMELOCK} != canonical ${policy.canonical.timelock}`);
  }
  if (type === "safe-migration" && chain.CONTROLLER_SAFE.toLowerCase() !== policy.canonical.controllerSafe.toLowerCase()) {
    errs.push(`controller Safe ${chain.CONTROLLER_SAFE} != canonical ${policy.canonical.controllerSafe}`);
  }
  if (type === "peer") {
    const dvns = (peerC.LZ_DVN || []).map((d) => (d || "").toLowerCase());
    if (dvns.length !== policy.requiredDVNCount) errs.push(`${peerC.NAME}: ${dvns.length} DVNs, expected ${policy.requiredDVNCount}`);
    if (!dvns.every(isAddr)) errs.push(`${peerC.NAME}: a DVN is not an address`);
    if (new Set(dvns).size !== dvns.length) errs.push(`${peerC.NAME}: DVNs not unique`);
    if (JSON.stringify(dvns) !== JSON.stringify([...dvns].sort())) errs.push(`${peerC.NAME}: DVNs not sorted ascending`);
    if (!isAddr(peerC.SEND_302) || !isAddr(peerC.RECEIVE_302)) errs.push(`${peerC.NAME}: missing 302 libraries`);
    if (!isAddr(chain.OFT)) errs.push(`${chain.NAME}: peer OFT (setPeer target) missing/invalid`);
  }
  if (errs.length) {
    console.error("CANONICAL LINT FAILED — refusing to write non-canonical proposal:");
    for (const e of errs) console.error(`  - ${e}`);
    process.exit(1);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const type = args.type || "handoff";
  const reg = loadRegistry();
  const policy = loadPolicy();
  const c = requireChain(reg, args.chain);

  let proposals;
  let peerC = null;
  if (type === "handoff") proposals = buildHandoff(c);
  else if (type === "safe-migration") proposals = buildSafeMigration(c, policy);
  else if (type === "peer") {
    if (!args.peer) {
      console.error("error: --peer <peerKey> is required for --type peer");
      process.exit(1);
    }
    peerC = requireChain(reg, args.peer);
    proposals = buildPeer(c, peerC, policy, args);
  } else {
    console.error(`error: unknown --type "${type}" (handoff | safe-migration | peer)`);
    process.exit(1);
  }
  // Refuse to write a proposal that touches a non-canonical address (wrong peer, stray DVN,
  // handoff to a non-canonical timelock, etc.) — a build-time gate, not a reviewer's eyeball.
  assertCanonical(type, c, peerC, proposals, policy);

  const outRepo = args.out || process.env.CP3_REPO || resolve(REPO_ROOT, "../../3CP-secure");
  if (!existsSync(outRepo)) {
    console.error(`error: 3CP repo not found at ${outRepo} (set --out or $CP3_REPO)`);
    process.exit(1);
  }

  const {ids: prIds, prs, ok: ghOk} = openPrFolders();
  const claimed = new Set([...localFolders(outRepo), ...prIds]);
  let id = args.id !== undefined ? Number(args.id) : (claimed.size ? Math.max(...claimed) + 1 : 1);
  // Batch mode: --subdir <chain> puts this chain's proposal(s) inside a shared
  // proposal number as a subfolder (queued/<id>/<subdir>/<leaf>.{json,md}), so a
  // multi-chain batch lives under ONE number in ONE PR. Pass the same --id for
  // every chain in the batch. Without --subdir, each proposal gets its own
  // top-level numbered folder (queued/<id>/<id>.{json,md}).
  const subdir = args.subdir;
  if (subdir) while (claimed.has(id) && args.id === undefined) id++;

  proposals.forEach((p, k) => {
    if (!subdir) { while (claimed.has(id)) id++; claimed.add(id); }
    const nonce =
      args.nonce !== undefined ? Number(args.nonce) : args.rpc ? readSafeNonce(p.safe, args.rpc) : 0;
    // Per-Safe MultiSendCallOnly (version-matched) for multi-call leaves; single-tx leaves
    // are hashed as a direct call (operation 0) by renderMd regardless.
    const multisend = args.multisend || resolveMultiSend(p.safe, args.rpc);
    const bundle = {chainId: p.chainId, safeAddress: p.safe.toLowerCase(), meta: {txBuilderVersion: "1.16.5"}, transactions: p.transactions};
    const leaf = subdir
      ? (proposals.length > 1 ? `${subdir}-${leafSuffix(p.label, k)}` : subdir)
      : String(id);
    const folder = subdir ? resolve(outRepo, "queued", String(id), subdir) : resolve(outRepo, "queued", String(id));
    const relJson = subdir ? `./queued/${id}/${subdir}/${leaf}.json` : `./queued/${id}/${leaf}.json`;
    mkdirSync(folder, {recursive: true});
    writeFileSync(resolve(folder, `${leaf}.json`), JSON.stringify(bundle, null, 2) + "\n");
    // peer proposals live on the PEER chain, not the new chain — use the peer key
    // for the verify --network (else it emits the wrong/unknown network).
    const netKey = type === "peer" ? args.peer : args.chain;
    writeFileSync(resolve(folder, `${leaf}.md`), renderMd(p, id, nonce, multisend, netKey, relJson));

    console.log(`#${id}${subdir ? `/${leaf}` : ""}  ${p.label}`);
    console.log(`      Safe ${p.safe} nonce ${nonce}  (${p.transactions.length} tx)`);
    const conflicts = ghOk ? sameSafePrs(prs, p.safe) : [];
    if (conflicts.length) {
      console.log(`      WARN: open PR(s) target this Safe — confirm nonce ${nonce} is free:`);
      for (const t of conflicts) console.log(`        - ${t}`);
    }
    if (!subdir) id++;
  });
  if (!ghOk) console.log("WARN: gh unavailable — folder ids from local queued/ only; check open PRs manually.");
}

main();
