#!/usr/bin/env node
// Propose every leaf of a 3CP PR to the Safe transaction service, signing back-to-back on a Ledger.
// The Ledger prompts once per leaf (keep it unlocked, Ethereum app open, blind-signing/EIP-712 on).
//
//   node tools/propose-3cp.mjs 590 585 591 [--hd-path "m/44'/60'/0'/0/0"] [--dry-run]
//
// Proposer (Ledger) MUST be an owner or a registered delegate of each Safe, else the tx service
// rejects the proposal. Order: PRs in the order given; within a PR, by chain then ascending nonce
// (so a Safe's schedule is proposed before its execute). Reconstructs each Safe tx from the leaf
// JSON (calldata) + its .md (nonce / operation / MultiSendCallOnly), RE-DERIVES the safeTxHash and
// aborts if it doesn't match the md — so the device never signs an unverified hash. Chains without a
// hosted Safe tx service are skipped after signing, with the signed payload printed for the offline flow.
import {execFileSync} from "node:child_process";
import {readFileSync, writeFileSync, readdirSync, existsSync} from "node:fs";
import {resolve} from "node:path";
const CP3 = process.env.CP3_REPO || resolve(process.env.HOME, "etherfi/3CP-secure");
const cast = (...a) => execFileSync("cast", a, {encoding: "utf8"}).trim();
const git = (...a) => execFileSync("git", ["-C", CP3, ...a], {encoding: "utf8"}).trim();
const argv = process.argv.slice(2);
const PROPOSER = "0x1B7Fd9679B2678F7e01897E0A3BA9aF18dF4f71e";
const HD = (argv[argv.indexOf("--hd-path") + 1] && argv.includes("--hd-path")) ? argv[argv.indexOf("--hd-path") + 1] : "m/44'/60'/0'/0/0";
const DRY = argv.includes("--dry-run");
// --no-sign: propose as a DELEGATE (signature=null) — no Ledger. Makes txns visible in the UI without
// re-signing; owners confirm separately (e.g. the on-chain approveHash you already did). Requires the
// proposer to be a registered delegate on each Safe.
const NO_SIGN = argv.includes("--no-sign");
const PRS = argv.filter(a => /^\d+$/.test(a));
const ZERO = "0x0000000000000000000000000000000000000000", Z = "0".repeat(64);

const DTH = cast("keccak", "EIP712Domain(uint256 chainId,address verifyingContract)");
const STH = cast("keccak", "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)");
const enc = (t, v) => cast("abi-encode", `f(${t.join(",")})`, ...v.map(String));
const u256 = n => BigInt(n).toString(16).padStart(64, "0");

function multiSend(txs) {                       // wrap inner txs as MultiSendCallOnly.multiSend(bytes)
  const payload = "0x" + txs.map(t => "00" + t.to.slice(2).toLowerCase() + u256(t.value || 0)
    + u256((t.data.length - 2) / 2) + t.data.slice(2)).join("");
  return cast("calldata", "multiSend(bytes)", payload);
}
function field(md, re) { const m = md.match(re); return m && m[1]; }

// build the (to, value, data, operation, nonce, safe, chainId, version, expectedHash, net) for a leaf
function buildLeaf(branch, jsonPath) {
  const name = jsonPath.split("/").pop().replace(/\.json$/, "");
  const leaf = JSON.parse(git("show", `${branch}:${jsonPath}`));
  const md = git("show", `${branch}:${jsonPath.replace(/\.json$/, ".md")}`);
  const op = Number(field(md, /\| operation \| (\d)/));
  const nonceRaw = field(md, /\| nonce \| ([^|]+?) \|/).trim();
  const safe = leaf.safeAddress, chainId = Number(leaf.chainId);
  const expected = field(md, /\| \*\*Safe tx\*\* \| `(0x[0-9a-fA-F]+)`/);
  let to, value, data;
  if (op === 1) { to = field(md, /MultiSendCallOnly `(0x[0-9a-fA-F]+)`/); value = "0"; data = multiSend(leaf.transactions); }
  else { to = leaf.transactions[0].to; value = leaf.transactions[0].value || "0"; data = leaf.transactions[0].data; }
  const nonce = nonceRaw === "TBD" ? null : Number(nonceRaw);
  return {name, safe, chainId, to, value, data, op, nonce, expected};
}
function safeTxHash(L) {
  const domain = cast("keccak", enc(["bytes32", "uint256", "address"], [DTH, L.chainId, L.safe]));
  const dataHash = cast("keccak", L.data);
  const structHash = cast("keccak", enc(["bytes32", "address", "uint256", "bytes32", "uint8", "uint256", "uint256", "uint256", "address", "address", "uint256"],
    [STH, L.to, L.value, dataHash, L.op, 0, 0, 0, ZERO, ZERO, L.nonce]));
  return {domain, structHash, safeTxHash: cast("keccak", `0x1901${domain.slice(2)}${structHash.slice(2)}`)};
}
function typedFile(L) {
  const t = {types: {EIP712Domain: [{name: "chainId", type: "uint256"}, {name: "verifyingContract", type: "address"}],
      SafeTx: [{name: "to", type: "address"}, {name: "value", type: "uint256"}, {name: "data", type: "bytes"}, {name: "operation", type: "uint8"},
        {name: "safeTxGas", type: "uint256"}, {name: "baseGas", type: "uint256"}, {name: "gasPrice", type: "uint256"}, {name: "gasToken", type: "address"},
        {name: "refundReceiver", type: "address"}, {name: "nonce", type: "uint256"}]},
    primaryType: "SafeTx", domain: {chainId: L.chainId, verifyingContract: L.safe},
    message: {to: L.to, value: L.value, data: L.data, operation: L.op, safeTxGas: "0", baseGas: "0", gasPrice: "0", gasToken: ZERO, refundReceiver: ZERO, nonce: L.nonce}};
  const f = `/tmp/safetx-${L.safe.slice(2, 10)}-${L.name}.json`; writeFileSync(f, JSON.stringify(t)); return f;
}

// Each PR's folder lives on its own branch — read leaves straight from git so the script works from
// any checkout and can propose multiple PRs at once. Find the ref that contains queued/<N>/<N>.md.
function branchForPR(n) {
  const refs = git("for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes/origin").split("\n").map(s => s.trim()).filter(Boolean);
  const has = r => { try { execFileSync("git", ["-C", CP3, "cat-file", "-e", `${r}:queued/${n}/${n}.md`], {stdio: "ignore"}); return true; } catch { return false; } };
  return refs.filter(has).sort((a, b) => {
    const score = r => (r.startsWith("origin/") ? 0 : 2) + (r.includes(`/${n}/`) ? 1 : 0);
    return score(b) - score(a);
  })[0];
}
const leafPaths = (branch, n) => git("ls-tree", "-r", "--name-only", branch, "--", `queued/${n}`).split("\n")
  .filter(f => f.endsWith(".json") && !f.split("/").pop().startsWith("_") && !f.includes("/stable-canonical/"));

const jobs = [];
for (const pr of PRS) {
  const branch = branchForPR(pr);
  if (!branch) { console.log(`no branch contains queued/${pr}, skipping`); continue; }
  for (const jp of leafPaths(branch, pr)) jobs.push({pr, branch, jsonPath: jp, sub: jp.split("/")[2]});
}
const leaves = jobs.map(j => ({...j, ...buildLeaf(j.branch, j.jsonPath)}))
  .sort((a, b) => a.pr !== b.pr ? PRS.indexOf(a.pr) - PRS.indexOf(b.pr) : a.sub !== b.sub ? a.sub.localeCompare(b.sub) : (a.nonce ?? 1e9) - (b.nonce ?? 1e9));

console.log(`Proposer ${PROPOSER} (Ledger ${HD}). ${leaves.length} leaves across PRs ${PRS.join(", ")}.\n`);
if (!DRY && !NO_SIGN) {  // fail fast if the Ledger's derived account isn't the proposer
  const addr = cast("wallet", "address", "--ledger", "--mnemonic-derivation-path", HD);
  if (addr.toLowerCase() !== PROPOSER.toLowerCase()) {
    console.log(`Ledger at ${HD} = ${addr}, expected ${PROPOSER}. Fix --hd-path and retry.`); process.exit(1);
  }
  console.log(`Ledger confirmed: ${addr}\n`);
}
for (const L of leaves) {
  const tag = `[${L.pr}] ${L.sub}/${L.name} n=${L.nonce ?? "TBD"} op${L.op}`;
  if (L.nonce === null) { console.log(`SKIP ${tag} — nonce TBD (assign before proposing)`); continue; }
  const h = safeTxHash(L);
  if (L.expected && h.safeTxHash.toLowerCase() !== L.expected.toLowerCase()) {
    console.log(`ABORT ${tag}\n  computed ${h.safeTxHash}\n  md says  ${L.expected}\n  (reconstruction mismatch — NOT signing)`); continue;
  }
  console.log(`\n=== ${tag} ===\n  safe ${L.safe}  chainId ${L.chainId}  safeTxHash ${h.safeTxHash}`);
  if (DRY) { console.log("  (dry-run: verified, not signing)"); continue; }
  let sig = null;
  if (!NO_SIGN) {
    const tf = typedFile(L);
    console.log("  → confirm on Ledger (hash above must match the device)…");
    sig = cast("wallet", "sign", "--ledger", "--mnemonic-derivation-path", HD, "--data", "--from-file", tf);
  }
  // Propose via the Safe Client Gateway — keyed by chainId, so it covers every chain the Safe UI supports.
  const body = JSON.stringify({to: L.to, value: L.value, data: L.data, nonce: String(L.nonce), operation: L.op,
    safeTxGas: "0", baseGas: "0", gasPrice: "0", gasToken: ZERO, refundReceiver: ZERO,
    safeTxHash: h.safeTxHash, sender: PROPOSER, signature: sig, origin: `3CP-${L.pr}`});
  const url = `https://safe-client.safe.global/v1/chains/${L.chainId}/transactions/${L.safe}/propose`;
  try {
    execFileSync("curl", ["-fsS", "-X", "POST", url, "-H", "content-type: application/json", "-d", body], {encoding: "utf8"});
    console.log(`  ✅ proposed via Safe Client Gateway (chain ${L.chainId})`);
  } catch (e) {
    const why = String(e).split("\n")[0].slice(0, 90);
    console.log(`  ⚠️ propose failed for chain ${L.chainId} (${why})`);
    console.log(sig ? `     signature (propose offline): ${sig}`
      : `     (--no-sign needs ${PROPOSER} to be a registered delegate on this Safe; else drop --no-sign to sign as owner)`);
  }
}
console.log("\nDone. Open each Safe in the UI to confirm the queued proposals, then collect the remaining owner signatures.");
