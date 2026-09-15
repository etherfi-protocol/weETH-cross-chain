// Verify a contract on a Blockscout explorer with the fewest possible API calls.
//
// `forge verify-contract` calls getsourcecode and getabi before it submits, so a rate-limited
// explorer rejects the run before any payload is sent. forge can still build the standard-json
// offline (--show-standard-json-input), so this builds the payload locally and makes one POST.
//
// Usage:
//   node tools/verify-direct.mjs --address 0x.. --contract EtherfiOFTUpgradeable \
//     --explorer http://127.0.0.1:8555/api/ [--constructor-args 0x..] [--compiler 0.8.22]
//     [--poll-ms 10000] [--apikey <key>] [--check-first]

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) args[argv[i].replace(/^--/, "")] = argv[i + 1];

const ADDR = args.address;
const CONTRACT = args.contract;
const EXPLORER = (args.explorer || "").replace(/\/?$/, "/").replace(/api\/$/, "api");
const CTOR = (args["constructor-args"] || "").replace(/^0x/, "");
const COMPILER = args.compiler || "0.8.22";
const POLL_MS = Number(args["poll-ms"] || 10000);
const APIKEY = args.apikey || process.env.EXPLORER_API_KEY || "";
const CHECK_FIRST = "check-first" in args;

if (!ADDR || !CONTRACT || !EXPLORER) {
  console.error("usage: --address <addr> --contract <Name> --explorer <blockscout /api url>");
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Blockscout wants the long solc version. The artifact carries it; `forge build --json` does not
// once the build is warm, and the short form is rejected.
function compilerVersion() {
  const path = `out/${CONTRACT}.sol/${CONTRACT}.json`;
  const v = JSON.parse(readFileSync(path, "utf8"))?.metadata?.compiler?.version;
  if (!v) throw new Error(`no compiler version in ${path} — run forge build`);
  return `v${v}`;
}

function standardJson() {
  return execFileSync("forge", ["verify-contract", ADDR, CONTRACT, "--show-standard-json-input"], {
    encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 64 * 1024 * 1024,
  }).trim();
}

/** Fully-qualified name Blockscout expects: <source path>:<ContractName>. */
function fullyQualified(stdJson) {
  const j = JSON.parse(stdJson);
  const path = Object.keys(j.sources).find((p) => p.endsWith(`/${CONTRACT}.sol`) || p.endsWith(`${CONTRACT}.sol`));
  return path ? `${path}:${CONTRACT}` : CONTRACT;
}

async function isVerified() {
  const r = await fetch(`${EXPLORER}?module=contract&action=getsourcecode&address=${ADDR}`);
  if (!r.ok) return false;
  const j = await r.json().catch(() => ({}));
  const res = Array.isArray(j.result) ? j.result[0] : j.result;
  return Boolean(res && res.SourceCode && res.SourceCode.length > 0);
}

async function main() {
  if (CHECK_FIRST && (await isVerified())) {
    console.log(`${CONTRACT} @ ${ADDR}: already verified`);
    return;
  }
  const stdJson = standardJson();
  const name = fullyQualified(stdJson);
  const version = compilerVersion();
  console.log(`submitting ${name} (${version}) …`);

  const body = new URLSearchParams({
    module: "contract",
    action: "verifysourcecode",
    apikey: APIKEY,
    codeformat: "solidity-standard-json-input",
    contractaddress: ADDR,
    contractname: name,
    compilerversion: version,
    sourceCode: stdJson,
    constructorArguements: CTOR,
    autodetectConstructorArguments: "false",
  });
  const r = await fetch(`${EXPLORER}?module=contract&action=verifysourcecode`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const text = await r.text();
  let sub;
  try { sub = JSON.parse(text); } catch { throw new Error(`explorer returned non-JSON (HTTP ${r.status}): ${text.slice(0, 200)}`); }

  if (/already verified/i.test(`${sub.result}`)) { console.log("already verified"); return; }
  if (sub.status !== "1" || !sub.result) throw new Error(`submit rejected: ${JSON.stringify(sub)}`);

  console.log(`guid ${sub.result} — polling every ${POLL_MS}ms`);
  for (let i = 0; i < 30; i++) {
    await sleep(POLL_MS);
    const p = await fetch(`${EXPLORER}?module=contract&action=checkverifystatus&guid=${sub.result}&apikey=${APIKEY}`);
    const j = await p.json().catch(() => ({}));
    const msg = `${j.result || j.message || ""}`;
    if (/pending|queue/i.test(msg)) { console.log(`  …${msg}`); continue; }
    console.log(`  ${msg}`);
    if (/fail|error|unable/i.test(msg)) process.exit(1);
    return;
  }
  throw new Error("timed out waiting for verification status");
}

main().catch((e) => { console.error(`error: ${e.message}`); process.exit(1); });
