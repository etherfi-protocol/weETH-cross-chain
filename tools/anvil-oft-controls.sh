#!/usr/bin/env bash
# Rehearses the OFT controls upgrade on two anvil forks (Ethereum adapter and Base L2 token).
#
#   1. fork both chains and deploy the new implementations through CREATE3
#   2. build the timelock batches from live state and push them through the real timelocks, as the real
#      proposer and executor, waiting out the real delays
#   3. check that every read from before the upgrade is unchanged
#   4. send real cross-chain messages both ways, relaying each packet through the destination endpoint
#   5. use the new controls on the upgraded contracts: fee, lane pause, guardian pause, blacklist, recovery
#
# Needs anvil, cast, forge and jq. Run from anywhere:  tools/anvil-oft-controls.sh
# Forks Ethereum and Base from the public Tenderly gateways. Anvil asks the node for state at the fork block
# long after it was mined, so the RPC must serve historical state. Most public RPCs do not (publicnode returns
# 403). Set ETH_RPC or BASE_RPC to use another archive RPC.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ETH_RPC="${ETH_RPC:-https://mainnet.gateway.tenderly.co}"
BASE_RPC="${BASE_RPC:-https://base.gateway.tenderly.co}"
ETH="http://127.0.0.1:8545"
BASE="http://127.0.0.1:8546"
DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
USER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
RECIPIENT="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
GUARDIAN="0x90F79bf6EB2c4f870365E785982E1f101E93b906"
FEE_DEPOSIT="0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
ESCROW="0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"
ETH_EID=30101
BASE_EID=30184
FAILURES=0
PIDS=()

log() { printf '\n== %s\n' "$*"; }
ok() { printf '  PASS %s\n' "$*"; }
bad() {
  printf '  FAIL %s\n' "$*"
  FAILURES=$((FAILURES + 1))
}

cleanup() {
  if [ -n "${KEEP_ANVIL:-}" ]; then
    echo "KEEP_ANVIL set: leaving anvil running on 8545 and 8546 (pids ${PIDS[*]:-none})"
    return
  fi
  for pid in "${PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

reg() { jq -r ".$1.$2" registry/chains.json; }
# strips cast's "[1e18]" annotations from numeric output
num() { awk '{print $1}'; }
call() { cast call "$@" | head -n1 | num; }
# Sends a transaction and fails loudly unless the receipt says it succeeded.
send() {
  local out
  out="$(cast send --unlocked --gas-price 0 --priority-gas-price 0 --json "$@")" || {
    echo "cast send failed: $out" >&2
    return 1
  }
  if ! jq -e '.status == "0x1" or .status == 1' >/dev/null <<<"$out"; then
    echo "transaction reverted: $(jq -c '{transactionHash, status}' <<<"$out")" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

expect_eq() { # label actual expected
  if [ "$2" = "$3" ]; then ok "$1 = $3"; else bad "$1: got $2, expected $3"; fi
}

expect_revert() { # label rpc from to sig args...
  local label="$1" rpc="$2" from="$3" to="$4"
  shift 4
  if cast send --unlocked --gas-price 0 --priority-gas-price 0 --rpc-url "$rpc" --from "$from" "$to" "$@" >/dev/null 2>&1; then
    bad "$label: expected a revert"
  else
    ok "$label reverts"
  fi
}

start_anvil() { # name port rpc
  anvil --fork-url "$3" --port "$2" --auto-impersonate --base-fee 0 --gas-price 0 \
    --retries 8 --fork-retry-backoff 1500 >"/tmp/anvil-$1.log" 2>&1 &
  PIDS+=("$!")
  for _ in $(seq 1 120); do
    cast chain-id --rpc-url "http://127.0.0.1:$2" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "anvil $1 did not start, see /tmp/anvil-$1.log" >&2
  exit 1
}

fund() { cast rpc anvil_setBalance "$2" 0x56BC75E2D63100000 --rpc-url "$1" >/dev/null; }

deploy_impl() { # chain rpc
  TARGET_CHAIN="$1" forge script scripts/oft-controls/DeployImpl.s.sol --rpc-url "$2" --broadcast \
    --unlocked --sender "$DEPLOYER" 2>&1 | awk '/^  implementation 0x/ {print $2}' | tail -n1
}

# Reads that must not change across the upgrade. One line per read, "label=value".
snapshot() { # rpc oft peer_eid
  local rpc="$1" oft="$2" eid="$3" sel
  for sel in "owner()(address)" "paused()(bool)" "decimalConversionRate()(uint256)" "msgInspector()(address)" \
    "token()(address)" "name()(string)" "symbol()(string)" "totalSupply()(uint256)"; do
    printf '%s=%s\n' "$sel" "$(cast call "$oft" "$sel" --rpc-url "$rpc" 2>/dev/null | tr '\n' ' ' || echo reverted)"
  done
  for sel in "peers(uint32)(bytes32)" "outboundRateLimits(uint32)(uint256,uint256,uint256,uint256)" \
    "inboundRateLimits(uint32)(uint256,uint256,uint256,uint256)"; do
    printf '%s=%s\n' "$sel" "$(cast call "$oft" "$sel" "$eid" --rpc-url "$rpc" | tr '\n' ' ')"
  done
}

# Pushes one generated Safe bundle through its timelock: schedule, wait the real delay, execute.
run_bundle() { # rpc prefix
  local rpc="$1" prefix="$2" safe timelock data delay
  safe="$(jq -r '.safeAddress' "$prefix-schedule.json")"
  timelock="$(jq -r '.transactions[0].to' "$prefix-schedule.json")"
  delay="$(call "$timelock" "getMinDelay()(uint256)" --rpc-url "$rpc")"
  fund "$rpc" "$safe"

  data="$(jq -r '.transactions[0].data' "$prefix-schedule.json")"
  send --rpc-url "$rpc" --from "$safe" "$timelock" "$data" >/dev/null
  ok "scheduled by $safe on $timelock (delay ${delay}s)"
  cast rpc evm_increaseTime "$((delay + 1))" --rpc-url "$rpc" >/dev/null
  cast rpc evm_mine --rpc-url "$rpc" >/dev/null

  safe="$(jq -r '.safeAddress' "$prefix-execute.json")"
  fund "$rpc" "$safe"
  data="$(jq -r '.transactions[0].data' "$prefix-execute.json")"
  send --rpc-url "$rpc" --from "$safe" "$timelock" "$data" >/dev/null
  ok "executed by $safe"
}

# Sends from one chain and returns the encoded packet from the endpoint's PacketSent log. Tokens go to `sender`.
bridge_send() { # rpc oft endpoint sender dst_eid amount
  bridge_send_to "$1" "$2" "$3" "$4" "$4" "$5" "$6"
}

bridge_send_to() { # rpc oft endpoint sender recipient dst_eid amount
  local rpc="$1" oft="$2" endpoint="$3" sender="$4" recipient="$5" dst="$6" amount="$7" param fee topic receipt
  fund "$rpc" "$sender"
  param="($dst,$(cast pad "$recipient"),$amount,0,0x,0x,0x)"
  fee="$(cast call "$oft" "quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))" \
    "$param" false --rpc-url "$rpc" | tr -d '()' | cut -d, -f1 | num)"
  receipt="$(send --rpc-url "$rpc" --from "$sender" --value "$fee" "$oft" \
    "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)" \
    "$param" "($fee,0)" "$sender")" || return 1
  topic="$(cast keccak "PacketSent(bytes,bytes,address)")"
  echo "$receipt" | jq -r --arg t "$topic" --arg e "$(echo "$endpoint" | tr '[:upper:]' '[:lower:]')" \
    '.logs[] | select((.address|ascii_downcase)==$e and .topics[0]==$t) | .data' | head -n1
}

# Commits a packet on the destination chain the way a DVN would. Sets PACKET for deliver.
relay_verify() { # dst_rpc dst_endpoint packet_event_data
  local rpc="$1" endpoint="$2" data="$3" payload src_eid sender nonce receiver guid message hash lib delegate lazy
  payload="$(cast abi-decode "f()(bytes,bytes,address)" "$data" | head -n1)"
  payload="${payload#0x}"
  nonce="$((16#${payload:2:16}))"
  src_eid="$((16#${payload:18:8}))"
  sender="0x${payload:26:64}"
  receiver="0x${payload:122:40}"
  guid="0x${payload:162:64}"
  message="0x${payload:226}"
  hash="$(cast keccak "$(printf '%s%s' "$guid" "${message#0x}")")"
  lib="$(cast call "$endpoint" "getReceiveLibrary(address,uint32)(address,bool)" "$receiver" "$src_eid" --rpc-url "$rpc" | head -n1)"
  delegate="$(cast call "$endpoint" "delegates(address)(address)" "$receiver" --rpc-url "$rpc")"
  lazy="$(call "$endpoint" "lazyInboundNonce(address,uint32,bytes32)(uint64)" "$receiver" "$src_eid" "$sender" --rpc-url "$rpc")"
  fund "$rpc" "$lib"
  fund "$rpc" "$delegate"

  # The two forks are not taken at the same instant. Skip nonces that were in flight when the fork was taken.
  while [ "$((lazy + 1))" -lt "$nonce" ]; do
    send --rpc-url "$rpc" --from "$delegate" "$endpoint" "skip(address,uint32,bytes32,uint64)" \
      "$receiver" "$src_eid" "$sender" "$((lazy + 1))" >/dev/null
    lazy="$((lazy + 1))"
  done

  send --rpc-url "$rpc" --from "$lib" "$endpoint" "verify((uint32,bytes32,uint64),address,bytes32)" \
    "($src_eid,$sender,$nonce)" "$receiver" "$hash" >/dev/null
  PACKET="($src_eid,$sender,$nonce)|$receiver|$guid|$message"
}

# Verify and execute in one step.
relay() { # dst_rpc dst_endpoint packet_event_data
  relay_verify "$@"
  deliver "$1" "$2" "$PACKET"
}

deliver() { # rpc endpoint packet
  local rpc="$1" endpoint="$2" packet="$3" origin receiver guid message
  IFS='|' read -r origin receiver guid message <<<"$packet"
  send --rpc-url "$rpc" --from "$DEPLOYER" "$endpoint" \
    "lzReceive((uint32,bytes32,uint64),address,bytes32,bytes,bytes)" "$origin" "$receiver" "$guid" "$message" 0x >/dev/null
}

expect_fails() { # label command...
  local label="$1"
  shift
  if ("$@") >/dev/null 2>&1; then bad "$label: expected a failure"; else ok "$label fails"; fi
}

add() { python3 -I -c "print(int('$1') + int('$2'))"; }
sub_() { python3 -I -c "print(int('$1') - int('$2'))"; }

# A call from the contract's owner, which is the timelock. The timelock path itself ran in step 5.
as_owner() { # rpc oft sig args...
  local rpc="$1" oft="$2" owner
  shift 2
  owner="$(cast call "$oft" "owner()(address)" --rpc-url "$rpc")"
  fund "$rpc" "$owner"
  send --rpc-url "$rpc" --from "$owner" "$oft" "$@" >/dev/null
}

as() { # rpc from oft sig args...
  local rpc="$1" from="$2" oft="$3"
  shift 3
  fund "$rpc" "$from"
  send --rpc-url "$rpc" --from "$from" "$oft" "$@" >/dev/null
}

bal() { call "$2" "balanceOf(address)(uint256)" "$3" --rpc-url "$1"; }

features() {
  local policy_unpauser_eth eth_blacklister
  policy_unpauser_eth="$(jq -r '.chains.ethereum.unpauser' registry/oft-controls.json)"
  eth_blacklister="$(jq -r '.chains.ethereum.blacklister' registry/oft-controls.json)"
  local packet before after

  log "9a. fees: a per-lane fee on the adapter, a default fee on Base"
  as_owner "$ETH" "$ETH_OFT" "setFeeDeposit(address)" "$FEE_DEPOSIT"
  as_owner "$ETH" "$ETH_OFT" "setFeeBps(uint256,uint16,bool)" "$BASE_EID" 100 true
  as_owner "$BASE" "$BASE_OFT" "setFeeDeposit(address)" "$FEE_DEPOSIT"
  as_owner "$BASE" "$BASE_OFT" "setDefaultFeeBps(uint16)" 50
  expect_fails "a fee above the 1% cap" as_owner "$BASE" "$BASE_OFT" "setDefaultFeeBps(uint16)" 101
  before="$(bal "$BASE" "$BASE_OFT" "$USER")"
  packet="$(bridge_send "$ETH" "$ETH_OFT" "$ETH_ENDPOINT" "$USER" "$BASE_EID" "$(cast to-wei 2)")"
  relay "$BASE" "$BASE_ENDPOINT" "$packet"
  expect_eq "Base receives 2 weETH minus the 1% lane fee" "$(sub_ "$(bal "$BASE" "$BASE_OFT" "$USER")" "$before")" "$(cast to-wei 1.98)"
  expect_eq "adapter fee deposit holds the 1% fee" "$(bal "$ETH" "$WEETH" "$FEE_DEPOSIT")" "$(cast to-wei 0.02)"
  before="$(bal "$ETH" "$WEETH" "$USER")"
  packet="$(bridge_send "$BASE" "$BASE_OFT" "$BASE_ENDPOINT" "$USER" "$ETH_EID" "$(cast to-wei 1)")"
  relay "$ETH" "$ETH_ENDPOINT" "$packet"
  expect_eq "Ethereum receives 1 weETH minus the 0.5% fee" "$(sub_ "$(bal "$ETH" "$WEETH" "$USER")" "$before")" "$(cast to-wei 0.995)"
  expect_eq "Base fee deposit holds the 0.5% fee" "$(bal "$BASE" "$BASE_OFT" "$FEE_DEPOSIT")" "$(cast to-wei 0.005)"
  as_owner "$ETH" "$ETH_OFT" "setFeeBps(uint256,uint16,bool)" "$BASE_EID" 0 false
  as_owner "$BASE" "$BASE_OFT" "setDefaultFeeBps(uint16)" 0

  log "9b. lane pause: the paused lane stops and an undelivered message survives"
  packet="$(bridge_send "$ETH" "$ETH_OFT" "$ETH_ENDPOINT" "$USER" "$BASE_EID" "$(cast to-wei 1)")"
  relay_verify "$BASE" "$BASE_ENDPOINT" "$packet"
  as "$BASE" "$PAUSER_EOA" "$BASE_OFT" "setLanePaused(uint32,bool)" "$ETH_EID" true
  expect_eq "Base lane to Ethereum is paused" "$(call "$BASE_OFT" "isLanePaused(uint32)(bool)" "$ETH_EID" --rpc-url "$BASE")" true
  expect_fails "a send on the paused lane" bridge_send "$BASE" "$BASE_OFT" "$BASE_ENDPOINT" "$USER" "$ETH_EID" "$(cast to-wei 1)"
  expect_fails "delivering into the paused lane" deliver "$BASE" "$BASE_ENDPOINT" "$PACKET"
  expect_fails "the pauser unpausing a lane (needs UNPAUSER)" as "$BASE" "$PAUSER_EOA" "$BASE_OFT" "setLanePaused(uint32,bool)" "$ETH_EID" false
  before="$(bal "$BASE" "$BASE_OFT" "$USER")"
  as "$BASE" "$CANONICAL" "$BASE_OFT" "setLanePaused(uint32,bool)" "$ETH_EID" false
  deliver "$BASE" "$BASE_ENDPOINT" "$PACKET"
  expect_eq "the same message delivers after the unpause" "$(sub_ "$(bal "$BASE" "$BASE_OFT" "$USER")" "$before")" "$(cast to-wei 1)"

  log "9c. guardian pause: stops the bridge and ends by itself"
  as "$BASE" "$GUARDIAN" "$BASE_OFT" "pauseBridgeUntil()"
  expect_fails "a send during the guardian pause" bridge_send "$BASE" "$BASE_OFT" "$BASE_ENDPOINT" "$USER" "$ETH_EID" "$(cast to-wei 1)"
  expect_fails "the guardian using the indefinite pause" as "$BASE" "$GUARDIAN" "$BASE_OFT" "pauseBridge()"
  cast rpc evm_increaseTime 86401 --rpc-url "$BASE" >/dev/null
  cast rpc evm_mine --rpc-url "$BASE" >/dev/null
  packet="$(bridge_send "$BASE" "$BASE_OFT" "$BASE_ENDPOINT" "$USER" "$ETH_EID" "$(cast to-wei 1)")"
  relay "$ETH" "$ETH_ENDPOINT" "$packet"
  ok "the bridge works again with nobody unpausing it"
  expect_fails "the same guardian pausing again inside its cooldown" as "$BASE" "$GUARDIAN" "$BASE_OFT" "pauseBridgeUntil()"

  log "9d. blacklist: credit redirect, blocked transfers, blocked bridging, recovery"
  as "$BASE" "$USER" "$BASE_OFT" "transfer(address,uint256)" "$RECIPIENT" "$(cast to-wei 1)"
  expect_fails "enabling Blacklist mode with no escrow" as_owner "$BASE" "$BASE_OFT" "setAllowlistMode(uint8)" 1
  as_owner "$BASE" "$BASE_OFT" "setEscrow(address)" "$ESCROW"
  as_owner "$BASE" "$BASE_OFT" "setAllowlistMode(uint8)" 1
  as "$BASE" "$CANONICAL" "$BASE_OFT" "setBlacklisted((address,bool)[])" "[($RECIPIENT,true)]"
  expect_eq "blacklist count on Base" "$(call "$BASE_OFT" "blacklistedCount()(uint256)" --rpc-url "$BASE")" 1
  expect_fails "a blocked holder transferring" as "$BASE" "$RECIPIENT" "$BASE_OFT" "transfer(address,uint256)" "$USER" 1
  expect_fails "sending to a blocked holder" as "$BASE" "$USER" "$BASE_OFT" "transfer(address,uint256)" "$RECIPIENT" 1
  expect_fails "a blocked holder bridging out" bridge_send "$BASE" "$BASE_OFT" "$BASE_ENDPOINT" "$RECIPIENT" "$ETH_EID" "$(cast to-wei 0.5)"
  expect_fails "a stranger recovering funds" as "$BASE" "$USER" "$BASE_OFT" "recoverFunds(address,address,uint256)" "$RECIPIENT" "$USER" 1
  before="$(bal "$BASE" "$BASE_OFT" "$ESCROW")"
  as "$ETH" "$USER" "$WEETH" "approve(address,uint256)" "$ETH_OFT" "$(cast to-wei 10)"
  packet="$(bridge_send_to "$ETH" "$ETH_OFT" "$ETH_ENDPOINT" "$USER" "$RECIPIENT" "$BASE_EID" "$(cast to-wei 1)")"
  relay "$BASE" "$BASE_ENDPOINT" "$packet"
  expect_eq "bridged tokens for a blocked recipient land in escrow" "$(sub_ "$(bal "$BASE" "$BASE_OFT" "$ESCROW")" "$before")" "$(cast to-wei 1)"
  expect_eq "the blocked recipient did not receive them" "$(bal "$BASE" "$BASE_OFT" "$RECIPIENT")" "$(cast to-wei 1)"
  as_owner "$BASE" "$BASE_OFT" "recoverFunds(address,address,uint256)" "$RECIPIENT" "$ESCROW" "$(cast to-wei 1)"
  expect_eq "the owner recovered the blocked holder's tokens" "$(bal "$BASE" "$BASE_OFT" "$RECIPIENT")" 0
  expect_fails "recovering from a holder who is not blacklisted" as_owner "$BASE" "$BASE_OFT" "recoverFunds(address,address,uint256)" "$USER" "$ESCROW" 1

  log "9e. the adapter blocks and redirects the same way"
  as_owner "$ETH" "$ETH_OFT" "setEscrow(address)" "$ESCROW"
  as_owner "$ETH" "$ETH_OFT" "setAllowlistMode(uint8)" 1
  as "$ETH" "$eth_blacklister" "$ETH_OFT" "setBlacklisted((address,bool)[])" "[($RECIPIENT,true)]"
  before="$(bal "$ETH" "$WEETH" "$ESCROW")"
  packet="$(bridge_send_to "$BASE" "$BASE_OFT" "$BASE_ENDPOINT" "$USER" "$RECIPIENT" "$ETH_EID" "$(cast to-wei 0.5)")"
  relay "$ETH" "$ETH_ENDPOINT" "$packet"
  expect_eq "adapter redirects a blocked recipient to escrow" "$(sub_ "$(bal "$ETH" "$WEETH" "$ESCROW")" "$before")" "$(cast to-wei 0.5)"
  expect_eq "unpauser on the adapter is the operating Safe" "$(call "$ETH_OFT" "hasRole(bytes32,address)(bool)" "$(cast keccak UNPAUSER_ROLE)" "$policy_unpauser_eth" --rpc-url "$ETH")" true

  log "9f. supply: Base supply and the adapter's locked weETH moved by the same amount"
  after="$(sub_ "$(bal "$ETH" "$WEETH" "$ETH_OFT")" "$ETH_LOCKED_BEFORE")"
  expect_eq "locked weETH change equals Base supply change" "$after" "$(sub_ "$(call "$BASE_OFT" "totalSupply()(uint256)" --rpc-url "$BASE")" "$BASE_SUPPLY_BEFORE")"
}

main() {
  ETH_OFT="$(reg ethereum OFT)"
  BASE_OFT="$(reg base OFT)"
  ETH_ENDPOINT="$(reg ethereum L2_ENDPOINT)"
  BASE_ENDPOINT="$(reg base L2_ENDPOINT)"
  WEETH="0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee"

  log "1. fork Ethereum and Base"
  start_anvil eth 8545 "$ETH_RPC"
  start_anvil base 8546 "$BASE_RPC"
  fund "$ETH" "$DEPLOYER"
  fund "$BASE" "$DEPLOYER"
  ok "anvil forks up: Ethereum block $(cast block-number --rpc-url "$ETH"), Base block $(cast block-number --rpc-url "$BASE")"

  log "2. deploy the implementations through CREATE3"
  ETH_IMPL="$(deploy_impl ethereum "$ETH")"
  BASE_IMPL="$(deploy_impl base "$BASE")"
  [ -n "$ETH_IMPL" ] && [ -n "$BASE_IMPL" ] || {
    echo "deploy failed" >&2
    exit 1
  }
  ok "adapter implementation $ETH_IMPL, L2 implementation $BASE_IMPL"

  log "3. read the state before the upgrade"
  snapshot "$ETH" "$ETH_OFT" "$BASE_EID" >/tmp/oft-controls-eth-before.txt
  snapshot "$BASE" "$BASE_OFT" "$ETH_EID" >/tmp/oft-controls-base-before.txt
  BASE_SUPPLY_BEFORE="$(call "$BASE_OFT" "totalSupply()(uint256)" --rpc-url "$BASE")"

  log "4. build the timelock batches from live state"
  for pair in "ethereum $ETH $ETH_IMPL" "base $BASE $BASE_IMPL"; do
    read -r name rpc impl <<<"$pair"
    out="$(TARGET_CHAIN="$name" OFT_CONTROLS_IMPL="$impl" GUARDIAN="$GUARDIAN" \
      forge script scripts/oft-controls/UpgradeBatch.s.sol --rpc-url "$rpc" 2>&1)" || {
      echo "$out" >&2
      exit 1
    }
    # display only: a run with nothing to print is not an error
    rg 'GRANT|KEEP|SKIP|batch|delay|[0-9]+: ' <<<"$out" | cat
  done

  log "5. push the batches through the real timelocks"
  echo " Ethereum: upgrade (ProxyAdmin timelock), then roles (operating timelock)"
  run_bundle "$ETH" "output/oft-controls/ethereum-upgrade"
  run_bundle "$ETH" "output/oft-controls/ethereum-roles"
  echo " Base: upgrade and roles in one batch"
  run_bundle "$BASE" "output/oft-controls/base-upgrade"

  expect_eq "adapter implementation" "$(cast implementation "$ETH_OFT" --rpc-url "$ETH" | tr '[:upper:]' '[:lower:]')" "$(echo "$ETH_IMPL" | tr '[:upper:]' '[:lower:]')"
  expect_eq "Base implementation" "$(cast implementation "$BASE_OFT" --rpc-url "$BASE" | tr '[:upper:]' '[:lower:]')" "$(echo "$BASE_IMPL" | tr '[:upper:]' '[:lower:]')"

  log "6. every read from before the upgrade is unchanged"
  snapshot "$ETH" "$ETH_OFT" "$BASE_EID" >/tmp/oft-controls-eth-after.txt
  snapshot "$BASE" "$BASE_OFT" "$ETH_EID" >/tmp/oft-controls-base-after.txt
  if diff -q /tmp/oft-controls-eth-before.txt /tmp/oft-controls-eth-after.txt >/dev/null; then
    ok "adapter reads unchanged"
  else
    bad "adapter reads changed"
  fi
  if diff -q /tmp/oft-controls-base-before.txt /tmp/oft-controls-base-after.txt >/dev/null; then
    ok "Base reads unchanged"
  else
    bad "Base reads changed"
  fi

  log "7. roles after the upgrade"
  PAUSER_EOA="$(jq -r '.defaults.pauser' registry/oft-controls.json)"
  CANONICAL="$(jq -r '.defaults.unpauser' registry/oft-controls.json)"
  expect_eq "Base PAUSER (0x9AF1...)" "$(call "$BASE_OFT" "hasRole(address,uint256)(bool)" "$PAUSER_EOA" 2 --rpc-url "$BASE")" true
  expect_eq "Base UNPAUSER (canonical Safe)" "$(call "$BASE_OFT" "hasRole(address,uint256)(bool)" "$CANONICAL" 3 --rpc-url "$BASE")" true
  expect_eq "Base MINTER (native minting pool)" "$(call "$BASE_OFT" "hasRole(address,uint256)(bool)" "$(jq -r '.chains.base.minters[0]' registry/oft-controls.json)" 1 --rpc-url "$BASE")" true
  expect_eq "Base guardian can pause" "$(call "$BASE_OFT" "hasRole(address,uint256)(bool)" "$GUARDIAN" 6 --rpc-url "$BASE")" true
  expect_eq "Base pause duration" "$(call "$BASE_OFT" "pauseUntilDuration()(uint256)" --rpc-url "$BASE")" 86400
  expect_eq "adapter guardian can pause" "$(call "$ETH_OFT" "hasRole(bytes32,address)(bool)" "$(cast keccak PAUSER_UNTIL_ROLE)" "$GUARDIAN" --rpc-url "$ETH")" true

  log "8. real cross-chain messages, Ethereum to Base and back"
  fund "$ETH" "$USER"
  fund "$BASE" "$USER"
  send --rpc-url "$ETH" --from "$ETH_OFT" "$WEETH" "transfer(address,uint256)" "$USER" "$(cast to-wei 10)" >/dev/null
  send --rpc-url "$ETH" --from "$USER" "$WEETH" "approve(address,uint256)" "$ETH_OFT" "$(cast to-wei 10)" >/dev/null
  # the lockbox lent the test user 10 weETH. Measure supply changes from here.
  ETH_LOCKED_BEFORE="$(call "$WEETH" "balanceOf(address)(uint256)" "$ETH_OFT" --rpc-url "$ETH")"
  packet="$(bridge_send "$ETH" "$ETH_OFT" "$ETH_ENDPOINT" "$USER" "$BASE_EID" "$(cast to-wei 4)")"
  relay "$BASE" "$BASE_ENDPOINT" "$packet"
  expect_eq "Base balance after bridging 4 weETH in" "$(call "$BASE_OFT" "balanceOf(address)(uint256)" "$USER" --rpc-url "$BASE")" "$(cast to-wei 4)"
  packet="$(bridge_send "$BASE" "$BASE_OFT" "$BASE_ENDPOINT" "$USER" "$ETH_EID" "$(cast to-wei 1)")"
  relay "$ETH" "$ETH_ENDPOINT" "$packet"
  expect_eq "Base balance after bridging 1 weETH back" "$(call "$BASE_OFT" "balanceOf(address)(uint256)" "$USER" --rpc-url "$BASE")" "$(cast to-wei 3)"

  features

  log "result"
  if [ "$FAILURES" -eq 0 ]; then
    echo "  all checks passed"
  else
    echo "  $FAILURES checks failed"
    exit 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
