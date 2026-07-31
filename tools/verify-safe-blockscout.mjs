#!/usr/bin/env node
// Verify a GnosisSafeProxy 1.3.0 on a Blockscout explorer via the etherscan-
// compatible /api verifysourcecode endpoint. The Safe proxy is compiled with
// solc 0.7.6 (not this repo's 0.8.22), so `forge verify-contract` can't match
// it — this posts the canonical source + 0.7.6 settings directly.
//
// Usage:
//   node tools/verify-safe-blockscout.mjs --safe <addr> --singleton <addr> \
//     --explorer https://<host>/api/ [--apikey <key>|$EXPLORER_API_KEY]
//
// Robinhood example (key from $ROBINHOOD_API_KEY):
//   node tools/verify-safe-blockscout.mjs \
//     --safe 0x7a00657a45420044bc526B90Ad667aFfaee0A868 \
//     --singleton 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA \
//     --explorer https://8crv4vmq6tiu1yqr.blockscout.com/api/ --apikey "$ROBINHOOD_API_KEY"

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) args[argv[i].replace(/^--/, "")] = argv[i + 1];

const SAFE = args.safe;
const SINGLETON = args.singleton;
const EXPLORER = (args.explorer || "").replace(/\/?$/, "/");
const APIKEY = args.apikey || process.env.EXPLORER_API_KEY || process.env.ROBINHOOD_API_KEY || "";
if (!SAFE || !SINGLETON || !EXPLORER) {
  console.error("usage: --safe <addr> --singleton <addr> --explorer <url> [--apikey <key>]");
  process.exit(1);
}

// Canonical GnosisSafeProxy 1.3.0 (safe-contracts), license LGPL-3.0-only.
const SOURCE = `// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

/// @title IProxy - Helper interface to access masterCopy of the Proxy on-chain
/// @author Richard Meissner - <richard@gnosis.io>
interface IProxy {
    function masterCopy() external view returns (address);
}

/// @title GnosisSafeProxy - Generic proxy contract allows to execute all transactions applying the code of a master contract.
/// @author Stefan George - <stefan@gnosis.io>
/// @author Richard Meissner - <richard@gnosis.io>
contract GnosisSafeProxy {
    // singleton always needs to be first declared variable, to ensure that it is at the same location in the contracts to which calls are delegated.
    // To reduce deployment costs this variable is internal and needs to be retrieved via \`getStorageAt\`
    address internal singleton;

    /// @dev Constructor function sets address of singleton contract.
    /// @param _singleton Singleton address.
    constructor(address _singleton) {
        require(_singleton != address(0), "Invalid singleton address provided");
        singleton = _singleton;
    }

    /// @dev Fallback function forwards all transactions and returns all received return data.
    fallback() external payable {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let _singleton := and(sload(0), 0xffffffffffffffffffffffffffffffffffffffff)
            // 0xa619486e == keccak("masterCopy()"). The value is right padded to 32-bytes with 0s
            if eq(calldataload(0), 0xa619486e00000000000000000000000000000000000000000000000000000000) {
                mstore(0, _singleton)
                return(0, 0x20)
            }
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), _singleton, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}
`;

const constructorArgs = "000000000000000000000000" + SINGLETON.replace(/^0x/, "").toLowerCase();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// GnosisSafeProxy 1.3.0 is solc 0.7.6 (confirmed by the on-chain metadata
// `64736f6c6343000706`); the exact optimizer/evm vary by build, so try the
// common Safe configs until Blockscout matches (full or partial).
const CONFIGS = [
  {optimizationUsed: "1", runs: "200", evmversion: "istanbul"},
  {optimizationUsed: "0", runs: "200", evmversion: "istanbul"},
  {optimizationUsed: "1", runs: "10000000", evmversion: "istanbul"},
  {optimizationUsed: "1", runs: "200", evmversion: "default"},
  {optimizationUsed: "0", runs: "200", evmversion: "default"},
  {optimizationUsed: "1", runs: "1000000", evmversion: "istanbul"},
];

const post = (body) =>
  fetch(EXPLORER + "?module=contract&action=verifysourcecode", {
    method: "POST",
    headers: {"content-type": "application/x-www-form-urlencoded"},
    body,
  }).then((r) => r.json());

async function tryConfig(cfg) {
  const form = new URLSearchParams({
    module: "contract", action: "verifysourcecode", apikey: APIKEY,
    contractaddress: SAFE, sourceCode: SOURCE, codeformat: "solidity-single-file",
    contractname: "GnosisSafeProxy", compilerversion: "v0.7.6+commit.7338295f",
    constructorArguements: constructorArgs, licenseType: "3", ...cfg,
  });
  const sub = await post(form);
  if (/already verified/i.test(JSON.stringify(sub))) return "already";
  if (sub.status !== "1" || !sub.result) return "submit-failed";
  for (let i = 0; i < 4; i++) {
    await sleep(5000);
    const j = await fetch(`${EXPLORER}?module=contract&action=checkverifystatus&guid=${sub.result}&apikey=${APIKEY}`).then((r) => r.json());
    const res = j.result || "";
    if (/pass|verified/i.test(res)) return "pass";
    if (/fail|error/i.test(res) && !/pending|queue/i.test(res)) return "fail";
  }
  return "timeout";
}

(async () => {
  for (const cfg of CONFIGS) {
    const label = `optimizer=${cfg.optimizationUsed} runs=${cfg.runs} evm=${cfg.evmversion}`;
    const r = await tryConfig(cfg);
    console.log(`${label} -> ${r}`);
    if (r === "pass" || r === "already") {
      console.log("VERIFIED ✅", `${EXPLORER.replace(/\/api\/$/, "")}/address/${SAFE}`);
      return;
    }
  }
  console.error("No config matched. The proxy may use non-standard build settings — fetch the verified source/metadata from a chain where this Safe is already verified.");
  process.exit(1);
})();
