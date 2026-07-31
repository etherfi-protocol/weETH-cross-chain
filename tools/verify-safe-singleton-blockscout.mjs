// Verify a Gnosis Safe singleton / master-copy (e.g. GnosisSafeL2 1.3.0) on a
// Blockscout explorer. The singleton is multi-file solc 0.7.6, so we can't use a
// single-file submit; instead we rebuild the exact solidity-standard-json-input
// from Sourcify (perfect-match source set + metadata settings) and POST it to the
// etherscan-compatible /api verifysourcecode endpoint.
//
// Why: the controller Safe is a thin GnosisSafeProxy that delegatecalls the
// singleton. Blockscout only surfaces approveHash/execTransaction once the
// singleton is verified — verifying the proxy alone is not enough.
//
// Usage:
//   ROBINHOOD_API_KEY=… node tools/verify-safe-singleton-blockscout.mjs \
//     --singleton 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA \
//     --explorer https://8crv4vmq6tiu1yqr.blockscout.com/api/ \
//     [--sourcify-chains 1,8453,10]

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) args[argv[i].replace(/^--/, "")] = argv[i + 1];

const ADDR = args.singleton;
const EXPLORER = (args.explorer || "").replace(/\/?$/, "/").replace(/api\/$/, "api"); // tolerate trailing slash
const APIKEY = process.env.ROBINHOOD_API_KEY || args.apikey || "";
const SOURCIFY_CHAINS = (args["sourcify-chains"] || "1,8453,10").split(",");

if (!ADDR || !EXPLORER) {
  console.error("usage: --singleton <addr> --explorer <blockscout /api url> [--sourcify-chains 1,8453]");
  process.exit(1);
}

async function loadFromSourcify() {
  for (const cid of SOURCIFY_CHAINS) {
    const r = await fetch(`https://sourcify.dev/server/files/${cid}/${ADDR}`);
    if (!r.ok) continue;
    const files = await r.json();
    const metaFile = files.find((f) => f.name === "metadata.json");
    if (!metaFile) continue;
    const meta = JSON.parse(metaFile.content);
    console.log(`Sourcify: matched on chain ${cid} (${Object.keys(meta.sources).length} sources)`);
    return { files, meta };
  }
  throw new Error(`singleton ${ADDR} not found in Sourcify for chains ${SOURCIFY_CHAINS}`);
}

function buildStandardJson(files, meta) {
  // map each metadata source path -> file content (file.path ends with "/sources/<path>")
  const sources = {};
  for (const path of Object.keys(meta.sources)) {
    const f = files.find((x) => x.path && x.path.endsWith(`/sources/${path}`));
    if (!f) throw new Error(`missing source content for ${path}`);
    sources[path] = { content: f.content };
  }
  const s = meta.settings;
  const settings = {
    optimizer: s.optimizer || { enabled: false, runs: 200 },
    evmVersion: s.evmVersion,
    remappings: s.remappings || [],
    libraries: s.libraries || {},
    metadata: s.metadata || { bytecodeHash: "ipfs" },
    outputSelection: { "*": { "*": ["abi", "evm.bytecode", "evm.deployedBytecode", "metadata"], "": ["ast"] } },
  };
  const target = Object.keys(s.compilationTarget)[0];
  const name = s.compilationTarget[target];
  return {
    stdJson: JSON.stringify({ language: "Solidity", sources, settings }),
    contractname: `${target}:${name}`,
    compilerversion: `v${meta.compiler.version}`,
  };
}

async function alreadyVerified() {
  const r = await fetch(`${EXPLORER}?module=contract&action=getsourcecode&address=${ADDR}`);
  const j = await r.json();
  const res = Array.isArray(j.result) ? j.result[0] : j.result;
  return res && res.SourceCode && res.SourceCode.length > 0;
}

async function submit(stdJson, contractname, compilerversion) {
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
  const { files, meta } = await loadFromSourcify();
  const { stdJson, contractname, compilerversion } = buildStandardJson(files, meta);
  console.log(`Submitting ${contractname} (${compilerversion}) …`);
  const sub = await submit(stdJson, contractname, compilerversion);
  if (!sub.result || sub.status !== "1") {
    if (/already verified/i.test(`${sub.result}`)) { console.log("already verified."); return; }
    console.error("submit failed:", JSON.stringify(sub));
    process.exit(1);
  }
  console.log("guid:", sub.result);
  console.log("result:", await poll(sub.result));
})();
