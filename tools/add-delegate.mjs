#!/usr/bin/env node
// Add a PROPOSER (Safe delegate) to the canonical Safe across chains — run by an OWNER of the Safe.
// Delegates live off-chain in each network's Safe Transaction Service (no on-chain tx). The v2 API
// signs an EIP-712 message with chainId in the domain (anti-replay), so the owner taps the Ledger
// once PER chain, back-to-back. Proposal is POSTed via the Safe Client Gateway (chainId-keyed).
//
//   node tools/add-delegate.mjs [--hd-path "m/44'/60'/0'/0/0"] [--dry-run] [--chains op,bnb,...]
//
// Ledger: unlocked, Ethereum app open, EIP-712/blind-signing on, and CLOSE Ledger Live first.
// The signer (delegator) MUST be an owner of the Safe — the gateway rejects non-owners.
import {execFileSync} from "node:child_process";
import {writeFileSync} from "node:fs";
const cast = (...a) => execFileSync("cast", a, {encoding: "utf8"}).trim();
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : d; };
const DRY = argv.includes("--dry-run");
const HD = opt("hd-path", "m/44'/60'/0'/0/0");

const SAFE = "0x7a00657a45420044bc526B90Ad667aFfaee0A868";      // canonical controller Safe
const DELEGATE = "0x1B7Fd9679B2678F7e01897E0A3BA9aF18dF4f71e"; // proposer to add
const LABEL = "3CP proposer";
// chains where the canonical Safe holds control (from the tables) — chainId per chain.
const CHAINS = {op: 10, bnb: 56, linea: 59144, unichain: 130, hyperEVM: 999, plasma: 9745,
  scroll: 534352, swell: 1923, bera: 80094, mode: 34443, blast: 81457, morph: 2818};
const only = opt("chains"); // optional comma list to restrict
const targets = Object.entries(CHAINS).filter(([n]) => !only || only.split(",").includes(n));

// derive the owner (delegator) from the Ledger and show it
let DELEGATOR = "0x0000000000000000000000000000000000000000";
if (!DRY) {
  DELEGATOR = cast("wallet", "address", "--ledger", "--mnemonic-derivation-path", HD);
  console.log(`Delegator (Ledger ${HD}): ${DELEGATOR}`);
} else console.log("(dry-run — not touching the Ledger)");
console.log(`Adding delegate ${DELEGATE} to Safe ${SAFE} on ${targets.length} chains.\n`);

const totp = Math.floor(Date.now() / 1000 / 3600); // hourly TOTP; tx service also accepts totp-1
for (const [name, chainId] of targets) {
  const typed = {
    types: {
      EIP712Domain: [{name: "name", type: "string"}, {name: "version", type: "string"}, {name: "chainId", type: "uint256"}],
      Delegate: [{name: "delegateAddress", type: "address"}, {name: "totp", type: "uint256"}],
    },
    primaryType: "Delegate",
    domain: {name: "Safe Transaction Service", version: "1.0", chainId},
    message: {delegateAddress: DELEGATE, totp},
  };
  const f = `/tmp/delegate-${chainId}.json`; writeFileSync(f, JSON.stringify(typed));
  console.log(`=== ${name} (chainId ${chainId}) ===`);
  if (DRY) { console.log(`  typed data: ${f} (totp ${totp})`); continue; }
  console.log("  → confirm the delegate message on your Ledger…");
  const sig = cast("wallet", "sign", "--ledger", "--mnemonic-derivation-path", HD, "--data", "--from-file", f);
  const body = JSON.stringify({safe: SAFE, delegate: DELEGATE, delegator: DELEGATOR, signature: sig, label: LABEL});
  const url = `https://safe-client.safe.global/v2/chains/${chainId}/delegates`;
  try {
    execFileSync("curl", ["-fsS", "-X", "POST", url, "-H", "content-type: application/json", "-d", body], {encoding: "utf8"});
    console.log(`  ✅ delegate added on ${name}`);
  } catch (e) {
    console.log(`  ⚠️ POST failed on ${name} (${String(e).split("\n")[0].slice(0, 90)})`);
    console.log(`     retry manually: curl -X POST '${url}' -H 'content-type: application/json' -d '${body}'`);
  }
}
console.log("\nDone. Verify in Safe{Wallet} → Settings → Setup → Proposers, or GET the same /delegates endpoint.");
