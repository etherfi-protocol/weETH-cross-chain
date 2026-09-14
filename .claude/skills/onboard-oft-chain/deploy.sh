#!/usr/bin/env bash
# Ledger-signed deploy of the weETH OFT to a chain already present in registry/chains.json.
# Runs the dry-run first and refuses to broadcast unless the connected Ledger resolves to the
# canonical deployer.
#
# Usage: deploy.sh <chainKey> [rpcUrl]
#
# Steps 1 and 3 are owner-gated and ONLY work from the deployer key. The OFT is initialized with
# a hardcoded DEPLOYER_ADDRESS as owner and ProxyAdmin owner (01_OFTConfigure.s.sol:40,62), so a
# different signer deploys the contracts fine and then reverts OwnableUnauthorizedAccount on the
# first config call — a half-deployed chain. This script checks the device up front instead.
# Step 2 (controller Safe) is sender-independent and anyone funded can run it.
set -euo pipefail

CHAIN="${1:?usage: deploy.sh <chainKey> [rpcUrl]}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
if [ -f .env ]; then set -a; . ./.env; set +a; fi

node -e "process.exit(require('./registry/chains.json')['$CHAIN'] ? 0 : 1)" 2>/dev/null || {
  echo "ERROR: '$CHAIN' is not a key in registry/chains.json. Known keys:" >&2
  node -e "console.error('  '+Object.keys(require('./registry/chains.json')).join(' '))" >&2
  exit 1
}

# RPC: explicit arg > registry RPC_URL > registry RPC_ENV > $<CHAIN>_MAINNET_RPC_URL.
# The env-var name is derived from the chain key, so scrub anything not legal in an identifier
# rather than letting bash fail on `${!var}` with a confusing "invalid variable name".
RPC="${2:-$(node -e "process.stdout.write((require('./registry/chains.json')['$CHAIN']||{}).RPC_URL||'')")}"
if [ -z "$RPC" ]; then
  ENVVAR="$(node -e "process.stdout.write((require('./registry/chains.json')['$CHAIN']||{}).RPC_ENV||'')")"
  if [ -z "$ENVVAR" ]; then
    ENVVAR="$(printf '%s' "$CHAIN" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]_' '_')_MAINNET_RPC_URL"
  fi
  RPC="${!ENVVAR:-}"
fi
[ -n "$RPC" ] || { echo "ERROR: no RPC for '$CHAIN' (pass as arg2, or set ${ENVVAR:-RPC_ENV} in .env)" >&2; exit 1; }

DEPLOYER=0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150
DERIV="${LEDGER_DERIVATION_PATH:-}"
LEDGER_ARGS=(--ledger)
[ -n "$DERIV" ] && LEDGER_ARGS+=(--mnemonic-derivation-path "$DERIV")

lower() { tr '[:upper:]' '[:lower:]'; }

# ---- gate 0: toolchain, so a fresh machine fails here and not 3 minutes into a fork ---------
missing=""
for bin in forge cast node git; do
  command -v "$bin" >/dev/null 2>&1 || missing="$missing $bin"
done
[ -z "$missing" ] || { echo "ERROR: not on PATH:$missing" >&2; exit 1; }
# foundry.toml sets libs = ["node_modules", "lib"], so both must be populated before forge build
[ -d "$ROOT/node_modules" ] || { echo "ERROR: node_modules missing — run 'yarn install'" >&2; exit 1; }
[ -f "$ROOT/lib/forge-std/src/Test.sol" ] || {
  echo "ERROR: lib/forge-std missing — run 'git submodule update --init --recursive'" >&2; exit 1; }

# CREATE3 addresses come from the salt, not the code, so building against the wrong dependency
# version puts DIFFERENT bytecode at the canonical address and nothing downstream notices —
# the dry run passes, the addresses assert clean, only explorer verification later disagrees.
# shellcheck disable=SC2016  # "+name+" is JS string concatenation, not shell expansion
node -e '
const fs=require("fs"), pkg=require("'"$ROOT"'/package.json");
const pinned={...(pkg.resolutions||{}), ...(pkg.overrides||{})};
let bad=[];
for (const [name, want] of Object.entries(pinned)) {
  let got;
  try { got=JSON.parse(fs.readFileSync("'"$ROOT"'/node_modules/"+name+"/package.json","utf8")).version; }
  catch { bad.push(name+": not installed (want "+want+")"); continue; }
  if (got!==want) bad.push(name+": installed "+got+", pinned "+want);
}
if (bad.length) {
  console.error("ERROR: dependency versions do not match the pin:\n  "+bad.join("\n  "));
  console.error("\nnpm ignores yarn `resolutions`. Install with yarn, or npm respecting `overrides`:");
  console.error("  yarn install --frozen-lockfile     # preferred, matches yarn.lock");
  console.error("  npm ci                             # honours the overrides block");
  process.exit(1);
}' || exit 1

echo "== weETH OFT deploy: $CHAIN =="
echo "chainId  : $(cast chain-id --rpc-url "$RPC")"
echo "deployer : $DEPLOYER"
echo

# ---- gate 1: dry run must pass before anything is signed -----------------------------------
LOG="/tmp/oft-dry-${CHAIN}.log"
echo "== gate 1/3: dry run =="
if ! "$ROOT/.claude/skills/onboard-oft-chain/dry-run.sh" "$CHAIN" "$RPC" >"$LOG" 2>&1; then
  echo "DRY RUN FAILED — nothing was signed. Full log: $LOG" >&2
  tail -25 "$LOG" >&2
  exit 1
fi
grep -q "Script ran successfully" "$LOG" || {
  echo "dry run did not report success — aborting. Log: $LOG" >&2; exit 1; }
echo "dry run OK"
echo

# ---- gate 2: the connected Ledger must BE the deployer ---------------------------------------
echo "== gate 2/3: Ledger identity =="
echo "Unlock the device, open the Ethereum app, enable blind signing, close Ledger Live."
LEDGER_ADDR="$(cast wallet address "${LEDGER_ARGS[@]}" 2>/dev/null || true)"
if [ -z "$LEDGER_ADDR" ]; then
  echo "ERROR: no Ledger found. Device locked, Ethereum app closed, or another wallet holds the USB." >&2
  exit 1
fi
if [ "$(printf '%s' "$LEDGER_ADDR" | lower)" != "$(printf '%s' "$DEPLOYER" | lower)" ]; then
  cat >&2 <<MSG
ERROR: connected Ledger is $LEDGER_ADDR, but this deploy must be signed by $DEPLOYER.

Steps 1 and 3 are owner-gated on a hardcoded deployer address, so a different key would deploy
the contracts and then revert on the first config call, leaving the chain half-deployed.

If this device holds the deployer on another derivation path, re-run with:
  LEDGER_DERIVATION_PATH="m/44'/60'/1'/0/0" $0 $CHAIN
Otherwise this must be run from the device that holds $DEPLOYER.
MSG
  exit 1
fi
echo "Ledger OK: $LEDGER_ADDR"
echo

# ---- gate 3: gas ------------------------------------------------------------------------------
echo "== gate 3/3: funding =="
BAL="$(cast balance "$DEPLOYER" --rpc-url "$RPC")"
NEED=600000000000000000   # ~0.6 native (18dp); full deploy simulates at ~0.53 on arc
echo "balance: $BAL (native, 18dp)"
if [ "$(printf '%s\n%s\n' "$BAL" "$NEED" | sort -g | head -1)" = "$BAL" ] && [ "$BAL" != "$NEED" ]; then
  echo "WARNING: balance is below ~0.6 native. The deploy may run out mid-way." >&2
  read -r -p "Continue anyway? [y/N] " a; [ "$a" = "y" ] || exit 1
fi
echo

read -r -p "All gates passed. Broadcast to $CHAIN now? [y/N] " go
[ "$go" = "y" ] || { echo "aborted, nothing signed"; exit 0; }

run_step() {
  echo
  echo "=================== $1 ==================="
  shift
  "$@"
}

run_step "step 1/3 — OFT deploy + config (~16 txns)" \
  env TARGET_CHAIN="$CHAIN" forge script \
    scripts/oft-deployment/01_OFTConfigure.s.sol:DeployOFTScript \
    --rpc-url "$RPC" "${LEDGER_ARGS[@]}" --sender "$DEPLOYER" --broadcast --slow

run_step "step 2/3 — controller Safe (1 tx)" \
  forge script scripts/oft-deployment/DeployControllerSafe.s.sol:DeployControllerSafe \
    --rpc-url "$RPC" "${LEDGER_ARGS[@]}" --sender "$DEPLOYER" --broadcast

run_step "step 3/3 — ownership handoff to timelock (~5 txns)" \
  env TARGET_CHAIN="$CHAIN" forge script \
    scripts/oft-deployment/03_OFTOwnershipTransfer.s.sol:OFTOwnershipTransfer \
    --rpc-url "$RPC" "${LEDGER_ARGS[@]}" --sender "$DEPLOYER" --broadcast --slow

cat <<DONE

=================== done ===================
Deployed and handed off. Ownership, ProxyAdmin and the LZ delegate are now the timelock.

Next (no Ledger needed):
  TARGET_CHAIN=$CHAIN forge script scripts/oft-deployment/04_OFTVerification.s.sol:verifyOFT --rpc-url <rpc>
  node tools/verify-deployment.mjs --chain $CHAIN

Each step is idempotent on already-deployed addresses, so a failed run can be re-run.
DONE
