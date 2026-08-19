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
- **Never sign a wiring 3CP until the proposal-replay end-to-end test is green** — replay the exact `queued/<N>` Safe txns (schedule→warp→execute / direct) on a fork of **every** chain in the batch, then bridge both ways. A clean safe-tx hash proves *what* is signed, not *that the bridge works after it executes*. See step 9.

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
9. **Reverse-peer wiring (3CP):** one proposal per peer chain (Eth/Base/OP) — `setPeer` + **inbound AND outbound rate limits** + **4-of-4 DVN@45 + enforced options + pinned message libraries** for the new EID. Without the DVN config the inbound side falls back to the chain's **1-DVN default** — always include it. **Rate limits are mandatory on EVERY peer including the L1 adapter** — `EtherFiOFTAdapterUpgradeable` *and* `EtherfiOFTUpgradeable` both inherit `PairwiseRateLimiter`, and an **unset** pathway has limit 0 → `amountCanBeSent == 0` → every bridge in/out of that pathway reverts (`Out/InboundRateLimitExceeded`) on day one. (This bit #574: `make-3cp-folder.mjs` had a `chainId == 1` guard that skipped L1 rate limits on the false premise "L1 adapter has none" — removed. Never special-case mainnet for rate limits.) **Pin the libraries too** (`setSendLibrary` / `setReceiveLibrary` to the 302 libs): a pathway left on the LayerZero **default** lib silently follows a LZ default-library rotation with no governance action on our side. `node tools/make-3cp-folder.mjs --type peer --chain <chainKey> --peer <eth|base|optimism> --rpc <peerRpc> --out <3CP>`. **`--rpc` is required for the lib pin** — the tool reads `isDefaultSendLibrary`/`getReceiveLibrary` off a live fork and emits a pin **only where the pathway is still on the default** (a blind pin reverts `LZ_SameValue`; see gotchas). Routing auto-detected: Safe-owned → direct; timelock-owned (L1) → schedule+execute pair. The tool runs a **canonical-address lint** before writing (see "Further hardening") and refuses to emit a proposal that touches a non-canonical address.
   **Prove it end-to-end before signing — replay the EXACT proposal bytes, then bridge.** Don't just reconstruct the intended config; load the literal Safe-tx JSONs from `queued/<N>/` and *execute them the way they'll execute in production*, on a fork of **every chain in the batch**, then bridge on that same post-execution fork. This is the only check that proves "once this 3CP lands, all pathways work" — a missing rate limit, a mis-encoded DVN blob, a wrong delegate, etc. surface as a revert here, never in the safe-tx hash. The end-to-end test (`test/RobinhoodRoundTrip.t.sol::testProposalEndToEnd_AllChains`) does, per chain:
   - **Replay the proposed transactions** pranked as the JSON's `safeAddress`: direct-Safe chains → call each `tx.to`/`tx.data` (equals the MultiSend execution); **timelock chains → `scheduleBatch`, `vm.warp(block.timestamp + minDelay + 1)`, then `executeBatch`** — so the delay path itself is exercised.
   - **Then bridge both ways on the same fork:** a real `send` (outbound → `_debit`/outbound limit) **and** an endpoint-impersonated `lzReceive` (inbound → `_credit`/inbound limit), each asserted to succeed, plus an over-limit amount asserted to revert.

   Point it at the proposal folder and give every chain an RPC: `PROPOSAL_DIR=/abs/path/3CP-secure/queued/<N> ETH_MAINNET_RPC_URL=… BASE_MAINNET_RPC_URL=… OP_MAINNET_RPC_URL=… <NEWCHAIN>_MAINNET_RPC_URL=… forge test --match-test testProposalEndToEnd_AllChains -vv` (needs `fs_permissions` read on the 3CP repo). Keep the faster reconstructed-config tests (`*RoundTrip`, `*RevertsWithoutRateLimits`, `*ToAndFro`) and `test/OFTDeployment.t.sol` as self-contained checks, but the **proposal-replay end-to-end run is the gate before signing**. When you add a chain to the batch, add its leg to the end-to-end test. Test gotchas: precompute any `public`-library call (e.g. `_toBytes32`) **before** `vm.prank` (a delegatecall consumes the prank); do the inbound mint **before** any `deal()` (forge `deal` perturbs the OFT's ERC-7201 storage and overflows the next mint); `vm.warp` past the live `lastUpdated` so the decay math doesn't underflow.
10. **Safe migration 2-of-5 → 4-of-7 (3CP, last):** `node tools/make-3cp-folder.mjs --type safe-migration --chain <chainKey> --out <3CP>` — signed by the original owners.
11. **Verification report (reviewer artifact):** `node tools/verify-deployment.mjs --chain <chainKey>` → writes `output/verify-<chainKey>.md`. A point-in-time on-chain snapshot with ✅/❌/⚠️ per check (deployment + canonical addresses, ownership/delegate → timelock, timelock roles, controller Safe composition, per-pathway peers/limits/enforced-options/DVN on the new chain **and** the reverse-peer acceptance on each peer), each with the `cast` command to re-run it and explorer/Safe/doc links. RPCs resolve from `--rpc`/`--peer-rpc key=url`, else `.env` `<KEY>_MAINNET_RPC_URL`, else an Alchemy URL built from `ALCHEMY_API_KEY` (eth/base/op) — the key never enters the report. Run it twice: right after deploy (peer-side + Safe-migration checks read ❌ = **pending** until the 3CPs execute), then again after the proposals land (they should flip to ✅). For pauser/unpauser (role-registry indices, not enumerable via `cast`) it points to the forge verifier in step 7. It also spot-checks that the **deployer EOA holds no timelock role** (backdoor check); full extra-holder detection needs a `RoleGranted` event scan (see "Further hardening").

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

### Hashing: single-tx → direct call; multi-tx → the Safe's MultiSendCallOnly
The `safeTxHash` depends on `to` + `operation`, and these differ by **how many txns** the
leaf has — get this wrong and the hash won't match what the signer sees (same domain hash,
different message/safeTx hash):

- **1 transaction** → Safe{Wallet} proposes it as a **direct call (`operation 0`, `to` = the
  target)** — NOT MultiSend-wrapped. Hash with `safe_hashes.sh --to <to> --data <data>
  --operation 0`. (The eth `scheduleBatch` / `executeBatch` and single-transfer leaves are this.)
- **2+ transactions** → wrapped in **MultiSendCallOnly** (`operation 1`, `to` = the MultiSend).
  Hash with `build_multisend.sh --multisend <addr>`.

**The MultiSend address is per-Safe, keyed to the Safe's version** (read `VERSION()` off the
Safe). Safe{Wallet} uses the MultiSendCallOnly for that version — for **1.3.0** that's the
eip155/Singleton-Factory **`0xA1dabEF33b3B82c7814B6D82A79e50F4AC44102B`** (fallback canonical
`0x40A2aCCb…`); for **1.4.1** it's **`0x9641d764…`**. NEVER the plain MultiSend `0xA238CBeb…`
(allows sub-call `delegatecall`).

`make-3cp-folder.mjs` does all of this automatically with `--rpc`: `resolveMultiSend(safe,rpc)`
reads the Safe version and picks the deployed MultiSendCallOnly, and the emitted verify command
is the **direct** form for single-tx leaves and the **MultiSend** form for batches. Always
confirm against a **Tenderly Safe simulation / Transaction Builder** — the `to`/`operation` it
shows is what to hash against. (Verified: base/op/eth/robinhood Safes are 1.3.0 → `0xA1dabEF3…`.)

### Chains with no Safe web UI — sign on-chain
**Check before you assume.** Fetch `https://safe-config.safe.global/api/v1/chains/?limit=200`
and look the chainId up; that list is the source of truth for both support and the EIP-3770
short name used in signing links. As of 2026-08-19 **every live mesh chain is supported**,
Robinhood (4663), Monad (143), Ink (57073), Plasma (9745) and HyperEVM (999) included — an
earlier version of this doc named those as UI-less, which was wrong and pushed signers toward a
manual flow they did not need.

Only when the live chain list genuinely omits a chain, document the on-chain
flow in the leaf md + PR body: (1) each of ≥threshold owners runs
`cast send <safe> "approveHash(bytes32)" <safeTxHash> --ledger --sender <owner>` from their
own key; verify with `approvedHashes(address,bytes32)`; (2) anyone runs `execTransaction(...)`
with `to`/`operation`/`data` = the leaf's tx (MultiSendCallOnly + op 1 for batches, or the
direct target + op 0 for single-tx) and a `signatures` blob of **pre-approved** entries (one
per approver, sorted by owner address ascending: `owner` left-padded to 32 bytes ‖ 32 zero
bytes ‖ `01`). See `queued/574/safe-migration/safe-migration.md` for a worked example.

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
**Safe singleton / master copy** (`GnosisSafeL2` 1.3.0 `0xfb1bffC9…`): the proxy is a thin
delegatecall to this — **verifying the proxy alone is NOT enough**; until the singleton is
verified Blockscout won't surface the Safe's `approveHash`/`execTransaction` under "Write as
Proxy", which blocks on-chain signing via the explorer. It's multi-file solc 0.7.6, so rebuild
the exact standard-json from Sourcify (perfect-match source set) and submit:
```bash
ROBINHOOD_API_KEY=… node tools/verify-safe-singleton-blockscout.mjs \
  --singleton 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA \
  --explorer https://8crv4vmq6tiu1yqr.blockscout.com/api/
```
Verify **all** deployed contracts before considering a deploy done: the 4 OFT contracts, the
controller Safe **proxy**, *and* the Safe **singleton** (6 total). Signing via `cast approveHash`
works without any of this — explorer verification is for the UI + transparency.

## Deprecated chains — skip for mesh-wide operations
These chains are **deprecated**; exclude them from mesh-wide actions (reverse-peer
wiring, governance/Safe unification, ownership→timelock migrations) unless explicitly
told otherwise:

**Scroll, Swell, Berachain, zkSync, Mode, Blast, Morph, Sonic, Stable.**

(zkSync is also structurally special — its canonical timelock address isn't deployed
under Era's different address derivation.) When onboarding a new chain, wire peers only
with the **live** peers in the allow-list; never add a deprecated chain as a new peer.

## Common mistakes
- Broadcasting from the Ledger account with 0 gas → "insufficient funds". Fund it first.
- **"Ledger device not found"** → device locked, Ethereum app not open, or Ledger Live /
  another wallet is holding the USB. Unlock, open the Ethereum app, close other wallet apps.
- Hardcoding one rate limit for all peers — limits are per-pathway from the registry `peerLimits`/`peerWindows` (same 1000/4h for the current peers, but kept per-chain).
- **Skipping rate limits on the L1 adapter** (or any peer) — the adapter inherits `PairwiseRateLimiter` just like the L2 OFTs; an unset pathway reverts every bridge in/out. Set inbound **and** outbound on every peer, mainnet included. Caught only by a round-trip send test, never by hash verification.
- `OwnableUnauthorizedAccount` in the dry run → you omitted `--sender <deployer>` (the dry-run script sets it).

## Recurring gotchas (re-read before queuing any wiring 3CP)
These have bitten the bridge ops repeatedly — the source-of-truth playbook is
**protocol-ops `docs/oft-bridge-security-hardening.md`** (PR #55); read it before any new
hardening/onboarding op. The two that hit cross-chain wiring directly:

1. **DVN `setConfig` ABI offset word.** The `ulnBytes` blob is a *dynamically-encoded*
   struct — it must lead with the `0x20` offset word (correct blob is **416 B**, the flat-tuple
   mis-encoding is 384 B). The flat form **hashes cleanly but reverts on decode at execution**.
   Bit us in 3CP-521 and again in 574. The tool encodes it correctly (`abi-encode
   "f((uint64,uint8,uint8,uint8,address[],address[]))"`); to verify, decode with an extra paren
   so `cast` treats it as dynamic: `cast --abi-decode "x()((uint64,uint8,uint8,uint8,address[],address[]))" 0x<inner>`.
2. **Library pins revert `LZ_SameValue` if already pinned.** Pinning send/receive libs is a
   real control (T2 — stops the LZ endpoint owner swapping the default lib out from under us),
   but most live pathways are already pinned. **Always generate pin calls from a live fork and
   emit only where `isDefaultSendLibrary == true`** — never from a static list. The tool does
   this (requires `--rpc`); bit the 474 ETHFI/EURC batch when pinned blindly.
3. **A zero rate limit reverts the bridge — it does not mean "unlimited".** `PairwiseRateLimiter`
   returns `amountCanBeSent == 0` for any EID never configured (the `_amountCanBeSent` decay math
   resolves to `limit`, which is 0). So a wiring 3CP that sets peer/DVN/libs but **omits the
   rate-limit calls leaves the pathway dead on arrival** — and the omission is invisible in the
   safe-tx hash. Set inbound + outbound for the new EID on **every** peer (L1 included). This is
   exactly what slipped through on #574's ethereum leaf. Verify with the round-trip send test, not
   the hash.

**Two separate OApps — don't conflate.** The OFT mesh (this skill) and the native-mint SyncPool
are distinct OApps and are hardened separately; a control applied to one is not applied to the
other. **Hardening arc / order** (from the playbook): config (DVN) → library pin → quorum (Safe
4-of-7) → native-mint parity → deprecation/onboarding with the same primitives.

## Further hardening — what's enforced vs pending
Full backlog + threat mapping: `audit/oft-hardening-backlog.md`.

**Enforced by the tooling now:**
- **Canonical-address lint (`make-3cp-folder.mjs`).** Before writing any proposal the tool runs
  `assertCanonical` and **fails the build** if a call touches a non-canonical address — every
  `tx.to` must be a known OFT/endpoint/timelock/Safe/MultiSend; peer DVNs must be the policy count,
  unique, sorted, and valid; a handoff target must be the canonical timelock; a safe-migration must
  target the canonical controller Safe. This is a hard gate, not a reviewer's eyeball — a
  wrong/attacker `setPeer` target or stray DVN can't be emitted.
- **Message-library pinning** (step 9) and **deployer-backdoor spot-check** (step 11, below).

**`verify-deployment.mjs` deployer-backdoor check.** The report now asserts the **deployer EOA
holds none of PROPOSER/EXECUTOR/CANCELLER**. Note: `EtherFiTimelock` is plain `TimelockController`
(`AccessControl`, **not** `AccessControlEnumerable`) — `getRoleMember` reverts — so detecting
*unknown* extra role holders requires a **`RoleGranted`/`RoleRevoked` event scan**, which belongs
in the drift monitor, not a view call.

**Pending (tracked in the backlog) — do these as the mesh matures:**
- **Executor config (ULN type 1).** We pin DVNs (type 2) + libraries but never the **executor**;
  every pathway rides the LZ default executor (liveness/censorship + `maxMessageSize` exposure, not
  authenticity). Pinning needs (a) a per-chain canonical executor in the registry — `resolve-chain`
  should populate `EXECUTOR` for every chain, today only some carry it — and (b) a call to LZ on
  whether pinning the executor fits our profile. Until then, treat executor as a **documented
  known-default**, not a silent gap.
- **Drift monitor (cron)** + **cross-chain supply invariant** (`Σ L2 totalSupply == L1 locked`) —
  the point-in-time `verify-deployment` report is the seed; make it `--all` + JSON and schedule it.
- **Onboarding unprotected-window invariant:** the new chain's *own* receive DVN is set at deploy
  (`01_OFTConfigure`) but its libraries/executor are **not** pinned there yet — wire no peer to a
  new chain before its receive side is on the 4-DVN config, and pin its own libs in a follow-up.
- **Emergency runbook:** pauser-EOA liveness/drill; canceller (Safe) can cancel a malicious
  scheduled op inside the 48h window; document `endpoint.skip/nilify/burn/clear` for a stuck or
  poisoned inbound message.
