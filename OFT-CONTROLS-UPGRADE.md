# weETH OFT controls upgrade

This upgrade adds new controls to the weETH L2 OFT (`EtherfiOFTUpgradeable`) and the Ethereum
adapter (`EtherfiOFTAdapterUpgradeable`). Every control is off after the upgrade. Governance turns
each one on separately.

## What changes

| Control | What it does | Who can use it |
|---------|--------------|----------------|
| Guardian pause (`pauseBridgeUntil`) | Pauses sends and receives for a set time (1 day by default, between 8 hours and 3 days). The pause ends on its own. The same address cannot pause again until its cooldown (the duration plus 1 day) ends. | `PAUSER_UNTIL` role. `unpauseBridgeUntil` needs `UNPAUSER`. |
| Lane pause (`setLanePaused`) | Pauses one peer chain in both directions. Other lanes keep working. A message for a paused lane stays in the endpoint and delivers after the unpause. | `PAUSER` pauses, `UNPAUSER` unpauses. |
| Blacklist and whitelist | Blocks addresses from transferring, receiving, minting and bridging. Modes: Open (default), Blacklist, Whitelist. The lists are enumerable (`getBlacklist`, `blacklistedCount`). | `BLACKLISTER` and `WHITELISTER` edit the lists. The owner picks the mode. |
| Escrow | Receives bridged tokens meant for a blocked recipient, so the LayerZero message still completes. Needed before a non-Open mode. | Owner |
| Bridge fee | Takes a fee in bps (capped at 1%) on a bridge and pays it to the fee deposit. A default fee and a fee per lane. Default 0. | Owner |
| Recover funds (L2 token only) | Moves tokens out of a blacklisted address. Works in Blacklist mode and only for listed addresses. | Owner |

## Roles and who holds them

Role ids on the L2 token (Solady `EnumerableRoles`): `MINTER` 1, `PAUSER` 2 and `UNPAUSER` 3 exist
today. New: `BLACKLISTER` 4, `WHITELISTER` 5, `PAUSER_UNTIL` 6. The adapter uses OpenZeppelin
`AccessControl` roles named `keccak256("<NAME>_ROLE")` for the same names.

`registry/oft-controls.json` holds the assignment below. I read the current holders on-chain on
2026-10-23.

| Role | Holder after the upgrade | Today on-chain |
|------|--------------------------|----------------|
| `PAUSER` | `0x9AF1298993DC1f397973C62A5D47a284CF76844D` on every chain. It is an EOA. | Same on every chain |
| `UNPAUSER` | Canonical Controller Safe `0x7a00657a…` on every L2. Operating Safe `0x2aCA7102…` on Ethereum. | Canonical on Base, Avalanche, Ink, Monad, Robinhood, Stable, Arc. A legacy Safe on OP (`0x764682c7…`), BNB (`0xD568c4D4…`), Linea (`0xe4ff196C…`), Unichain (`0xe54449CB…`), HyperEVM (`0xf27128a5…`) and Plasma (`0x8faD84C9…`). Operating Safe on Ethereum. |
| `MINTER` | Native-minting sync pool: Base `0xc38e046d…`, OP `0xC9475e18…`. None elsewhere. | Same |
| `BLACKLISTER`, `WHITELISTER` | The same Safe as `UNPAUSER`. Both do nothing while the mode is Open. | New |
| `PAUSER_UNTIL` | The exec guardian Safe. Its address is not in the repo, so the policy leaves it empty and the script skips the grant until it is set. | New |

Moving `UNPAUSER` to the canonical Safe on the six legacy-Safe chains is the fix the 2026-09-23
unpauser audit recommended. It needs no extra batch, because the 8 chains still on OpenZeppelin
roles must re-grant every role in the upgrade batch anyway.

Governance on-chain:

| Chain | ProxyAdmin owner | OFT owner | Proposer, executor, canceller |
|-------|------------------|-----------|-------------------------------|
| Ethereum | `0x9f26d4C9…`, 10 day delay | `0xcD425f44…`, 48 hour delay | Upgrade Safe `0xcdd57D11…` and operating Safe `0x2aCA7102…` |
| Every L2 | `0x851Dd540…`, 72 hour delay (Stable: `0xd2D4171A…`) | The same timelock | Canonical Safe `0x7a00657a…` |

On the L2s the ProxyAdmin and the OFT share a timelock, so the upgrade, the role grants and the
config go in one batch. Ethereum needs two batches because its timelocks differ.

## Why

- `pauseBridge` stops every lane and stays on until an unpauser acts. A guardian key cannot hold
  it safely. `pauseBridgeUntil` ends on its own, so a guardian can stop the bridge without being
  able to keep it stopped.
- One bad lane forces a global pause today. Lane pause stops that lane only.
- There is no way to block an address that holds stolen funds, or to move those funds. The
  allowlist blocks the address. `recoverFunds` moves the tokens, and it needs the owner.
- The fee gives governance a lever on bridge volume and revenue. It starts at zero.

## What does not change

- Every existing function, event and role stays. A diff of the ABI against `master` shows additions
  only, with one exception: the OpenZeppelin 5.3.0 bump drops three library errors from the ABI
  (`AddressEmptyCode`, `AddressInsufficientBalance`, `FailedInnerCall`). OpenZeppelin replaced them
  with `FailedCall` and `InsufficientBalance`. Only a tool that decodes those three revert reasons
  notices.
- The sequential storage slots stay the same: the two `PairwiseRateLimiter` mappings at slots 0
  and 1. All new state lives in namespaced (ERC-7201) storage.
- With the defaults (Open mode, fee 0, no pause, no lane pause), `send`, `quoteSend`, `quoteOFT`
  and `lzReceive` return the same results as before.
- There is no initializer. The upgrade batch sets the pause duration, and a guardian pause reverts
  until it is set. The owner sets the fee deposit and the escrow before turning on a fee or a
  non-Open mode.

## How it is built

`contracts/OFTControls.sol` holds the shared logic. Both contracts inherit it and map its roles to
their own role system.

From LayerZero Console (`@layerzerolabs/utils-upgradeable-evm-contracts` 1.2.84, MIT): the
allowlist, the fee config and the fee handler modules.

Differences from the LayerZero modules:

- Lane pause is a local module. The LayerZero per-lane pause cannot sit next to OpenZeppelin
  `Pausable`: both define a `whenNotPaused` modifier and a `Paused` event or error.
- The escrow is one address in namespaced storage. The LayerZero credit redirect module adds an
  external allowlist lookup that this contract's own allowlist makes redundant. It cost about 560
  bytes of the 24,576 byte size limit. The `CreditRedirected` event keeps the LayerZero signature.
- `recoverFunds` also requires Blacklist mode and a listed address. The LayerZero version only
  requires that the address is not allowlisted, which in Whitelist mode covers every holder
  outside the list.
- A transfer checks the sender and the recipient. It does not check a blocked spender, which can
  only move tokens whose owner approved it.
- The fee cap (1%) and the "fee deposit set first" rule are additions.

Not adopted:

- The Console OFT contracts. They are an adapter around a separate token. Our L2 token is the
  OFT, so adopting them means a new peer address on every chain.
- The LayerZero rate limiter. We keep `PairwiseRateLimiter` and its storage. Its outbound and
  inbound code now share one implementation, with the same ABI and behavior.
- A rate-limit manager role that can only lower limits. A manager could zero a lane, and only the
  timelock could restore it.
- Two-step ownership. It changes how `transferOwnership` behaves for existing scripts.

Size: the L2 token deploys at 23,939 bytes of 24,576. The adapter deploys at 21,767.

OpenZeppelin moves from 5.0.1 and 5.0.2 to 5.3.0. The L2 token is about 240 bytes smaller on
5.3.0. The bump changes the bytecode of every contract this repo rebuilds, so rebuilding a contract
this PR does not upgrade no longer reproduces its deployed bytecode. The contracts this PR does
upgrade change anyway. The 2026-09 comparison of the deployed OFT implementations against `master`
already found that most chains do not rebuild to the deployed bytecode.

## Behavior to know before rollout

- The 8 chains still on the old OpenZeppelin role system (Base, OP, BNB, Linea, Unichain,
  Avalanche, HyperEVM, Plasma) move to the Solady role system when they take this
  implementation. Existing `PAUSER`, `UNPAUSER` and `MINTER` holders are not carried over. The
  batch re-grants them. `grantRole` and `hasRole(bytes32,address)` disappear on those chains.
  Ethereum, Ink, Monad, Robinhood, Stable and Arc keep their roles.
- Whoever holds `BLACKLISTER` can freeze any address once the owner sets Blacklist mode. Grant it
  to a Safe, not a key.
- The cooldown is per address. Two holders of `PAUSER_UNTIL` can take turns and keep the bridge
  paused until an `UNPAUSER` ends it. Grant the role to one Safe.
- Turning on a fee changes `amountReceivedLD`. Integrators that pass `minAmountLD == amountLD`
  start to revert on slippage.
- `setDefaultFeeBps` and `setFeeBps` revert without a fee deposit, and a non-Open mode reverts
  without an escrow.

## Scripts

All three read the chain from `registry/chains.json` through `TARGET_CHAIN`.

1. `scripts/oft-controls/DeployImpl.s.sol` deploys the implementation through the CREATE3
   factory, so it lands at the same address on every chain. It reads the endpoint from the
   registry, checks the immutables, and skips a chain that already has it.

   ```bash
   TARGET_CHAIN=base forge script scripts/oft-controls/DeployImpl.s.sol --rpc-url <rpc> --broadcast
   ```

2. `scripts/oft-controls/UpgradeBatch.s.sol` builds the timelock batches from live state and writes
   Safe bundles to `output/oft-controls/<chain>-<batch>-{schedule,execute}.json`.

   ```bash
   TARGET_CHAIN=base OFT_CONTROLS_IMPL=0x... forge script scripts/oft-controls/UpgradeBatch.s.sol --rpc-url <rpc>
   ```

   It gates on what it reads:
   - The timelocks are the live owners of the ProxyAdmin and the OFT. The proposer and executor
     are the first addresses in the policy that hold those roles on the timelock.
   - It refuses to run if the registry ProxyAdmin is not the proxy's admin, the implementation
     has the wrong endpoint, or the proxy already runs this implementation.
   - It grants a role only when the holder does not hold it, so no call is a no-op that could
     revert at execution. A policy minter that does not hold `MINTER` today is skipped.
   - An empty address in the policy skips that role and prints why.

   `GUARDIAN=0x...` overrides the guardian for a fork run.

3. `tools/anvil-oft-controls.sh` rehearses the whole thing on two anvil forks (Ethereum and Base):

   ```bash
   tools/anvil-oft-controls.sh
   ```

   It deploys the implementations, builds the bundles, schedules them as the real proposers,
   waits out the real delays, executes them, and checks that every read from before the upgrade
   is unchanged and the roles are right. Then it sends real messages between the forks, in both
   directions, and relays each packet through the destination endpoint. It uses the new controls
   on those messages: a fee on each leg, a lane pause with a message that survives it, a guardian
   pause that ends by itself, a blacklist that redirects to escrow and blocks bridging, recovery,
   and a final check that the Base supply and the adapter's locked weETH moved by the same amount.
   It needs an RPC that serves historical state. It defaults to the Tenderly gateways. Set
   `ETH_RPC` and `BASE_RPC` to use others.

## Test

Unit tests, 73 tests, no network. They include `OFTControlsAttacks.t.sol`, which tries to abuse
each control:

```bash
forge test --match-path 'test/OFTControls[LA]*.t.sol'
```

Fork tests upgrade the live proxy on each live chain with its real proxy admin, then check that
every read is unchanged, `send` and `lzReceive` still work through the real endpoint, and each
control works on the real state. Run them one at a time to stay under public RPC limits:

```bash
forge test --match-path test/OFTControlsUpgradeFork.t.sol --no-match-test monad --threads 1
forge test --match-path test/OFTControlsUpgradeFork.t.sol --match-test monad --network monad
```

## Rollout

This PR changes contracts, scripts and tests. The rollout is separate. Steps, with owners:

1. Fill in `guardian` in `registry/oft-controls.json`. Owner: ether.fi security.
2. Audit the implementation. Owner: ether.fi security.
3. Deploy the implementation on each chain with `DeployImpl.s.sol`. Owner: deployer.
4. Per chain, run `UpgradeBatch.s.sol` from live state and propose the schedule bundle. Owner: the
   proposer Safe for that timelock. Ethereum has two bundles. Schedule the second after the
   upgrade executes.
5. After the delay, execute the bundle, then run `tools/verify-deployment.mjs` against the chain.
6. Before enabling a fee or a non-Open mode, set the fee deposit and the escrow with the owner.
