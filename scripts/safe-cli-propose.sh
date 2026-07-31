#!/usr/bin/env bash
#
# safe-cli-propose.sh <chain>
#
# Launches safe-cli pointed at the correct Safe + RPC for a given L2 and
# prints the two commands you need to paste to load Ledger and the
# tx-builder JSON produced by Generate-OFT-Owner-Delegate-Transfer.s.sol.
#
# Install once (requires Python 3.10+):
#   pipx install 'safe-cli[ledger]'
# (the `[ledger]` extra is required; without it safe-cli prints
#  "Ledger=Disabled  Optional ledger library is not installed".)
#
# Plug in the Ledger, unlock, open the Ethereum app, and run:
#   ./scripts/safe-cli-propose.sh base
#
# Override the derivation path:
#   LEDGER_DERIVATION_PATH="m/44'/60'/1'/0/0" ./scripts/safe-cli-propose.sh base

set -euo pipefail

CHAIN="${1:-}"
DEFAULT_LEDGER_PATH="m/44'/60'/0'/0/0"
DERIVATION_PATH="${LEDGER_DERIVATION_PATH:-$DEFAULT_LEDGER_PATH}"

SUPPORTED="ethereum blast mode linea base bnb morph op scroll zksync swell bera unichain avax sonic hyperEVM"

if [ -z "$CHAIN" ]; then
    echo "usage: $0 <chain>" >&2
    echo "  chain ∈ { $SUPPORTED }" >&2
    exit 1
fi

# safe + rpc per chain (mirrors utils/L2Constants.sol as of 2026-05-22)
case "$CHAIN" in
    ethereum) SAFE=0x2aCA71020De61bb532008049e1Bd41E451aE8AdC; RPC=https://mainnet.gateway.tenderly.co ;;
    blast)    SAFE=0xa4822d7d24747e6A1BAA171944585bad4434f2D5; RPC=https://rpc.blast.io ;;
    mode)     SAFE=0xa4822d7d24747e6A1BAA171944585bad4434f2D5; RPC=https://mainnet.mode.network ;;
    linea)    SAFE=0xe4ff196Cd755566845D3dEBB1e2bD34123807eBc; RPC=https://rpc.linea.build ;;
    base)     SAFE=0x7a00657a45420044bc526B90Ad667aFfaee0A868; RPC=https://mainnet.base.org ;;
    bnb)      SAFE=0xD568c4D42147224a701A14468bEC9E9bccF571F5; RPC=https://bsc-dataseed1.binance.org ;;
    morph)    SAFE=0x770099bca35DE404C1843eaA36bA1C8986514a93; RPC=https://rpc.morphl2.io ;;
    op)       SAFE=0x764682c769CcB119349d92f1B63ee1c03d6AECFf; RPC=https://optimism-rpc.publicnode.com ;;
    scroll)   SAFE=0x3cD08f51D0EA86ac93368DE31822117cd70CECA3; RPC=https://rpc.scroll.io ;;
    zksync)   SAFE=0x8b9836176900A8EE62Dbe98066976D6CE829C53e; RPC=https://mainnet.era.zksync.io ;;
    swell)    SAFE=0x6D685276540271076e2c07eD6ed6Ce351549bA11; RPC=https://swell-mainnet.alt.technology ;;
    bera)     SAFE=0x2F8B067150123f53Da77eF3c1414FcE866E8A2D1; RPC=https://berachain-rpc.publicnode.com ;;
    unichain) SAFE=0xe54449CB6162FfcA23721434F4bB9f62702dC602; RPC=https://mainnet.unichain.org ;;
    avax)     SAFE=0x7a00657a45420044bc526B90Ad667aFfaee0A868; RPC=https://avalanche-c-chain-rpc.publicnode.com ;;
    sonic)    SAFE=0x7a00657a45420044bc526B90Ad667aFfaee0A868; RPC=https://rpc.soniclabs.com ;;
    hyperEVM) SAFE=0xf27128a5b064e8d97EDaa60D24bFa2FD1eeC26eB; RPC=https://rpc.hyperliquid.xyz/evm ;;
    *)
        echo "error: unknown chain '$CHAIN'" >&2
        echo "  chain ∈ { $SUPPORTED }" >&2
        exit 1
        ;;
esac

# Chains whose Safe Transaction Service is NOT operated by safe.global.
# For these, safe-cli can sign locally but `propose_tx` will fail; you must
# `execute_tx` directly, which only works if the Safe threshold is 1 or
# you can gather other co-signatures via a different channel.
NO_TX_SERVICE_REGEX="^(blast|mode|morph|swell|hyperEVM)$"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSON="$REPO_ROOT/output/${CHAIN}-OFT-OwnerDelegate-ToTimelock.json"

if [ ! -f "$JSON" ]; then
    echo "error: $JSON not found" >&2
    echo "  run: forge script scripts/Generate-OFT-Owner-Delegate-Transfer.s.sol --skip-simulation" >&2
    exit 1
fi

if ! command -v safe-cli >/dev/null 2>&1; then
    echo "error: safe-cli not installed" >&2
    echo "  install: pipx install 'safe-cli[ledger]'" >&2
    exit 1
fi

# Check if the [ledger] extra is actually importable from safe-cli's own
# environment. safe-cli depends on `ledgereth`, which on macOS needs the
# `hidapi` system lib — `pipx install 'safe-cli[ledger]'` can silently fail
# the wheel build and still report success.
# Locate safe-cli's venv python (pipx layout varies across versions/OSes:
# ~/.local/share/pipx/venvs/safe-cli or ~/.local/pipx/venvs/safe-cli).
_safecli_python=""
for _candidate in \
    "$HOME/.local/pipx/venvs/safe-cli/bin/python" \
    "$HOME/.local/share/pipx/venvs/safe-cli/bin/python"; do
    if [ -x "$_candidate" ]; then
        _safecli_python="$_candidate"
        break
    fi
done
if [ -n "$_safecli_python" ] && ! "$_safecli_python" -c 'import ledgereth' >/dev/null 2>&1; then
    cat <<'EOF' >&2
note: ledgereth is not importable from safe-cli's environment.
  fix on macOS:
    brew install hidapi libusb
    pipx uninstall safe-cli && pipx install 'safe-cli[ledger]'
  verify:
    pipx runpip safe-cli list | grep ledgereth
EOF
fi
unset _safecli_python _candidate

# safe-cli needs an API key for tx-service write operations (propose_tx).
# Reads still work without it, so warn rather than block.
if [ -z "${SAFE_TRANSACTION_SERVICE_API_KEY:-}" ] && ! [[ "$CHAIN" =~ $NO_TX_SERVICE_REGEX ]]; then
    cat <<'EOF' >&2
note: SAFE_TRANSACTION_SERVICE_API_KEY is not set.
  Reads will work, but `propose_tx` will fail until you export it.
  Get a key: https://developer.safe.global/
    export SAFE_TRANSACTION_SERVICE_API_KEY=<your_key>
EOF
fi

cat <<EOF
================================================================
  Chain:        $CHAIN
  Safe:         $SAFE
  RPC:          $RPC
  Bundle:       $JSON
  Ledger path:  $DERIVATION_PATH
================================================================

After the safe-cli prompt opens, paste:

  load_ledger_cli_owners --derivation-path "$DERIVATION_PATH"
  tx-builder $JSON

safe-cli will print a safeTxHash for the MultiSend. Then run:

  sign_tx     <safeTxHash>     # Ledger will prompt for confirmation
  propose_tx  <safeTxHash>     # submits to Safe Transaction Service
                               # other signers can co-sign via UI or CLI

EOF

if [[ "$CHAIN" =~ $NO_TX_SERVICE_REGEX ]]; then
    cat <<'EOF'
WARNING: This chain is NOT hosted by safe.global's Transaction Service.
  - `propose_tx` will fail. Use `execute_tx` for a one-shot send, but that
    only works if the Safe threshold == 1.
  - For higher thresholds, collect each signer's signature off-chain, then
    submit via the Safe contract's execTransaction directly.

EOF
fi

echo "Make sure the Ledger is unlocked and the Ethereum app is open."
echo "Launching safe-cli..."
echo

exec safe-cli "$SAFE" "$RPC"
