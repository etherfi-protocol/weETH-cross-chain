# Arc mainnet weETH OFT deploy — runbook for the signing operator

Hand this to whoever holds the deployer Ledger. End state: the weETH OFT live on Arc (5042),
configured for ethereum/base/op, owned by the timelock.

Expect ~30 minutes, roughly 22 device confirmations.

---

## 0. What you must have

- **The deployer Ledger** holding `0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150`. There is no way
  around this — see "Why only this device" at the bottom.
- macOS or Linux, `git`, `node` 20+, `yarn`.
- Foundry. Match what the deploy was validated on: `forge 1.3.5`.
  ```bash
  curl -L https://foundry.paradigm.xyz | bash && foundryup
  forge --version   # expect 1.3.x
  ```
  Bytecode does not vary with the Foundry version here — `foundry.toml` pins `solc_version =
  "0.8.22"`, `optimizer_runs = 200` and `bytecode_hash = 'none'`, and forge fetches that solc
  itself. Contract addresses come from CREATE3 salts, not creation code, so they are identical
  regardless.
- **The Arc RPC URL**, sent to you separately by Pankaj. It is a private endpoint.

## 1. Get the code

The branch is not merged yet — check out the PR branch, not master.

```bash
git clone https://github.com/etherfi-protocol/weETH-cross-chain.git
cd weETH-cross-chain
git checkout feat/arc-onboarding
git submodule update --init --recursive
yarn install
forge build
```

`foundry.toml` sets `libs = ["node_modules", "lib"]`, so both `yarn install` and the submodule
are required. `forge build` should finish with warnings but no errors.

## 2. Create `.env`

In the repo root, containing **one line**:

```bash
ARC_MAINNET_RPC_URL=<the URL Pankaj sends you>
```

> Do not ask for, or accept, a copy of anyone else's full `.env`. That file in this repo also
> holds `PRIVATE_KEY`, `ALCHEMY_API_KEY`, `ETHERSCAN_API_KEY` and `SAFE_API_KEY`. The Arc RPC URL
> is the only value this deploy needs.

Check it resolves:

```bash
set -a; . ./.env; set +a
cast chain-id --rpc-url "$ARC_MAINNET_RPC_URL"   # expect 5042
```

## 3. Prepare the Ledger

1. Plug in and **unlock**.
2. Open the **Ethereum** app.
3. In the Ethereum app: Settings → **Blind signing = Enabled**. Without this every transaction
   fails with APDU `6985 (Conditions of use not satisfied)`.
4. **Quit Ledger Live** and any other wallet software. They hold the USB interface and Foundry
   then reports "device not found".

Confirm the device presents the deployer address:

```bash
cast wallet address --ledger
```

Expected: `0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150`.

If it returns a different address, the account is on another derivation path. Enumerate:

```bash
for i in 0 1 2 3 4; do
  echo -n "m/44'/60'/$i'/0/0  -> "
  cast wallet address --ledger --mnemonic-derivation-path "m/44'/60'/$i'/0/0" 2>/dev/null || echo "-"
done
for i in 0 1 2 3 4; do
  echo -n "m/44'/60'/0'/0/$i  -> "
  cast wallet address --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/$i" 2>/dev/null || echo "-"
done
```

Whichever path prints the deployer address, export it for step 4:

```bash
export LEDGER_DERIVATION_PATH="m/44'/60'/<n>'/0/0"
```

If no path yields it, stop — this is not the right device.

## 4. Deploy

```bash
.claude/skills/onboard-oft-chain/deploy.sh arc
```

The script runs four gates before it signs anything:

| Gate | Checks |
|---|---|
| 0 | `forge`/`cast`/`node`/`git` on PATH, `node_modules` and `lib/forge-std` populated |
| 1 | Full dry run against an Arc fork — must report `Script ran successfully` |
| 2 | Connected Ledger resolves to the deployer, else it refuses |
| 3 | Deployer funded (~0.6 needed; balance should be ~5) |

Then it prompts once. Answer `y` and it broadcasts three steps:

1. **OFT deploy + config** — ~16 txns: implementation, proxy, timelock via CREATE3, then rate
   limits, peers, enforced options, DVNs.
2. **Controller Safe** — 1 tx, deterministic 2-of-5 at `0x7a00657a…`.
3. **Ownership handoff** — ~5 txns: OFT owner, ProxyAdmin owner and LayerZero delegate all to the
   timelock.

Confirm each on the device. Arc blocks are ~400 ms, so it moves quickly.

**Gas is USDC at 18 decimals on Arc.** The balance reads like ether but is dollars. The whole run
costs well under 1 USDC against a ~5 USDC balance.

### If something goes wrong

Every step is idempotent on already-deployed addresses — re-run the same command and it skips
what already landed.

| Symptom | Cause |
|---|---|
| `Ledger device not found` | Locked, Ethereum app closed, or Ledger Live still running |
| APDU `6985` | Blind signing disabled |
| `connected Ledger is 0x… but this deploy must be signed by 0x8D5AAc…` | Wrong device or wrong derivation path — go back to step 3 |
| `OwnableUnauthorizedAccount` | You bypassed the script with a raw `forge script`. Stop and use `deploy.sh` |
| RPC timeouts | The endpoint is rate-limited. Re-run; `--slow` already serialises |
| `insufficient funds` | Send more of Arc's native USDC to the deployer |

Stop and report, rather than improvising, if any step reverts for a reason not listed here.

## 5. Report back

Paste the console output, plus:

```bash
set -a; . ./.env; set +a
R="$ARC_MAINNET_RPC_URL"
for n in OFT:0xA3D68b74bF0528fdD07263c60d6488749044914b \
         IMPL:0x08DB0DB9b5F2dcbBFDc26FF411FB2026e81DA748 \
         ADMIN:0x373ea3AEC25eB652ACa38504254eCD5459da6d19 \
         TIMELOCK:0x851Dd540f4D2Ec78120De0a0cc87B21EdE5Df5C6 \
         SAFE:0x7a00657a45420044bc526B90Ad667aFfaee0A868; do
  a="${n#*:}"; s=$(cast code "$a" --rpc-url "$R" | wc -c)
  echo "${n%%:*} $a $([ "$s" -gt 3 ] && echo DEPLOYED || echo ABSENT)"
done
cast call 0xA3D68b74bF0528fdD07263c60d6488749044914b "owner()(address)" --rpc-url "$R"
```

All five should read `DEPLOYED`, and `owner()` should be the timelock
`0x851Dd540f4D2Ec78120De0a0cc87B21EdE5Df5C6`.

Do not run anything further. Explorer verification and the reverse-peer 3CP come next and need
neither the Ledger nor this machine.

---

## Why only this device

`scripts/oft-deployment/01_OFTConfigure.s.sol:40` sets `scriptDeployer = DEPLOYER_ADDRESS` — a
hardcoded constant, not `msg.sender` — and initializes the proxy with it as OFT owner and
ProxyAdmin owner. The rate-limit, peer, enforced-option and DVN calls then run in the same
broadcast, and they are owner-gated.

From any other signer the CREATE3 deploys still succeed, because the salts carry no sender, so
the contracts land at the correct canonical addresses. Every subsequent config call then reverts.
Simulated from `0x…dEaD`:

```
[Revert] OwnableUnauthorizedAccount(0x000000000000000000000000000000000000dEaD)
Error: script failed
```

The result is Arc deployed, unconfigured, and owned by a key nobody present holds — recoverable
only by producing the real deployer. Gate 2 exists to make that a refusal instead of a
half-finished chain.

Step 2 is the one exception: the controller Safe address derives from (factory, singleton,
initializer, saltNonce) and never the deployer, so any funded signer can deploy it.
