#!/usr/bin/env node
// Verify a GnosisSafeProxy 1.3.0 on a Blockscout explorer via the etherscan-
// compatible /api verifysourcecode endpoint. The Safe proxy is compiled with
// solc 0.7.6 (not this repo's 0.8.22), so `forge verify-contract` can't match
// it — this takes the verified standard-json from Sourcify and submits it once.
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


const constructorArgs = "000000000000000000000000" + SINGLETON.replace(/^0x/, "").toLowerCase();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The build settings are not guessable, and brute-forcing them costs a POST plus polls per
// attempt — enough to trip a rate limiter before reaching the right one. Sourcify already holds
// verified GnosisSafeProxy deployments, and the proxy bytecode is chain-independent, so take the
// standard-json from whichever chain has it and submit once.
const SOURCIFY_REFS = (args["sourcify-refs"] || "10,1,8453").split(",");
const PROXY_REF = args["proxy-ref"] || "0x7a00657a45420044bc526B90Ad667aFfaee0A868";

async function loadProxyFromSourcify() {
  let best = null;
  for (const cid of SOURCIFY_REFS) {
    const r = await fetch(`https://sourcify.dev/server/v2/contract/${cid}/${PROXY_REF}?fields=compilation,stdJsonInput`);
    if (!r.ok) continue;
    const j = await r.json();
    if (!j.stdJsonInput || !j.compilation) continue;
    const hit = {
      stdJson: JSON.stringify(j.stdJsonInput),
      contractname: j.compilation.fullyQualifiedName,
      compilerversion: `v${j.compilation.compilerVersion}`,
      match: j.match,
      chain: cid,
    };
    if (j.match === "exact_match") return hit;
    best = best || hit;
  }
  if (!best) throw new Error(`no verified GnosisSafeProxy in Sourcify for ${PROXY_REF} on ${SOURCIFY_REFS}`);
  return best;
}

(async () => {
  const src = await loadProxyFromSourcify();
  console.log(`Sourcify: ${src.match} on chain ${src.chain} — ${src.contractname} (${src.compilerversion})`);
  const form = new URLSearchParams({
    module: "contract", action: "verifysourcecode", apikey: APIKEY,
    contractaddress: SAFE, sourceCode: src.stdJson, codeformat: "solidity-standard-json-input",
    contractname: src.contractname, compilerversion: src.compilerversion,
    constructorArguements: constructorArgs, autodetectConstructorArguments: "false",
  });
  const sub = await fetch(EXPLORER + "?module=contract&action=verifysourcecode", {
    method: "POST", headers: {"content-type": "application/x-www-form-urlencoded"}, body: form,
  }).then((r) => r.json());

  if (/already verified/i.test(JSON.stringify(sub))) {
    console.log("already verified ✅"); return;
  }
  if (sub.status !== "1" || !sub.result) {
    console.error("submit rejected:", JSON.stringify(sub)); process.exit(1);
  }
  for (let i = 0; i < 20; i++) {
    await sleep(10000);
    const j = await fetch(`${EXPLORER}?module=contract&action=checkverifystatus&guid=${sub.result}&apikey=${APIKEY}`).then((r) => r.json());
    const res = `${j.result || j.message || ""}`;
    if (/pending|queue/i.test(res)) { console.log(`  …${res}`); continue; }
    console.log(`  ${res}`);
    if (/pass|verified/i.test(res)) {
      console.log("VERIFIED ✅", `${EXPLORER.replace(/\/api\/$/, "")}/address/${SAFE}`); return;
    }
    process.exit(1);
  }
  console.error("timed out waiting for verification status"); process.exit(1);
})();
