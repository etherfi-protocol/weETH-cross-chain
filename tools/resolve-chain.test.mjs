import { test } from "node:test";
import assert from "node:assert";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

// JSON import-attributes are supported in Node >=20.10 / v26; fall back to require() for compatibility
const fixture = require("./fixtures/lz-metadata-robinhood.json");
const arcFixture = require("./fixtures/lz-metadata-arc.json");
const policy = require("../registry/policy.json");

import { resolveDvns } from "./resolve-chain.mjs";
import { buildEntry } from "./resolve-chain.mjs";

// Read providers from policy rather than restating them, so the test cannot drift from the
// policy it is meant to enforce.
test("resolveDvns returns 4 policy DVNs sorted ascending", () => {
  const dvns = resolveDvns(fixture.robinhood, policy.dvnProviders, policy.retiredDvnProviders);
  assert.equal(dvns.length, policy.requiredDVNCount);
  const sorted = [...dvns].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  assert.deepEqual(dvns, sorted);
});

test("resolveDvns throws on missing provider", () => {
  assert.throws(
    () => resolveDvns(fixture.robinhood, ["Nonexistent DVN"]),
    /missing DVN provider/
  );
});

// --- Canary -> P2P policy: a new chain must be onboarded onto P2P, never back onto Canary.

test("policy requires P2P and retires Canary", () => {
  assert.ok(policy.dvnProviders.includes("P2P"), "P2P must be a policy DVN provider");
  assert.ok(!policy.dvnProviders.includes("Canary"), "Canary must not be a policy DVN provider");
  assert.ok(policy.retiredDvnProviders.includes("Canary"), "Canary must be listed as retired");
});

test("resolveDvns refuses a retired provider even if callers ask for it", () => {
  assert.throws(
    () => resolveDvns(fixture.robinhood, ["Canary"], policy.retiredDvnProviders),
    /retired DVN provider requested/
  );
});

test("a resolved chain entry contains P2P and not that chain's Canary", () => {
  const dvns = resolveDvns(fixture.robinhood, policy.dvnProviders, policy.retiredDvnProviders);
  // robinhood's P2P and Canary addresses, as verified against live on-chain config
  assert.ok(dvns.includes("0x8ed0a851964604bb1b6b1a703f4c8234ee684d76"), "P2P missing");
  assert.ok(!dvns.includes(policy.retiredDvns.robinhood.toLowerCase()), "Canary still present");
});

// Arc carries two LayerZero Labs DVNs and enumerates the DEPRECATED one first, so a resolver
// that takes the first name match pins a DVN that no longer attests — 4-of-4 against a set that
// can never reach 4. Arc is the only mesh chain where metadata order and liveness disagree.
test("resolveDvns skips a deprecated DVN and takes the live address", () => {
  const dvns = resolveDvns(arcFixture.arc, policy.dvnProviders, policy.retiredDvnProviders);
  assert.ok(
    dvns.includes("0xa2447e5b58d357c49bf74b50b14421e6a100e525"),
    "live LayerZero Labs DVN missing"
  );
  assert.ok(
    !dvns.includes("0x282b3386571f7f794450d5789911a9804fa346b4"),
    "deprecated LayerZero Labs DVN was resolved"
  );
});

test("resolveDvns reports a provider that exists but is deprecated on the chain", () => {
  const onlyDeprecated = {
    chainKey: "arc",
    dvns: { "0x282b3386571f7f794450d5789911a9804fa346b4": { canonicalName: "LayerZero Labs", deprecated: true } },
  };
  assert.throws(
    () => resolveDvns(onlyDeprecated, ["LayerZero Labs"], policy.retiredDvnProviders),
    /deprecated on arc/
  );
});

test("arc resolves to the four operator-supplied DVNs, sorted and live", () => {
  const dvns = resolveDvns(arcFixture.arc, policy.dvnProviders, policy.retiredDvnProviders);
  assert.deepStrictEqual(dvns, [
    "0x69df29c29afcc8d1a0ee563a27827427f89ef698", // P2P
    "0x9e0e95ede70f680f74480b510ff9f45c70e3da80", // Nethermind
    "0xa2447e5b58d357c49bf74b50b14421e6a100e525", // LayerZero Labs
    "0xd36246c322ee102a2203bca9cafb84c179d306f6", // Horizen
  ]);
  assert.ok(!dvns.includes(policy.retiredDvns.arc.toLowerCase()), "arc Canary present");
});

test("retiredDvns is keyed per chain, not a flat list", () => {
  // DVN operators reuse one address across chains, so an address is only meaningful with its
  // chain: base's P2P is byte-identical to op's Canary. A flat denylist would reject base.
  assert.equal(typeof policy.retiredDvns, "object");
  assert.ok(!Array.isArray(policy.retiredDvns));
  assert.notEqual(policy.retiredDvns.base, policy.retiredDvns.op);
});

test("buildEntry maps Robinhood v2 deployment", () => {
  const e = buildEntry(fixture.robinhood, policy);
  assert.strictEqual(e.L2_EID, 30416);
  assert.equal(e.L2_ENDPOINT.toLowerCase(), "0x6f475642a6e85809b1c36fa62763669b1b48dd5b");
  assert.equal(e.LZ_DVN.length, 4);
  assert.equal(e.WINDOW, 14400);
});
