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
POLL_MS="${POLL_MS:-10000}"
MIN_GAP="${MIN_GAP_MS:-1500}"

read -r OFT IMPL PA TL SAFE <<EOF
$(node -e "const c=require('./registry/chains.json')['$CHAIN'];console.log([c.OFT,c.OFT_IMPL,c.PROXY_ADMIN,c.TIMELOCK,c.CONTROLLER_SAFE].join(' '))")
EOF

ENDPOINT="$(node -e "process.stdout.write(require('./registry/chains.json')['$CHAIN'].L2_ENDPOINT)")"
DEPLOYER=0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150
SINGLETON=0xfb1bffC9d739B8D520DaF37dF666da4C687191EA

echo "== starting Cloudflare Access proxy -> $EXPLORER =="
node tools/cf-access-proxy.mjs --upstream "$EXPLORER" --port "$PORT" --min-gap "$MIN_GAP" &
PROXY_PID=$!
trap 'kill $PROXY_PID 2>/dev/null || true' EXIT
sleep 2


# Reject a stale credential before spending verification attempts on it.
echo "== auth preflight =="
if ! curl -sf --max-time 20 "http://127.0.0.1:$PORT/api/v2/stats" >/dev/null; then
  echo "ERROR: the explorer rejected the credential. Grab a fresh CF_Authorization cookie." >&2
  exit 1
fi
echo "auth OK"
echo

RESULTS=()
ok=0; fail=0

# Blockscout answers a submission with "OK" + a GUID and then verifies asynchronously, so a
# successful POST says nothing about the outcome. verify-direct polls the GUID, and reading the
# contract back afterwards is what actually proves it landed.
is_verified() { # address
  curl -s --max-time 25 "http://127.0.0.1:$PORT/api?module=contract&action=getsourcecode&address=$1" \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const r=Array.isArray(j.result)?j.result[0]:j.result;process.exit(r&&r.SourceCode&&r.SourceCode.length>0?0:1)}catch{process.exit(1)}})'
}

# verify-direct builds the standard-json offline and makes one POST plus polls. forge would spend
# three GETs per contract before submitting, which a rate-limited explorer refuses outright.
verify() { # label address contract ctor-args-hex
  local label="$1" addr="$2" contract="$3" ctor="${4:-}"
  echo "== $label  $addr"
  if is_verified "$addr"; then
    echo "  already verified — skipping"
    RESULTS+=("OK       $label (was already verified)"); ok=$((ok+1)); echo; return
  fi
  if node tools/verify-direct.mjs --address "$addr" --contract "$contract" \
       --explorer "http://127.0.0.1:$PORT/api/" --constructor-args "$ctor" \
       --poll-ms "$POLL_MS" 2>&1 | sed 's/^/  /'; then
    RESULTS+=("OK       $label"); ok=$((ok+1))
  else
    RESULTS+=("FAILED   $label  ($contract @ $addr)"); fail=$((fail+1))
  fi
  echo
}

INIT_DATA="$(cast calldata "initialize(string,string,address)" "Wrapped eETH" "weETH" "$DEPLOYER")"

verify "OFT implementation" "$IMPL" EtherfiOFTUpgradeable "$(cast abi-encode 'f(address)' "$ENDPOINT")"

verify "ProxyAdmin" "$PA" ProxyAdmin "$(cast abi-encode 'f(address)' "$DEPLOYER")"

verify "OFT proxy" "$OFT" TransparentUpgradeableProxy "$(cast abi-encode 'f(address,address,bytes)' "$IMPL" "$DEPLOYER" "$INIT_DATA")"

verify "Timelock" "$TL" EtherFiTimelock "$(cast abi-encode 'f(uint256,address[],address[],address)' 259200 "[$SAFE]" "[$SAFE]" 0x0000000000000000000000000000000000000000)"

# The Safe proxy and singleton are solc 0.7.6 with a different build config, so forge cannot match
# them. Dedicated tools post the canonical Safe sources and try the known Safe build configs.
echo "== Safe proxy + singleton (solc 0.7.6, separate toolchain) =="
node tools/verify-safe-blockscout.mjs --safe "$SAFE" --singleton "$SINGLETON" \
  --explorer "http://127.0.0.1:$PORT/api/" || echo "  Safe proxy verification failed"
node tools/verify-safe-singleton-blockscout.mjs --singleton "$SINGLETON" \
  --explorer "http://127.0.0.1:$PORT/api/" || echo "  Safe singleton verification failed"

for a in "Safe proxy:$SAFE" "Safe singleton:$SINGLETON"; do
  if is_verified "${a#*:}"; then RESULTS+=("OK       ${a%%:*}"); ok=$((ok+1))
  else RESULTS+=("FAILED   ${a%%:*}  (${a#*:})"); fail=$((fail+1)); fi
done

echo
echo "================ result ================"
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "  $ok verified, $fail failed"
echo
echo "Confirm in a browser: $EXPLORER/address/$OFT"
[ "$fail" -eq 0 ]
