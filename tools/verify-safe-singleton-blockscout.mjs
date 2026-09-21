// Verify a Gnosis Safe singleton / master-copy (e.g. GnosisSafeL2 1.3.0) on a Blockscout explorer.
//
// The singleton is multi-file solc 0.7.6, so forge cannot match it. Sourcify already holds an
// exact match, so we pull its standard-json input and POST that to the etherscan-compatible
// /api verifysourcecode endpoint.
//
// The controller Safe is a thin proxy that delegatecalls this singleton, and Blockscout only
// surfaces approveHash/execTransaction once the singleton itself is verified.
//
// Usage:
//   node tools/verify-safe-singleton-blockscout.mjs \
//     --singleton 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA \
//     --explorer https://<host>/api/ [--sourcify-chains 1,8453,10] [--apikey <key>]

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) args[argv[i].replace(/^--/, "")] = argv[i + 1];

const ADDR = args.singleton;
const EXPLORER = (args.explorer || "").replace(/\/?$/, "/").replace(/api\/$/, "api");
const APIKEY = args.apikey || process.env.EXPLORER_API_KEY || process.env.ROBINHOOD_API_KEY || "";
const SOURCIFY_CHAINS = (args["sourcify-chains"] || "1,8453,10").split(",");

if (!ADDR || !EXPLORER) {
  console.error("usage: --singleton <addr> --explorer <blockscout /api url> [--sourcify-chains 1,8453]");
  process.exit(1);
}

// Sourcify v1 (/files, /check-by-addresses) was retired and now 404s. v2 returns the standard-json
// input directly, so there is nothing left to reconstruct from metadata.
async function loadFromSourcify() {
  for (const cid of SOURCIFY_CHAINS) {
    const url = `https://sourcify.dev/server/v2/contract/${cid}/${ADDR}?fields=compilation,stdJsonInput`;
    const r = await fetch(url);
    if (!r.ok) continue;
    const j = await r.json();
    if (!j.stdJsonInput || !j.compilation) continue;
    console.log(`Sourcify: ${j.match} on chain ${cid} (${Object.keys(j.stdJsonInput.sources).length} sources)`);
    return {
      stdJson: JSON.stringify(j.stdJsonInput),
      contractname: j.compilation.fullyQualifiedName,
      compilerversion: `v${j.compilation.compilerVersion}`,
    };
  }
  throw new Error(`singleton ${ADDR} not found in Sourcify for chains ${SOURCIFY_CHAINS}`);
}

async function alreadyVerified() {
  const r = await fetch(`${EXPLORER}?module=contract&action=getsourcecode&address=${ADDR}`);
  if (!r.ok) throw new Error(`explorer getsourcecode failed: HTTP ${r.status}`);
  const j = await r.json();
  const res = Array.isArray(j.result) ? j.result[0] : j.result;
  return res && res.SourceCode && res.SourceCode.length > 0;
}

async function submit({ stdJson, contractname, compilerversion }) {
  const body = new URLSearchParams({
    module: "contract",
    action: "verifysourcecode",
    apikey: APIKEY,
    codeformat: "solidity-standard-json-input",
    contractaddress: ADDR,
    contractname,
    compilerversion,
    sourceCode: stdJson,
    constructorArguements: "",
    autodetectConstructorArguments: "false",
  });
  const r = await fetch(`${EXPLORER}?module=contract&action=verifysourcecode`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  return r.json();
}

async function poll(guid) {
  for (let i = 0; i < 30; i++) {
    await new Promise((res) => setTimeout(res, 4000));
    const j = await fetch(`${EXPLORER}?module=contract&action=checkverifystatus&guid=${guid}&apikey=${APIKEY}`).then((r) => r.json());
    const msg = `${j.result || j.message}`;
    if (/pending/i.test(msg)) { console.log(`  …${msg}`); continue; }
    return msg;
  }
  return "timed out";
}

(async () => {
  if (await alreadyVerified()) { console.log(`${ADDR} already verified on this explorer.`); return; }
  const src = await loadFromSourcify();
  console.log(`Submitting ${src.contractname} (${src.compilerversion}) …`);
  const sub = await submit(src);
  if (!sub.result || sub.status !== "1") {
    if (/already verified/i.test(`${sub.result}`)) { console.log("already verified."); return; }
    console.error("submit failed:", JSON.stringify(sub));
    process.exit(1);
  }
  console.log("guid:", sub.result);
  console.log("result:", await poll(sub.result));
})();
