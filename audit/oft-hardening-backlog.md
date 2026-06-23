# LayerZero OFT — further hardening & vuln-fix backlog

Additions to our onboarding **process** (skill + scripts) and **Ops workflow** (tooling,
monitoring, runbooks), beyond the controls already in place (4-of-4 DVN @ 45, library pinning,
enforced options, pairwise rate limits, peer allow-list, owner/delegate → timelock, Safe 4-of-7,
deprecation). Source playbook: protocol-ops `docs/oft-bridge-security-hardening.md` (PR #55).

Grounding (verified in this repo): we set **only ULN config type 2** — never Executor config
type 1; `01_OFTConfigure` sets DVN + rate limits + peers but **does not pin libraries or
executor** on the new chain's own side; there is **no drift monitor, cron, or supply
reconciliation**; `04_OFTVerification` checks the Safe *has* each timelock role but does not
enumerate members to prove **no extra holder** exists.

---

## P0 — continuous assurance (biggest Ops gap: everything today is point-in-time)

### 1. Mesh-wide drift monitor (scheduled)
Every control we set can later be changed by whoever holds delegate/owner, by a LZ default
rotation on an unpinned pathway, or by a malicious upgrade. A one-time post-deploy check can't
catch that.
- **Build:** make `verify-deployment.mjs` mesh-wide (`--all`) and machine-readable (JSON + non-zero
  exit on any ❌); run it on a **cron** (GitHub Actions or an off-chain monitor) every few hours
  against every live chain; page on ANY drift from expected — DVN set, confirmations, pinned
  send/receive libs, executor, peers, rate limits, OFT owner, **LZ delegate**, ProxyAdmin owner,
  **impl slot**, timelock roles, Safe threshold/owners.
- This converts the reviewer report we already have into a standing tripwire.

### 2. Cross-chain supply invariant monitor
The terminal failure of any bridge bug (bad peer, minting flaw, DVN compromise) shows up as weETH
minted on an L2 without backing locked on L1 — *before* anyone notices a config change.
- **Build:** reconcile `Σ(L2 OFT.totalSupply) == L1 adapter locked balance` (± in-flight tolerance)
  on a cron; alert on divergence. Defense-in-depth that catches an exploit in progress even when
  config still looks correct. Pairs with the rate limiter (which caps the per-window blast radius).

---

## P1 — close verifiable gaps (mostly tooling we can add now)

### 3. Pin the Executor config (ULN type 1)
We pin the DVN (type 2) and the library, but the **executor** stays on the LZ default on every
pathway. The executor governs *delivery* + `maxMessageSize` (not authenticity — DVNs cover that),
so the exposure is **liveness/censorship + oversized-message DoS**, and the endpoint owner can
rotate the default executor out from under us.
- **Add:** `setConfig(oapp, lib, [(eid, 1, ExecutorConfig(maxMessageSize, executor))])` pinned to
  the canonical per-chain executor, in the same delegate-gated batch as the library pin, with the
  same **live-fork gating** (only where still on default). Add to `peerInnerCalls` + `01_OFTConfigure`;
  verify via `getConfig(..., 1)`.
- **Decision first:** confirm with LZ whether pinning the executor is recommended for our profile
  (some teams deliberately leave it on default since it isn't authenticity-critical and pinning adds
  rotation maintenance). Document the call either way.

### 4. Role-holder enumeration / backdoor detection
An extra EOA holding PROPOSER/EXECUTOR/CANCELLER, or DEFAULT_ADMIN not renounced, is a governance
backdoor. `hasRole(role, Safe)==true` does not prove exclusivity.
- **Add:** `getRoleMemberCount` + `getRoleMember` enumeration → assert the holder set is **exactly**
  expected and `getRoleMemberCount(DEFAULT_ADMIN_ROLE)==0` (self-administered). Add to
  `verify-deployment.mjs` and the drift monitor.

### 5. Proposal-time canonical-address lint (refuse non-canonical calls)
A 3CP could `setPeer` to a wrong/attacker `bytes32`, `setConfig` a non-canonical DVN/lib/executor,
or `transferOwnership` to a non-timelock — and a reviewer reading raw calldata can miss it.
- **Add:** a linter in `make-3cp-folder.mjs` (and standalone) that parses every emitted call and
  asserts each address arg is in the registry/policy allow-list (peer OFT == registry, DVNs ==
  sorted registry set, libs == 302, executor == canonical, ownership target == timelock, MultiSend
  == known MSCO). **Fail the build otherwise** — turn "trust the reviewer" into "the tool won't emit
  a non-canonical call."

### 6. Onboarding unprotected-window invariant
Between deploy and reverse-wiring, inbound security to the new chain relies on the *new chain's*
receive config. `01_OFTConfigure` sets the 4-DVN receive config at deploy (good) but does **not**
pin the receive library or executor yet (follow-up ticket).
- **Add:** assert in onboarding that the new chain's receive DVN == 4-set (and, once #3/follow-up
  lands, libs/executor pinned) **before** any peer is wired to it; encode the ordering so the new
  chain is never a live target on default security.

### 7. Emergency runbook (pause / cancel / stuck-message)
- **Pause:** pauser = EOA for instant stop — verify the key is live, monitored, with a documented
  trigger and a periodic drill.
- **Cancel:** canceller = Safe can cancel a malicious scheduled timelock op within the 48h window —
  confirm 48h ≥ realistic detect+sign time; consider a faster guardian solely for `cancel`.
- **Stuck/poisoned inbound:** document the delegate-gated `endpoint.skip / nilify / burn / clear`
  procedures for a stuck or malicious message.

---

## P2 — document / decide (trade-offs, not clear bugs)

### 8. DVN liveness vs the 4-required/0-optional choice
4 required + 0 optional means a single DVN outage halts the pathway. That's an intentional
security>liveness call — document it, and if outages become real consider `required=3` + an
optional pool with a threshold for margin (changes the trust model; decide deliberately).

### 9. Receive-library timeout discipline
We pin receive libs with grace 0 (immediate). Any *future* receive-lib rotation must manage
`setReceiveLibraryTimeout` so there's no window where two libs both accept.

### 10. Enforced-options consistency
Standardize the `lzReceive` gas floor — older adapter-migration scripts use 1,000,000, the
onboarding flow uses 170k. Justify the floor per destination (under-gas → stuck messages; over →
waste) and confirm enforced options exist for every msgType the OFT actually uses (1 send, 2
send-and-call; 3/compose only if used).

---

## Two-OApp reminder
Every control above applies **separately** to the OFT mesh and the native-mint SyncPool — they are
distinct OApps; hardening one does not harden the other.
