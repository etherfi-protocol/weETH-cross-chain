import test from "node:test";
import assert from "node:assert/strict";
import {applyRoleEvent} from "./verify-deployment.mjs";

test("role grants and revokes reconstruct the current holder set", () => {
  const role = "0x" + "11".repeat(32);
  const granted = "0x" + "22".repeat(32);
  const revoked = "0x" + "33".repeat(32);
  const alice = "0x" + "aa".repeat(20);
  const bob = "0x" + "bb".repeat(20);
  const holders = new Map([[role, new Set()]]);
  const topics = {[role]: "PROPOSER"};
  applyRoleEvent(holders, {topics:[granted, role, "0x"+"00".repeat(12)+alice.slice(2)]}, granted, revoked, topics);
  applyRoleEvent(holders, {topics:[granted, role, "0x"+"00".repeat(12)+bob.slice(2)]}, granted, revoked, topics);
  assert.deepEqual([...holders.get(role)], [alice, bob]);
  applyRoleEvent(holders, {topics:[revoked, role, "0x"+"00".repeat(12)+alice.slice(2)]}, granted, revoked, topics);
  assert.deepEqual([...holders.get(role)], [bob]);
});
