import { test } from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

// JSON import-attributes are supported in Node >=20.10 / v26; fall back to require() for compatibility
const fixture = require("./fixtures/lz-metadata-robinhood.json");
const policy = require("../registry/policy.json");

import { resolveDvns } from "./resolve-chain.mjs";
import { buildEntry } from "./resolve-chain.mjs";

test("resolveDvns returns 4 policy DVNs sorted ascending", () => {
  const dvns = resolveDvns(fixture.robinhood, ["LayerZero Labs", "Nethermind", "Horizen", "Canary"]);
  assert.equal(dvns.length, 4);
  const sorted = [...dvns].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  assert.deepEqual(dvns, sorted);
});

test("resolveDvns throws on missing provider", () => {
  assert.throws(
    () => resolveDvns(fixture.robinhood, ["Nonexistent DVN"]),
    /missing DVN provider/
  );
});

test("buildEntry maps Robinhood v2 deployment", () => {
  const e = buildEntry(fixture.robinhood, policy);
  assert.strictEqual(e.L2_EID, 30416);
  assert.equal(e.L2_ENDPOINT.toLowerCase(), "0x6f475642a6e85809b1c36fa62763669b1b48dd5b");
  assert.equal(e.LZ_DVN.length, 4);
  assert.equal(e.WINDOW, 14400);
});
