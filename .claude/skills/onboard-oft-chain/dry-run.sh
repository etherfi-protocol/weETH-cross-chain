#!/usr/bin/env bash
# Pre-flight checks + full deploy/config dry-run (simulation, NO broadcast) for
# onboarding a chain to the weETH OFT mesh. Nothing is signed or sent on-chain.
#
# Usage: dry-run.sh <chainKey> [rpcUrl]
#   chainKey  key in registry/chains.json (e.g. robinhood)
#   rpcUrl    optional; defaults to registry RPC_URL, else $<CHAIN>_MAINNET_RPC_URL from .env
set -euo pipefail

CHAIN="${1:?usage: dry-run.sh <chainKey> [rpcUrl]}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

# Load API-keyed RPCs from .env if present.
# shellcheck disable=SC1091
if [ -f .env ]; then set -a; . ./.env; set +a; fi

# RPC: explicit arg > registry RPC_URL > $<CHAIN>_MAINNET_RPC_URL
RPC="${2:-$(node -e "process.stdout.write((require('./registry/chains.json')['$CHAIN']||{}).RPC_URL||'')")}"
if [ -z "$RPC" ]; then
  ENVVAR="$(printf '%s' "$CHAIN" | tr '[:lower:]' '[:upper:]')_MAINNET_RPC_URL"
  RPC="${!ENVVAR:-}"
fi
[ -n "$RPC" ] || { echo "ERROR: no RPC for '$CHAIN' (pass as arg2 or set in registry/.env)" >&2; exit 1; }

DEPLOYER=0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150
CREATEX=0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed

read -r OFT EID < <(node -e "const c=require('./registry/chains.json')['$CHAIN']||{};console.log((c.OFT||'-')+' '+(c.L2_EID||'-'))") || true

echo "== pre-flight: $CHAIN =="
echo "chainId        : $(cast chain-id --rpc-url "$RPC")"
echo "registry EID   : $EID"
createx_code="$(cast code "$CREATEX" --rpc-url "$RPC")"
if [ "${#createx_code}" -gt 2 ]; then echo "CreateX        : OK"; else echo "CreateX        : *** MISSING — deploy factory first ***"; fi
if [ "$OFT" != "-" ]; then
  oft_code="$(cast code "$OFT" --rpc-url "$RPC")"
  if [ "${#oft_code}" -le 2 ]; then echo "OFT address    : free (empty)"; else echo "OFT address    : *** ALREADY DEPLOYED ($OFT) ***"; fi
fi
echo "deployer gas   : $(cast balance "$DEPLOYER" --rpc-url "$RPC") wei  ($DEPLOYER)"
echo "               (0 is fine for dry-run; must be funded before --broadcast)"

echo
echo "== dry-run simulation (no broadcast, no Ledger, no gas) =="
TARGET_CHAIN="$CHAIN" forge script scripts/oft-deployment/01_OFTConfigure.s.sol:DeployOFTScript \
  --fork-url "$RPC" --sender "$DEPLOYER" -vvv

echo
echo "Dry-run complete. 'Script ran successfully' above == deploy + config simulate cleanly."
