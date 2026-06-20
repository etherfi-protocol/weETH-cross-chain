---
name: onboard-oft-chain
description: Use when onboarding a new chain to the weETH cross-chain OFT mesh, or when dry-running, deploying, configuring, verifying, or wiring peers for the weETH OFT on a chain (e.g. "dry run robinhood", "deploy weETH to <chain>", "add <chain> to the mesh").
---

# Onboard a chain to the weETH OFT mesh

Registry-driven deployment of the weETH OFT to a new chain. One input — the
chain key — drives everything from `registry/chains.json` via `TARGET_CHAIN`.
The OFT, impl, proxy admin, and timelock land at the **same address on every
chain** (CREATE3). Full prose runbook: `NEW-CHAIN-ONBOARDING.md`.

## When to use
- Dry-running or deploying the weETH OFT on a new chain.
- Adding a chain's registry entry, wiring peers, verifying, or handing off ownership.

## On invocation — gather inputs, confirm the Ledger, set expectations FIRST
When the user says "deploy weETH to <chain>" (or similar), do this **before any broadcast**:

**1. Collect the inputs — ask the user, or have them set in `.env`. If any is missing, STOP and ask; never guess:**
- **Chain key** (e.g. `robinhood`) → becomes `TARGET_CHAIN`.
- **RPC** in `.env` as `<CHAIN>_MAINNET_RPC_URL` (API keys stay out of git).
- **Explorer + API key** for verification — Blockscout base URL + `<CHAIN>_API_KEY`.
- **Peer allow-list** — which existing chains it bridges with (e.g. Eth/Base/OP) and the per-pathway rate limit (default **1000 weETH / 4h**). Hand-added to `registry/chains.json`.
- **Controller Safe** — **always** the canonical `0x7a00657a45420044bc526B90Ad667aFfaee0A868` (deployed deterministically on each chain via `DeployControllerSafe`; do **not** vary it per chain). **Deployer** — recommended Ledger `0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150` (`policy.json` → `canonical.deployer`). Both live in `registry/policy.json` → `canonical`.

**2. Confirm the deployer Ledger is ready (broadcasts can't sign otherwise):**
- Connected and **unlocked**, **Ethereum app open**, with **Ledger Live / other wallet apps closed** (they grab the USB → "device not found").
- **Blind signing / contract data ENABLED** in the Ethereum app — otherwise every tx fails with APDU `6985 (Conditions of use not satisfied)`.
- The selected derivation path resolves to the deployer `0x8D5AAc…` (else pass `--mnemonic-derivation-paths`).
- The deployer holds **gas on the new chain** (~0.005 ETH; CREATE3 → addresses are deployer-independent, so any funded path works).

**3. Tell the user what to expect, so there's no misalignment:**
- A **dry run runs first** — no signing, no gas, nothing sent on-chain.
- Then **Ledger-signed broadcasts** (run in the background; confirm each tx on the device): OFT deploy + config (~15 txns), controller Safe (1 tx), ownership handoff (~5 txns).
- The remaining steps are **3CP proposals** — PRs to `3CP-secure`, signed later by the multisig, **not signed now**: reverse-peer wiring, Safe 2-of-5→4-of-7 migration, and the L1 leg (timelock schedule+execute, ~2-day delay).
- Ends with **explorer verification** of every deployed contract.

## Hard guardrails
- **Never `--broadcast` before the dry-run passes** (`Script ran successfully`).
- **Broadcast only via `--ledger`** (deployer `0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150`); no hot keys.
- **4-DVN gate:** all 4 policy DVNs must be live on the chain (dry-run / resolver fails otherwise). Do not deploy without them.
- **Do not change `solc_version`** (0.8.22 is required by OZ v5.4.0).
- Rate limits are **per-pathway**, one config per peer, from the registry (`peerLimits`/`peerWindows`). Current peers are all **1000 weETH / 4h**, but values can differ per chain.
- **Authority model:** OFT owner, ProxyAdmin owner, **and the LZ delegate** all go to the **timelock** (so DVN/library/enforced-option changes are timelock-gated, not just upgrades). Pauser = EOA (instant emergency stop), unpauser = Safe. The Safe holds proposer/executor/canceller on the timelock.

## Dry run (one command — run this first, always)
```bash
.claude/skills/onboard-oft-chain/dry-run.sh <chainKey> [rpcUrl]
```
Runs pre-flight (CreateX present, OFT address free, deployer gas) + the full
`01` deploy+config simulation against a fork — no signing, no gas, nothing sent.
Pass `rpcUrl` if the chain's RPC isn't in the registry / `.env`.

## Full flow (each step; pause for the human at signing/funding)
1. **Registry entry:** `node tools/resolve-chain.mjs <chainKey> --rpc <url>` → resolves endpoint, 302 libs, 4 sorted DVNs into `registry/chains.json`. Then hand-add the peer allow-list (`peerEids`/`peerOfts`/`peerLimits`/`peerWindows`). Set `CONTROLLER_SAFE` to the canonical `0x7a00657a…` (same on every chain — copy from `policy.json` → `canonical.controllerSafe`); set `OFT`/`OFT_IMPL`/`PROXY_ADMIN`/`TIMELOCK` to the canonical CREATE3 addresses. Policy in `registry/policy.json`.
2. **Load check:** `TARGET_CHAIN=<chainKey> forge test --match-contract TargetLoaderTest -vvv`.
3. **Dry run:** the script above. Must end `Script ran successfully`.
4. **Deploy OFT + config (Ledger):**
   ```bash
   TARGET_CHAIN=<chainKey> forge script scripts/oft-deployment/01_OFTConfigure.s.sol:DeployOFTScript \
     --rpc-url <url> --ledger --sender <deployer> --broadcast --slow
   ```
   Deployer must hold gas first (CREATE3 → addresses are deployer-independent). Skip inline `--verify` (forge can't map CREATE3 factory deploys).
5. **Deploy controller Safe (Ledger):**
   ```bash
   forge script scripts/oft-deployment/DeployControllerSafe.s.sol:DeployControllerSafe \
     --rpc-url <url> --ledger --sender <deployer> --broadcast
   ```
   Deterministic 2-of-5 at `0x7a00657a…` from the recovered initializer; idempotent (skips if already deployed); asserts the canonical address. Migrate to 4-of-7 in step 10.
6. **Ownership handoff (deployer Ledger, NOT a 3CP for a fresh deploy):**
   `forge script scripts/oft-deployment/03_OFTOwnershipTransfer.s.sol:OFTOwnershipTransfer --rpc-url <url> --sender <deployer> --ledger --broadcast --slow`
   → OFT owner, ProxyAdmin owner, **and LZ delegate all → timelock**; pauser = EOA, unpauser = Safe. (The Safe from step 5 must exist — it becomes unpauser + timelock proposer/executor.) `make-3cp-folder --type handoff` is only for migrating chains *already* Safe-owned.
7. **Verify roles/config on-chain:** `TARGET_CHAIN=<chainKey> forge script scripts/oft-deployment/04_OFTVerification.s.sol:verifyOFT` — owner/proxyAdmin/**delegate all == timelock**, pauser == EOA, unpauser == Safe, DVN 4-of-4@45, limits. (Needs the registry to carry the chain's RPC; for Robinhood the API key is scrubbed, so spot-check with `cast` instead.)
8. **Verify all deployed contracts on the explorer** (do this for every deploy — see Contract verification below).
9. **Reverse-peer wiring (3CP):** one proposal per peer chain (Eth/Base/OP) — `setPeer` + rate limit + **4-of-4 DVN@45 + enforced options** for the new EID. Without the DVN config the inbound side falls back to the chain's **1-DVN default** — always include it. `node tools/make-3cp-folder.mjs --type peer --chain <chainKey> --peer <eth|base|optimism> --rpc <peerRpc> --out <3CP>`. Routing auto-detected: Safe-owned → direct; timelock-owned (L1) → schedule+execute pair.
10. **Safe migration 2-of-5 → 4-of-7 (3CP, last):** `node tools/make-3cp-folder.mjs --type safe-migration --chain <chainKey> --out <3CP>` — signed by the original owners.

## 3CP PRs — ONE PR, ONE number, per-chain subfolders
A multi-chain batch (reverse-peer for Eth+Base+OP, a schedule+execute pair, etc.)
goes in **a single PR under a single proposal number**, with **one subfolder per
chain inside it** — NOT multiple top-level numbered folders, NOT separate PRs:

```
queued/<id>/
  ethereum/  ethereum.json  ethereum.md
  base/      base.json      base.md
  optimism/  optimism.json  optimism.md
```

Branch `pankaj/<id>/<desc>`, commit the whole `queued/<id>/` tree, open one PR
titled for the batch. A single-chain proposal stays flat: `queued/<id>/<id>.{json,md}`.
For each leaf: generate hashes (`safe_hashes.sh` single tx · `build_multisend.sh`
multi-tx; for chains not in the tool's network list — e.g. Robinhood/4663 —
compute the Safe-1.3.0 EIP-712 hash with `cast` and validate the domain against
the Safe's on-chain `domainSeparator()`), and append a `## Hashes` table (+ Safe-app
link where the chain is on the Safe UI) to that leaf's md.

Batch generation: pass `--id <sharedNum> --subdir <chain>` per chain so they all
land under one number as subfolders, e.g.
`node tools/make-3cp-folder.mjs --type peer --chain robinhood --peer base --rpc <url> --nonce <n> --id 580 --subdir base --out <3CP>`
(repeat for op/ethereum). The eth schedule+execute auto-split into
`ethereum/ethereum-schedule.*` and `ethereum/ethereum-execute.*`. Then one branch,
commit `queued/<id>/`, one PR.

## Contract verification (explorer)
Always verify after deploy. CREATE3 factory deploys aren't auto-verified, so run
`forge verify-contract` per contract. **Robinhood (Blockscout):** use the
**`blockscout`** verifier — NOT `etherscan` (forge 1.3.x can't map a custom chain
id to a key; the v2 API is auth-gated). No key needed:
`forge verify-contract <addr> <Contract> --verifier blockscout --verifier-url https://8crv4vmq6tiu1yqr.blockscout.com/api/ --chain 4663 --compiler-version 0.8.22 --constructor-args <...>`.
OZ contracts (proxy, ProxyAdmin) must use the **bare name** (`TransparentUpgradeableProxy`, `ProxyAdmin`), not the `@openzeppelin/...` path. Full command set: `NEW-CHAIN-ONBOARDING.md` → Contract verification.

**Controller Safe** (`GnosisSafeProxy` 1.3.0, solc **0.7.6** — different toolchain, so forge can't match it): verify with the dedicated tool, which posts the canonical source and **auto-tries the common Safe build configs** until one matches (Robinhood's matched optimizer **off**, runs 200, istanbul):
```bash
node tools/verify-safe-blockscout.mjs --safe <safe> --singleton <singleton> \
  --explorer https://8crv4vmq6tiu1yqr.blockscout.com/api/ --apikey "$ROBINHOOD_API_KEY"
```
Verify **all** deployed contracts (4 OFT contracts + the Safe) before considering a deploy done.

## Common mistakes
- Broadcasting from the Ledger account with 0 gas → "insufficient funds". Fund it first.
- Hardcoding one rate limit for all peers — limits are per-pathway from the registry `peerLimits`/`peerWindows` (same 1000/4h for the current peers, but kept per-chain).
- `OwnableUnauthorizedAccount` in the dry run → you omitted `--sender <deployer>` (the dry-run script sets it).
