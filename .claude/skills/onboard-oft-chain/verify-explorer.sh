#!/usr/bin/env bash
# Verify every deployed weETH OFT contract on a chain's Blockscout explorer.
#
# Arc's explorer is behind Cloudflare Access, so this runs everything through
# tools/cf-access-proxy.mjs, which attaches the Access credential forge cannot send itself.
#
# Usage:
#   CF_AUTHORIZATION=<cookie> .claude/skills/onboard-oft-chain/verify-explorer.sh arc
#   CF_ACCESS_CLIENT_ID=… CF_ACCESS_CLIENT_SECRET=… .claude/skills/onboard-oft-chain/verify-explorer.sh arc
set -euo pipefail

CHAIN="${1:?usage: verify-explorer.sh <chainKey>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
[ -f .env ] && { set -a; . ./.env; set +a; }

[ -n "${CF_AUTHORIZATION:-}" ] || [ -n "${CF_ACCESS_CLIENT_ID:-}" ] || {
  echo "ERROR: set CF_AUTHORIZATION (browser cookie) or CF_ACCESS_CLIENT_ID + CF_ACCESS_CLIENT_SECRET" >&2
  exit 1
}

EXPLORER="${EXPLORER_URL:-https://explorer.arc.io}"
PORT="${PROXY_PORT:-8555}"
CHAIN_ID="$(node -e "process.stdout.write(require('./registry/chains.json')['$CHAIN'].CHAIN_ID)")"
SOLC=0.8.22

read -r OFT IMPL PA TL SAFE <<EOF
$(node -e "const c=require('./registry/chains.json')['$CHAIN'];console.log([c.OFT,c.OFT_IMPL,c.PROXY_ADMIN,c.TIMELOCK,c.CONTROLLER_SAFE].join(' '))")
EOF

ENDPOINT="$(node -e "process.stdout.write(require('./registry/chains.json')['$CHAIN'].L2_ENDPOINT)")"
DEPLOYER=0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150
SINGLETON=0xfb1bffC9d739B8D520DaF37dF666da4C687191EA

echo "== starting Cloudflare Access proxy -> $EXPLORER =="
node tools/cf-access-proxy.mjs --upstream "$EXPLORER" --port "$PORT" &
PROXY_PID=$!
trap 'kill $PROXY_PID 2>/dev/null || true' EXIT
sleep 2

V=(--verifier blockscout --verifier-url "http://127.0.0.1:$PORT/api/" --chain "$CHAIN_ID" --compiler-version "$SOLC")

# Reject a stale credential before burning four verification attempts on it.
echo "== auth preflight =="
if ! curl -sf --max-time 20 "http://127.0.0.1:$PORT/api/v2/stats" >/dev/null; then
  echo "ERROR: the explorer rejected the credential. Grab a fresh CF_Authorization cookie." >&2
  exit 1
fi
echo "auth OK"
echo

ok=0; fail=0
verify() { # label address contract ctor-args...
  local label="$1" addr="$2" contract="$3"; shift 3
  echo "== $label  $addr"
  if forge verify-contract "$addr" "$contract" "${V[@]}" "$@" 2>&1 | tail -4; then
    ok=$((ok+1))
  else
    fail=$((fail+1)); echo "  ^ FAILED"
  fi
  echo
}

INIT_DATA="$(cast calldata "initialize(string,string,address)" "Wrapped eETH" "weETH" "$DEPLOYER")"

verify "OFT implementation" "$IMPL" EtherfiOFTUpgradeable \
  --constructor-args "$(cast abi-encode 'f(address)' "$ENDPOINT")"

verify "ProxyAdmin" "$PA" ProxyAdmin \
  --constructor-args "$(cast abi-encode 'f(address)' "$DEPLOYER")"

verify "OFT proxy" "$OFT" TransparentUpgradeableProxy \
  --constructor-args "$(cast abi-encode 'f(address,address,bytes)' "$IMPL" "$DEPLOYER" "$INIT_DATA")"

verify "Timelock" "$TL" EtherFiTimelock \
  --constructor-args "$(cast abi-encode 'f(uint256,address[],address[],address)' 259200 "[$SAFE]" "[$SAFE]" 0x0000000000000000000000000000000000000000)"

# The Safe proxy and singleton are solc 0.7.6 with a different build config, so forge cannot match
# them. Dedicated tools post the canonical Safe sources and try the known Safe build configs.
echo "== Safe proxy + singleton (solc 0.7.6, separate toolchain) =="
node tools/verify-safe-blockscout.mjs --safe "$SAFE" --singleton "$SINGLETON" \
  --explorer "http://127.0.0.1:$PORT/api/" || echo "  Safe proxy verification failed"
node tools/verify-safe-singleton-blockscout.mjs --singleton "$SINGLETON" \
  --explorer "http://127.0.0.1:$PORT/api/" || echo "  Safe singleton verification failed"

echo
echo "== done: $ok forge contracts verified, $fail failed =="
echo "Check: $EXPLORER/address/$OFT"
