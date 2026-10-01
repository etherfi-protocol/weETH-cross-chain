import test from "node:test";
import assert from "node:assert/strict";
import {scanRoleHolders} from "./verify-deployment.mjs";

test("scanRoleHolders is exported for policy verification", () => {
  assert.equal(typeof scanRoleHolders, "function");
});
