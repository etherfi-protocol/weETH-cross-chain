# Arc Mainnet (5042) — weETH OFT onboarding

Status as of 2026-09-14: **prep complete, dry run green, waiting on Ledger broadcasts.**

## Chain facts (all verified live, not copied)

| | |
|---|---|
| chainId | 5042 |
| LZ EID | 30417 (confirmed against `endpoint.eid()`, not just metadata) |
| LZ endpoint | `0x6f475642a6e85809b1c36fa62763669b1b48dd5b` |
| SEND_302 | `0xc39161c743d0307eb9bcc9fef03eeb9dc4802de7` |
| RECEIVE_302 | `0xe1844c5d63a9543023008d332bd3d2e6f1fe1043` |
| Executor | `0x4208d6e27538189bb48e603d6123a94b8abe0a0b` |
| Native gas token | **USDC, 18 decimals** — a balance that looks like ether is dollars |
| Explorer | Blockscout, `https://explorer.arc.io` |
| Safe{Wallet} | supported, shortName `arc` |
| RPC | private, `ARC_MAINNET_RPC_URL` in `.env` (kept out of git via `RPC_ENV`) |

Pre-flight: CreateX present; Safe 1.3.0 singleton, proxy factory, fallback handler and
MultiSendCallOnly (`0xA1dabEF3…`) all deployed; all five canonical mesh addresses free.

## DVN set — 4-of-4 @ 45 confirmations

| Provider | Address | |
|---|---|---|
| P2P | `0x69df29c29afcc8d1a0ee563a27827427f89ef698` | live |
| Nethermind | `0x9e0e95ede70f680f74480b510ff9f45c70e3da80` | live |
| LayerZero Labs | `0xa2447e5b58d357c49bf74b50b14421e6a100e525` | live |
| Horizen | `0xd36246c322ee102a2203bca9cafb84c179d306f6` | live |

Matches the four addresses supplied by the operators, sorted ascending.

**Two Arc addresses deliberately excluded:**

- `0x282b3386571f7f794450d5789911a9804fa346b4` — LayerZero Labs, **deprecated**. Arc lists two
  LZ Labs DVNs and enumerates the dead one first, so the old resolver picked it. See below.
- `0xacde1f22eeab249d3ca6ba8805c8fee9f52a16e7` — Canary, retired mesh-wide. Added to
  `policy.retiredDvns.arc`. Note this same address is **Horizen on mode** — the per-chain keying
  of `retiredDvns` is what stops a flat denylist rejecting a legitimate DVN.

### The resolver bug this onboarding caught

`resolveDvns` took the first metadata entry matching a provider name and ignored `deprecated`.
On every existing mesh chain the first match happens to be live, so this never showed. On Arc it
is not, and the first run produced a required set containing a DVN that no longer attests —
a pathway that can never reach 4-of-4 and can never verify a message.

Nothing downstream would have caught it: the address is a real DVN, it passes the canonical
lint, it encodes cleanly, and the Safe tx hash is valid. It would have surfaced as weETH
bridged to Arc and never arriving.

Fixed in `tools/resolve-chain.mjs` (filter `deprecated`, throw when a provider has no live
address), with three regression tests against a real Arc metadata fixture.

## Peers — Ethereum + Base + OP @ 1000 weETH / 4h

| Peer | EID | OFT |
|---|---|---|
| ethereum | 30101 | `0xcd2eb13D6831d4602D80E5db9230A57596CDCA63` (adapter) |
| base | 30184 | `0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A` |
| op | 30111 | `0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF` |

## Dry run

`Script ran successfully` — 16 txns, 12,493,982 gas, ~0.512 USDC at the quoted 41 gwei.
Deployer `0x8D5AAc…` holds 5 USDC, so deploy + Safe + handoff clears comfortably.

Simulated calldata asserted to contain all four live DVNs, all three peer EIDs, and **neither**
the deprecated LZ Labs DVN nor Canary. Only contracts touched: CreateX, the CREATE2 factory,
the OFT, and the LZ endpoint.

## What you need to run (Ledger — I cannot sign these)

Ledger unlocked, Ethereum app open, **blind signing on**, Ledger Live closed, derivation path
resolving to `0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150`.

```bash
cd /Users/pankajjagtap/etherfi/Stake/weETH-cross-chain
set -a; . ./.env; set +a
D=0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150

# 1. OFT deploy + config  (~16 txns)
TARGET_CHAIN=arc forge script scripts/oft-deployment/01_OFTConfigure.s.sol:DeployOFTScript \
  --rpc-url "$ARC_MAINNET_RPC_URL" --ledger --sender $D --broadcast --slow

# 2. Controller Safe  (1 tx, deterministic 2-of-5 at 0x7a00657a…)
forge script scripts/oft-deployment/DeployControllerSafe.s.sol:DeployControllerSafe \
  --rpc-url "$ARC_MAINNET_RPC_URL" --ledger --sender $D --broadcast

# 3. Ownership handoff  (~5 txns — owner, proxyAdmin, delegate all -> timelock)
TARGET_CHAIN=arc forge script scripts/oft-deployment/03_OFTOwnershipTransfer.s.sol:OFTOwnershipTransfer \
  --rpc-url "$ARC_MAINNET_RPC_URL" --ledger --sender $D --broadcast --slow
```

The RPC is rate-limited — `--slow` already serialises, but if you see timeouts, rerun; both
scripts are idempotent on already-deployed addresses.

## After the broadcasts land, I pick back up with

4. `04_OFTVerification.s.sol` — owner/proxyAdmin/delegate all == timelock, pauser EOA,
   unpauser Safe, DVN 4-of-4 @ 45, limits.
5. Blockscout verification of all 6 contracts (4 OFT + Safe proxy + Safe singleton).
   **Needs `ARC_API_KEY` in `.env`** — not set yet, please add it.
6. The reverse-peer 3CP: one PR, one number, three subfolders (`ethereum/` schedule+execute via
   timelock, `base/` and `optimism/` direct-Safe). setPeer + inbound **and** outbound rate limits
   + 4-of-4 DVN@45 + enforced options + library pins generated from a live fork.
7. Proposal-replay end-to-end test across all four chains before anything is signed.
8. Safe 2-of-5 → 4-of-7 migration 3CP, last.
