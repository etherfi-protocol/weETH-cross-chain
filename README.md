# ether.fi's weETH Cross-Chain Contracts

Solidity contracts that take weETH beyond Ethereum mainnet. weETH moves between chains as a
LayerZero V2 OFT: the mainnet `EtherFiOFTAdapter` locks weETH, and each L2 mints the same
amount of `EtherfiOFTUpgradeable`. Every weETH on another chain is backed 1:1 by weETH held
in the adapter.

[Docs](https://etherfi.gitbook.io/etherfi/) ·
[Cross-chain addresses](https://etherfi.gitbook.io/etherfi/developers/contracts-and-integrations/deployed-contracts#cross-chain-token-contracts) ·
[Core protocol contracts](https://github.com/etherfi-protocol/smart-contracts) ·
[Audits](audit/)

## Contracts

| Area | Path | Contracts |
|------|------|-----------|
| OFT | `contracts/` | `EtherfiOFTUpgradeable` (L2 token), `EtherFiOFTAdapterUpgradeable` (mainnet lockbox) |
| Rate limiting | `contracts/` | `PairwiseRateLimiter`, `PausableUntil` |
| Governance | `contracts/` | `EtherFiTimelock` |
| Native minting | `contracts/native-minting/` | `EtherfiL1SyncPoolETH`, `EtherfiL2ExchangeRateProvider`, `BucketRateLimiter`, `DummyTokenUpgradeable` |
| L2 sync pools | `contracts/native-minting/l2-syncpools/` | OP Stack, Scroll, and Hydra (Berachain) sync pools |
| L1 receivers | `contracts/native-minting/receivers/` | Scroll and Hydra receivers |
| LayerZero base | `contracts/native-minting/layerzero-base/` | Shared messenger, receiver, and sync pool bases |

`contracts/archive` holds retired contracts kept for reference.

Contract addresses on every chain live in the ether.fi docs under
[Cross-chain Token Contracts](https://etherfi.gitbook.io/etherfi/developers/contracts-and-integrations/deployed-contracts#cross-chain-token-contracts).
`registry/chains.json` holds the full per-chain deployment: endpoint, libraries, DVNs, proxy
admin, timelock, and controller Safe.

## Architecture

- **Same address everywhere.** CREATE3 deploys the OFT, its implementation, the proxy admin,
  and the timelock at one address on every new chain. Only the LayerZero endpoint, libraries,
  DVNs, controller Safe, and peer list change per chain.
- **DVN policy.** Every pathway requires four DVNs (LayerZero Labs, Nethermind, Horizen, P2P) at
  45 confirmations. `registry/policy.json` holds the policy, and `tools/dvn-policy.test.mjs`
  enforces it.
- **Rate limits.** On the L2 OFTs, `PairwiseRateLimiter` caps how much weETH each peer chain can
  send and receive in a time window. The mainnet adapter has no pairwise limiter.
- **Governance.** Each chain has a controller Safe. Some OFTs are owned by the Safe directly
  (Base, Optimism) and others by a timelock the Safe drives (the Ethereum adapter). Either
  way, changes go through ether.fi's 3CP process.
- **Native minting.** On chains with a sync pool, users deposit ETH on the L2 and receive weETH
  right away. The sync pool later settles the ETH to `EtherfiL1SyncPoolETH` on mainnet, which
  mints the backing weETH.

## Getting started

Requirements: [Foundry](https://book.getfoundry.sh/getting-started/installation), Node.js, and
Yarn.

```bash
git clone https://github.com/etherfi-protocol/weETH-cross-chain.git
cd weETH-cross-chain
yarn build        # yarn install, forge install, forge build
yarn test         # policy tests in tools/, then forge test
yarn test:policy  # policy tests only
```

The build uses Solidity 0.8.22. Fork tests need the chain RPC URLs in `.env`.

## Repository layout

| Path | Purpose |
|------|---------|
| `contracts/` | OFT, timelock, rate limiter, and native-minting contracts |
| `test/` | Foundry unit and fork tests |
| `scripts/` | Deploy, upgrade, and Safe transaction scripts |
| `registry/` | Per-chain deployment data and mesh-wide policy |
| `tools/` | Node scripts for 3CP proposals, deployment checks, and contract verification |
| `utils/` | LayerZero and Gnosis helpers, DVN and endpoint metadata |
| `audit/` | Audit reports |

## Runbooks

- [Onboarding a new chain](NEW-CHAIN-ONBOARDING.md): add a chain to the weETH OFT mesh from a
  single registry entry.
- [Native minting upgrade timelock](NATIVE-MINTING-UPGRADE-TIMELOCK.md): move native-minting
  upgrade authority from the controller Safe to the upgrade timelock.

## 📄 License

ether.fi is open-source and licensed under the [MIT License](LICENSE).

Vendored third-party interfaces keep the licenses of the projects they came from, as marked by
the SPDX header in each file. That covers `interfaces/IStargate.sol` (BUSL-1.1).

---

<p align="center">Built with ❤️ by the ether.fi team</p>
