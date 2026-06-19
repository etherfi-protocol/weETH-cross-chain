# Native minting: move upgrade authority to the upgrade timelock

Today the native-minting proxies are upgradeable by the chain's **controller
Safe directly, with no timelock delay**. This change moves that upgrade
authority to the upgrade timelock so an implementation swap inherits the same
delay as the rest of governance.

Scope: Ethereum and Optimism (the chains requested).

## What moves

| Chain | Contract | ProxyAdmin | New owner (upgrade timelock) |
|-------|----------|------------|------------------------------|
| Ethereum | L1 sync pool (`0xD78987…`) | `0xDBf6bE12…` | `0x9f26d4…` (10-day) |
| Optimism | L2 sync pool (`0xC9475e…`) | `0xecA0b8…` | `0x851Dd5…` (canonical L2) |
| Optimism | exchange-rate provider (`0xAaE0d7…`) | `0x5ab0DC…` | `0x851Dd5…` |
| Optimism | rate limiter (`0x9685Ff…`) | `0xc706AC…` | `0x851Dd5…` |

Each transaction is `ProxyAdmin.transferOwnership(<timelock>)`, executed by the
chain's controller Safe.

On Ethereum the L1 **receiver** and **dummy-token** proxy admins are already
owned by `0x9f26d4…`, so only the shared L1 sync pool admin needs to move.

## Transactions (ready for 3CP)

- `output/ethereum-NativeMinting-ProxyAdmin-ToTimelock.json` — L1 controller Safe `0x2aCA71…`, 1 tx.
- `output/optimism-NativeMinting-ProxyAdmin-ToTimelock.json` — OP controller Safe `0x764682…`, 3 txs.

## Verification

`test/NativeMintingUpgradeTimelock.t.sol` forks Ethereum and Optimism, executes
each transfer as the Safe, and asserts (a) the ProxyAdmin owner becomes the
timelock and (b) the Safe can no longer upgrade. `test/L1SyncPoolUpgrade.t.sol`
further proves the L1 sync pool can still be upgraded *through* the timelock
(schedule → wait `minDelay` → execute) after the move.

```bash
forge test --match-path test/NativeMintingUpgradeTimelock.t.sol -vv
forge test --match-path test/L1SyncPoolUpgrade.t.sol -vv
```

## Note

Any upgrade pushed from this repo would ship current-repo logic; the deployed
L1 sync pool implementation is not byte-reproducible from current source
(compiler/source drift), so reconcile that before the first real upgrade.
