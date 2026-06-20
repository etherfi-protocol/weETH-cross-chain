# Onboarding a new chain to the weETH OFT mesh

Minimal, end-to-end steps to add a new chain. Everything is driven by one
registry entry keyed by `TARGET_CHAIN`. The OFT, its implementation, the proxy
admin, and the timelock are deployed at the **same address on every chain** via
CREATE3, so the only per-chain inputs are the LayerZero endpoint/libraries/DVNs,
the controller Safe, and the peer allow-list.

Prerequisites: a funded deployer (Ledger), the new chain's RPC in `.env`, and
the chain present in LayerZero's deployment metadata (endpoint + 4 policy DVNs
must already exist on it — that is the gating check).

## Inputs you provide

- **Chain key** — short lowercase name (e.g. `robinhood`). Becomes `TARGET_CHAIN`.
- **RPC URL** — added to `.env` (keep API keys out of git; the registry RPC is optional).
- **Peer allow-list** — which existing chains this chain bridges with, and the
  per-pathway rate limit. Current policy: **1,000 weETH / 4h** with
  Ethereum (EID 30101), Base (30184), Optimism (30111).

Fixed for every chain (do not vary): **controller Safe** `0x7a00657a45420044bc526B90Ad667aFfaee0A868`
and recommended **deployer** Ledger `0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150`
(`registry/policy.json` → `canonical`).

## Steps

### 1. Add the registry entry

```bash
node tools/resolve-chain.mjs <chainKey> --rpc "$NEW_CHAIN_RPC_URL"
```

Resolves the endpoint, send/receive 302 libraries, and the 4 policy DVNs
(LayerZero Labs, Nethermind, Horizen, Canary — sorted ascending) from LayerZero
metadata and writes them into `registry/chains.json`. Then hand-add the peer
allow-list fields (`peerEids`, `peerOfts`, `peerLimits`, `peerWindows`) and set
`CONTROLLER_SAFE` to the canonical `0x7a00657a…` (same on every chain — from
`policy.json` → `canonical.controllerSafe`). Policy constants live in `registry/policy.json`.

If a DVN provider is missing on the chain, the resolver throws — **do not
deploy** until all four are live (this is the hard security gate).

### 2. Load-check the entry

```bash
TARGET_CHAIN=<chainKey> forge test --match-contract TargetLoaderTest -vvv
```

Confirms `_loadTarget()` reads the entry: EID, 4 DVNs, peer arrays line up.

### 3. Dry run (mandatory, no broadcast)

```bash
TARGET_CHAIN=<chainKey> forge script scripts/oft-deployment/01_OFTConfigure.s.sol:DeployOFTScript \
  --fork-url "$NEW_CHAIN_RPC_URL" -vvv | tee output/dry-run-<chainKey>.log
```

Simulates the full lifecycle against a fork of the new chain: CREATE3 deploy of
impl/proxy/timelock (with the `require(deployed == canonical)` and CreateX
`extcodesize` asserts), `setPeer`, `setConfig` (4-of-4 DVNs @ 45 confirmations
on both send and receive libs), enforced options, and per-pathway rate limits.

> `test/OFTDeployment.t.sol` reads the **live** config of already-deployed mesh
> chains — it cannot validate a not-yet-deployed chain. Use the `01` simulation
> above for the new chain; run `OFTDeployment.t.sol` only against live chains.

If CreateX is not deployed on the new chain, deploy the factory first (its
address is deployer-independent: `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`).

### 4. Broadcast the deploy + config (Ledger)

```bash
TARGET_CHAIN=<chainKey> forge script scripts/oft-deployment/01_OFTConfigure.s.sol:DeployOFTScript \
  --rpc-url "$NEW_CHAIN_RPC_URL" --ledger --broadcast --verify
```

No hot keys — the deployer Ledger signs. The deterministic addresses match the
mesh because CREATE3 depends only on `(factory, salt)`, not the deployer.

### 5. Wire the reverse direction — 3CP per peer chain

Each chain in the allow-list must accept the new chain. Generate one 3CP
proposal per peer (setPeer + the 1000 weETH/1h pathway rate limit on L2s):

```bash
for PEER in ethereum base optimism; do
  node tools/make-3cp-folder.mjs --type peer --chain <chainKey> --peer "$PEER" \
    --rpc "$<PEER>_RPC_URL" --out /path/to/3CP-secure
done
```

Routing is automatic from the peer OFT's on-chain owner:
- **Safe-owned** (e.g. Base, Optimism) → a direct Safe bundle.
- **Timelock-owned** (e.g. the Ethereum L1 adapter) → a **scheduleBatch + executeBatch**
  pair on that chain's timelock (the controlling Safe submits both; execute runs
  after the delay). The L1 adapter has no pairwise limiter, so it gets `setPeer` only.

The tool reads each Safe's live nonce and warns if an open PR already targets
that Safe — bump the nonce if so.

### 6. Verify on-chain

```bash
TARGET_CHAIN=<chainKey> forge script scripts/oft-deployment/04_OFTVerification.s.sol:verifyOFT
```

Asserts implementation/proxy bytecode, roles (owner & proxy-admin owner ==
timelock, pauser EOA, unpauser/delegate == Safe, timelock roles), and — when a
peer allow-list is present — the 4-of-4 DVN ULN config @ 45 confirmations,
enforced options, and per-pathway inbound/outbound rate limits.

### 7. Hand owner + delegate to the timelock, then stage the 3CP proposal

Generate the owner+delegate→timelock Safe bundle, then package it as a 3CP
proposal folder ready for `3CP-secure`:

```bash
node tools/make-3cp-folder.mjs --type handoff --chain <chainKey> \
  --rpc "$NEW_CHAIN_RPC_URL" --out /path/to/3CP-secure
```

`make-3cp-folder.mjs` builds the bundle straight from `registry/chains.json`
(so it works before any helper Solidity script knows the chain) — `setDelegate`
then `transferOwnership`, both to the chain's `TIMELOCK`. It picks the next free
3CP folder id (across local `queued/` and open PRs), reads the Safe nonce
on-chain, and prints the `build_multisend.sh` verify command. `--out` defaults
to `$CP3_REPO` or the sibling `../../3CP-secure` checkout. Pass `--bundle` to
reuse a pre-generated bundle (e.g. from
`Generate-OFT-Owner-Delegate-Transfer.s.sol`). Open the folder as a PR in
`3CP-secure`.

### 8. Migrate the controller Safe to 4-of-7

The Safe is deployed at the canonical address with the original **2-of-5**
owner set (that initializer is what reproduces the address). After the handoff,
migrate it to the mesh standard **4-of-7**:

```bash
node tools/make-3cp-folder.mjs --type safe-migration --chain <chainKey> --out /path/to/3CP-secure
```

This emits the Safe self-call bundle (`addOwnerWithThreshold` for each added
owner, the last call setting threshold 4), signed by the original 2-of-5
owners. The owner sets and thresholds come from `registry/policy.json`
(`controllerSafe`).

## Contract verification (explorer source)

`forge script --broadcast --verify` tries to verify everything it created, but
the OFT/impl/proxyAdmin/timelock are **CREATE3-deployed via the factory**, so
forge often can't auto-verify them. Verify each manually after deploy.

**Robinhood (Blockscout):** use the **`blockscout`** verifier — NOT `etherscan`.
forge 1.3.x's etherscan verifier can't map a custom chain id (4663) to an API
key and errors `ETHERSCAN_API_KEY must be set`; the Blockscout v2 API is also
auth-gated. The `blockscout` verifier posts to the open etherscan-compatible
`/api/` and needs **no key**. OZ contracts (proxy, ProxyAdmin) must be referenced
by **bare contract name**, not the `@openzeppelin/...` path (forge errors
`Failed to get standard json input` otherwise).

```bash
EXPLORER=https://8crv4vmq6tiu1yqr.blockscout.com/api/
V="--verifier blockscout --verifier-url $EXPLORER --chain 4663 --compiler-version 0.8.22"

# 1. OFT implementation — constructor(address endpoint)
forge verify-contract 0x08DB0DB9b5F2dcbBFDc26FF411FB2026e81DA748 \
  contracts/EtherfiOFTUpgradeable.sol:EtherfiOFTUpgradeable $V \
  --constructor-args "$(cast abi-encode 'constructor(address)' 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B)"

# 2. OFT proxy — constructor(address logic, address initialOwner, bytes data)
INIT=$(cast calldata 'initialize(string,string,address)' 'Wrapped eETH' 'weETH' 0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150)
forge verify-contract 0xA3D68b74bF0528fdD07263c60d6488749044914b \
  TransparentUpgradeableProxy $V \
  --constructor-args "$(cast abi-encode 'constructor(address,address,bytes)' 0x08DB0DB9b5F2dcbBFDc26FF411FB2026e81DA748 0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150 "$INIT")"

# 3. ProxyAdmin (auto-deployed by the proxy) — constructor(address initialOwner)
forge verify-contract 0x373ea3AEC25eB652ACa38504254eCD5459da6d19 \
  ProxyAdmin $V \
  --constructor-args "$(cast abi-encode 'constructor(address)' 0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150)"

# 4. EtherFiTimelock — constructor(uint256 minDelay, address[] proposers, address[] executors, address admin)
forge verify-contract 0x851Dd540f4D2Ec78120De0a0cc87B21EdE5Df5C6 \
  contracts/EtherFiTimelock.sol:EtherFiTimelock $V \
  --constructor-args "$(cast abi-encode 'constructor(uint256,address[],address[],address)' 259200 '[0x7a00657a45420044bc526B90Ad667aFfaee0A868]' '[0x7a00657a45420044bc526B90Ad667aFfaee0A868]' 0x0000000000000000000000000000000000000000)"
```

The OFT proxy will then resolve its implementation automatically. Browsing the
explorer UI to confirm needs the instance login (the same `ROBINHOOD_API_KEY`);
the verify API itself does not.

## Registry as source of truth

`registry/chains.json` holds the current on-chain setup for every mesh chain
(OFT, impl, proxy admin, controller Safe, timelock, endpoint, libraries, sorted
DVNs). It is derived from `utils/L2Constants.sol` and spot-checked against live
RPC. Keep it updated when a chain's config changes.
