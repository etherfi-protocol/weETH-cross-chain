# weETH OFT controls upgrade

This upgrade adds new controls to the weETH L2 OFT (`EtherfiOFTUpgradeable`) and the Ethereum
adapter (`EtherfiOFTAdapterUpgradeable`). Every control is off after the upgrade. Governance turns
each one on separately.

## What changes

| Control | What it does | Who can use it |
|---------|--------------|----------------|
| Guardian pause (`pauseBridgeUntil`) | Pauses sends and receives for a set time (default 1 day, between 8 hours and 3 days). The pause ends on its own. | `PAUSER_UNTIL` role. `unpauseBridgeUntil` needs `UNPAUSER`. |
| Lane pause (`pauseLanes`) | Pauses one peer chain. Other lanes keep working. | `PAUSER` pauses, `UNPAUSER` unpauses. |
| Blacklist and whitelist | Blocks addresses from transferring, receiving, minting and bridging. Modes: Open (default), Blacklist, Whitelist. | `BLACKLISTER` and `WHITELISTER` edit the lists. The owner picks the mode. |
| Credit redirect | Sends bridged tokens for a blocked recipient to an escrow address. The LayerZero message still completes. | Owner |
| Bridge fee | Takes a fee in bps (capped at 1%) on every bridge and pays it to a fee deposit address. Default 0. | Owner |
| Recover funds (L2 token only) | Moves tokens out of a blacklisted address. Works in Blacklist mode and only for listed addresses. | Owner |
| Tighten-only rate limits (`tightenRateLimits`) | Lowers a lane's rate limit. Cannot raise a limit or enable a new lane. | `RATE_LIMIT_MANAGER` role. The owner keeps the full setters. |

Role ids on the L2 token (Solady `EnumerableRoles`): `PAUSER` 2 and `UNPAUSER` 3 exist today.
New: `BLACKLISTER` 4, `WHITELISTER` 5, `RATE_LIMIT_MANAGER` 6, `PAUSER_UNTIL` 7. The adapter uses
OpenZeppelin `AccessControl` roles named `keccak256("<NAME>_ROLE")` for the same names.

## Why

- `pauseBridge` stops every lane and stays on until an unpauser acts. A guardian key cannot hold
  it safely. `pauseBridgeUntil` ends on its own, so a guardian can stop the bridge without being
  able to keep it stopped.
- One bad lane forces a global pause today. Lane pause stops that lane only.
- Rate limits change only through the owner, which is the timelock. `tightenRateLimits` lets a
  Safe lower a limit in one transaction. Raising a limit still goes through the timelock.
- There is no way to block an address that holds stolen funds, or to move those funds. The
  allowlist blocks the address. `recoverFunds` moves the tokens, and it needs the owner.
- The fee gives governance a lever on bridge volume and revenue. It starts at zero.

## What does not change

- Every existing function, event, role and error stays. A diff of the ABI against `master` shows
  additions only.
- The sequential storage slots stay the same: the two `PairwiseRateLimiter` mappings at slots 0
  and 1. All new state lives in namespaced (ERC-7201) storage.
- With the defaults (Open mode, fee 0, no pause, no lane pause), `send`, `quoteSend`, `quoteOFT`
  and `lzReceive` return the same results as before.

## How it is built

`contracts/OFTControls.sol` holds the shared logic. Both contracts inherit it and map its roles
to their own role system. Each contract needs one call after the upgrade:
`initializeControls(feeDeposit, pauseUntilDuration)`. Make it part of `ProxyAdmin.upgradeAndCall`.
Only the owner or the proxy admin can call it, and it runs once.

From LayerZero Console (`@layerzerolabs/utils-upgradeable-evm-contracts` 1.2.84, MIT): the fee
handler and the credit redirect modules. The allowlist keeps the LayerZero enum, struct, events
and errors, so the event signatures match.

Differences from the LayerZero modules:

- The allowlist uses mappings instead of enumerable sets, so there are no on-chain list getters.
  Read the `BlacklistUpdated` and `WhitelistUpdated` events. The sets would put the L2 token over
  the 24,576 byte contract size limit.
- Lane pause is a local module. The LayerZero per-lane pause cannot sit next to OpenZeppelin
  `Pausable`: both define a `whenNotPaused` modifier and a `Paused` event or error.
- The fee has one rate for all lanes. The LayerZero per-lane fee config stays out for size.
- `recoverFunds` also requires Blacklist mode and a listed address. The LayerZero version only
  requires that the address is not allowlisted, which in Whitelist mode covers every holder
  outside the list.
- The L2 token deploys at 24,162 bytes, 414 bytes under the limit.

Not adopted:

- The Console OFT contracts. They are an adapter around a separate token. Our L2 token is the
  OFT, so adopting them means a new peer address on every chain.
- The LayerZero rate limiter. We keep `PairwiseRateLimiter` and its storage.
- Two-step ownership. It changes how `transferOwnership` behaves for existing scripts.

## Behavior to know before rollout

- The 8 chains still on the old OpenZeppelin role system (Base, OP, BNB, Linea, Unichain,
  Avalanche, HyperEVM, Plasma) move to the Solady role system when they take this
  implementation. Existing `PAUSER`, `UNPAUSER` and `MINTER` holders are not carried over.
  Re-grant them with `setRole` in the same batch as the upgrade. `grantRole` and `hasRole(bytes32,address)`
  disappear on those chains. Ethereum, Ink, Monad, Robinhood, Stable and Arc keep their roles.
- Whoever holds `BLACKLISTER` can freeze any address once the owner sets Blacklist mode. Grant it
  to a Safe, not a key.
- Turning on a fee changes `amountReceivedLD`. Integrators that pass `minAmountLD == amountLD`
  start to revert on slippage.
- The fee and the escrow need addresses before the controls turn on. `setDefaultFeeBps` reverts
  without a fee deposit, and a non-Open mode reverts without an escrow.

## Test

Unit tests, 54 tests, no network:

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

This PR changes contracts and tests only. The rollout is separate:

1. Deploy one implementation per endpoint address. The constructor takes the endpoint, so the
   live L2s need four implementations and Ethereum needs the adapter implementation.
2. Per chain, call `ProxyAdmin.upgradeAndCall(proxy, implementation, initializeControls(...))`
   through the existing upgrade path. Fold the `setRole` re-grants for the 8 legacy chains into
   the same batch. Build each batch from live state.
3. Grant `PAUSER_UNTIL` to the exec guardian Safe, `RATE_LIMIT_MANAGER` and `BLACKLISTER` to the
   chosen Safes, then set the fee deposit and the escrow.
