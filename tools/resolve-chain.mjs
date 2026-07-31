import { readFileSync, writeFileSync, existsSync } from "node:fs";

/**
 * Resolve DVN addresses for a set of provider names from LayerZero chain metadata.
 * Returns addresses sorted ascending by numeric value (as BigInt).
 * Throws if any requested provider is not found in the metadata.
 *
 * @param {object} chain - The chain entry from LZ metadata (e.g. metadata.robinhood)
 * @param {string[]} providers - Ordered list of provider canonical names from policy
 * @returns {string[]} DVN addresses sorted ascending
 */
export function resolveDvns(chain, providers) {
  const dvns = chain.dvns || {};
  // DVN addresses are keys; metadata values hold canonicalName/name
  const addresses = providers.map((name) => {
    const pair = Object.entries(dvns).find(
      ([, v]) => (v.canonicalName || v.name || v.providerName) === name
    );
    if (!pair) throw new Error(`missing DVN provider: ${name}`);
    return pair[0].toLowerCase();
  });
  return addresses.sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
}

/**
 * Build a registry/chains.json entry from LZ metadata + policy.
 * Throws if no v2 deployment with endpointV2 is found.
 *
 * @param {object} chain - The chain entry from LZ metadata
 * @param {object} policy - Parsed registry/policy.json
 * @returns {object} Entry shaped as { NAME, CHAIN_ID, L2_EID, L2_ENDPOINT, SEND_302, RECEIVE_302, EXECUTOR, LZ_DVN, LIMIT, WINDOW }
 */
export function buildEntry(chain, policy) {
  const dep = (chain.deployments || []).find(
    (d) => d.version === 2 && d.endpointV2?.address
  );
  if (!dep) throw new Error("no LayerZero v2 endpoint deployment for chain");
  return {
    NAME: chain.chainDetails?.chainKey,
    CHAIN_ID: String(chain.chainDetails?.nativeChainId),
    L2_EID: Number(dep.eid),
    L2_ENDPOINT: dep.endpointV2.address,
    SEND_302: dep.sendUln302.address,
    RECEIVE_302: dep.receiveUln302.address,
    EXECUTOR: dep.executor.address,
    LZ_DVN: resolveDvns(chain, policy.dvnProviders),
    LIMIT: policy.rateLimit.limitWei,
    WINDOW: policy.rateLimit.windowSeconds,
  };
}

// CLI entrypoint — guarded so tests importing this module don't execute it
if (import.meta.url === `file://${process.argv[1]}`) {
  async function main() {
    const [chainKey, ...rest] = process.argv.slice(2);
    if (!chainKey) {
      throw new Error(
        "usage: resolve-chain.mjs <chainKey> [--rpc url] [--fixture path] [--date d]"
      );
    }
    const opt = Object.fromEntries(
      rest.reduce((a, x, i, arr) => {
        return x.startsWith("--") ? [...a, [x.slice(2), arr[i + 1]]] : a;
      }, [])
    );

    const policy = JSON.parse(
      readFileSync(new URL("../registry/policy.json", import.meta.url))
    );

    const all = opt.fixture
      ? JSON.parse(readFileSync(opt.fixture))
      : await (await fetch("https://metadata.layerzero-api.com/v1/metadata")).json();

    const chain = all[chainKey];
    if (!chain) throw new Error(`chain not in LayerZero metadata: ${chainKey}`);

    const date = opt.date || new Date().toISOString().slice(0, 10);
    writeFileSync(
      `registry/snapshots/${chainKey}-${date}.json`,
      JSON.stringify({ [chainKey]: chain }, null, 2)
    );

    const entry = buildEntry(chain, policy);
    if (opt.rpc) entry.RPC_URL = opt.rpc;

    const reg = existsSync("registry/chains.json")
      ? JSON.parse(readFileSync("registry/chains.json"))
      : {};
    reg[chainKey] = entry;
    writeFileSync("registry/chains.json", JSON.stringify(reg, null, 2));

    console.log(JSON.stringify(entry, null, 2));
  }

  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
