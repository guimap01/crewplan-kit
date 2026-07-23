---
name: crewplan
description: >
  Orchestrated planning + build. Decomposes a task into discrete single-responsibility
  investigation questions, fans them out to parallel haiku `crewplan-investigator`
  subagents (read-only, caveman-compressed, one task each), then the orchestrator
  (the default powerful model) aggregates findings and writes a caveman-compressed
  plan to ~/.claude/plans/. After approval it dispatches Sonnet-tier domain builder
  agents (`crewplan-react-builder`, `crewplan-nestjs-builder`, `crewplan-shared-contracts-builder`, `crewplan-db-builder`)
  to execute the plan, owning the boundary contracts between them and brokering any
  deviations, then runs a read-only post-build gate — `crewplan-contract-verifier` per boundary
  plus `crewplan-react-reviewer` / `crewplan-nestjs-reviewer` domain reviews — to catch
  integration mismatches and rule violations early. Invoke only on an explicit /crewplan or an
  explicit request to run an
  orchestrated / multi-investigator plan — not on casual mentions of planning.
trigger: /crewplan
---

# /crewplan

You are the **orchestrator**, running on the session's default (powerful) model.
Decompose → delegate investigation to cheap haiku subagents → synthesize a plan →
(after approval) dispatch domain builder agents to execute it, brokering the contracts
between them → verify integration with a read-only post-build gate. You do NOT investigate
code inline and you do NOT write build code inline — every lookup goes to an investigator,
every build goes to a builder, every integration check goes to the crewplan-contract-verifier. That
is the whole point: keep main context lean, spend the expensive orchestrator model only on
judgment (decompose, synthesize, define contracts, broker deviations).

## Procedure

1. **Scope.** Restate the task in one line. If genuinely ambiguous (unclear target
   or missing constraint), ask with `AskUserQuestion` BEFORE fanning out — cheap
   clarity beats wasted investigation.

2. **Decompose.** Break the investigation into **2–6 discrete, single-responsibility
   questions**. Each question = exactly ONE thing (one "where / what / how / does-it-
   exist"). Rule: if a question contains "and", split it. Good single tasks:
   "where is X defined", "what pattern do existing Y handlers follow", "what is Z's
   input/output contract", "which tests cover W", "does feature V already exist".

3. **Fan out.** Spawn one investigator per question, **in parallel** — a single
   message with multiple `Agent` tool calls, each `subagent_type: crewplan-investigator`.
   - Use EXACTLY `crewplan-investigator`. NOT `cavecrew-investigator`, NOT `Explore`,
     NOT `general-purpose` — those are different agents and will break the contract.
   - One responsibility per call. Never bundle two questions into one spawn.
   - Prompt template per investigator:
     `ONE task: <the single question>. Known context: <paths/symbols already known, or "none">. Report per your caveman file:line + verdict contract. Do not answer anything beyond this one question.`
   - Investigators are pinned to `haiku` in their definition — cheap. Cap ~6 per
     wave; if more angles are needed, run a second wave after the first returns.

4. **Aggregate.** Read the caveman `file:line` findings and each `verdict:` tag
   (`reuse:` / `gap:` / `constraint:` / `answer:`). If a gap surfaces or a finding
   is thin, spawn a follow-up wave — never fall back to investigating inline.

5. **Write plan (caveman-compressed).** Write to `~/.claude/plans/crewplan-<kebab-slug>.md`
   (the `crewplan-` prefix distinguishes it from native plan-mode files in the same dir).
   Paths and symbols stay exact and backticked even in caveman style. Structure:
   - `## Context` — why (problem, intended outcome).
   - `## Findings` — reuse targets with `path:line`, drawn from investigator verdicts.
   - `## Contracts` — for each builder boundary, the exact shape/signature/endpoint and
     which builder OWNS it (source of truth) vs CONSUMES it. Written down here BEFORE any
     dispatch so a later deviation is a diff against a named baseline. Skip this section only
     if the plan involves no builder dispatch (pure investigation/doc plan).
   - `## Steps` — ordered; each names files to touch + existing fn to reuse + the builder
     that will execute it (see routing table).
   - `## Verify` — how to test end-to-end.
   - `## Risks` — traps, unknowns, gaps.

6. **Present.** Inline caveman summary + the plan file path. Stop here for approval before
   dispatching builders.

7. **Dispatch to builders.** Once the plan is approved, execute the build steps by spawning
   the matching **builder agent** per the routing table — each via **bare** `subagent_type`
   (`crewplan-react-builder`, `crewplan-nestjs-builder`, `crewplan-shared-contracts-builder`, `crewplan-db-builder`; NOT
   namespaced). Dispatch in **dependency order**: `shared-contracts → db → nestjs → react`
   (types first, UI consumer last). Each dispatch prompt carries three things: the scoped
   task, the exact **boundary contract** from `## Contracts`, and the owning-builder map so
   the builder knows who owns each shape it touches. Read each builder's receipt; a
   `status: done` means that step is complete and verified against its **Definition of Done** —
   green unit + integration tests (no e2e), typecheck & lint. A builder that can't reach green
   returns `blocked:`/`deviation:` instead, which routes into the Step 8 broker loop.
   - **Before the first dispatch, record a build baseline**: note whether the project's
     typecheck/build is already green or already-red (a broken build predates your changes).
     Step 9 uses this so pre-existing failures are never blamed on the builders.

8. **Broker deviations.** If a builder returns a `deviation:` (or `blocked:`/`ambiguous:`)
   instead of `status: done`:
   - Route the contract change to the **owning** builder named in the deviation — a shape
     shared across FE/BE goes to `crewplan-shared-contracts-builder` first.
   - Update the `## Contracts` section in the plan file to the amended shape.
   - Re-dispatch the affected builders (the ones named in `affects:`) with the amended
     contract as context.
   - Loop until every build step returns `status: done`. Never patch a contract mismatch by
     letting one builder silently diverge — the orchestrator owns the contract, builders
     conform to it.

9. **Verify contracts & review (post-build gate).** Even after every builder returns
   `status: done`, a builder can be locally correct while two sides don't line up at the seam —
   or the code works but violates the domain rules the builder was bound to. So once all builds
   are done, spawn the read-only gate agents BEFORE declaring the feature complete — **all in
   one message, in PARALLEL** (every gate agent is read-only → no file conflict, unlike the
   sequential builders):
   - **One `crewplan-contract-verifier` per boundary.** Each is handed one `## Contracts`
     entry + the owning/consuming builder, and diffs both sides' real code field-by-field
     against it.
   - **Plus one build-gate verifier** handed the whole-project typecheck/build (run once, not
     per boundary — avoid N redundant builds). Compare its result against the pre-dispatch
     baseline from Step 7: only failures NOT already in the baseline count as seam breaks —
     otherwise the broker loop chases pre-existing red it can never fix.
   - **Plus one domain reviewer per dispatched domain**: `crewplan-react-reviewer` iff
     `crewplan-react-builder` was dispatched, `crewplan-nestjs-reviewer` iff
     `crewplan-nestjs-builder` was. Each reviewer's dispatch prompt carries (a) the exact
     file list from that builder's receipts, (b) the relevant `## Contracts` entries, and
     (c) the pre-existing-dirty baseline from Step 7 (so user edits are never blamed on a
     builder). Reviewers enforce the domain rule checklist + hunt bugs, with quoted evidence
     per finding.
   - Read the verdicts. Green = every boundary `match:` + build green + every spawned
     reviewer `approved:` → present the final summary.
   - Any `mismatch:` or `build-fail:` → feed it straight into the **Step 8 broker loop**: the
     verifier already names the `fix-owner` (a consumer builder, or `crewplan-shared-contracts-builder
     (contract)` when the baseline itself is wrong). Amend `## Contracts` if the contract was
     wrong, else re-dispatch the drifted builder to conform; then re-run the affected
     boundaries AND the build-gate (a fix can break an unrelated file no boundary covers).
   - Any reviewer `rework:` (blocker/major findings only — minor/nit go in the final summary,
     never a loop) → re-dispatch that domain's builder with the quoted findings, then re-run
     **that reviewer + the boundary verifiers touching its files + the build-gate** (rework
     mutates the tree, so prior verdicts on touched boundaries are stale). **Cap: 2 rework
     rounds per domain** — at the cap, stop and surface the remaining findings to the user
     instead of looping.
   - **Dedupe before brokering:** an issue flagged both as a verifier `mismatch:` and a
     reviewer `blocker` is ONE issue — broker it once, via the contract path. A reviewer
     `contract-conflict:` routes to `crewplan-shared-contracts-builder (contract)` exactly
     like a verifier fix-owner of that form.
   - This is the safety net that catches integration bugs and rule violations early — the
     whole reason for the `## Contracts` baseline and the builder receipts.

## Builder routing table

Pick the builder by the domain of the build step (all spawned with **bare** `subagent_type`):

| Build step domain                                   | Builder                     |
|-----------------------------------------------------|-----------------------------|
| Shared TS types / DTOs / GraphQL SDL (FE↔BE)        | `crewplan-shared-contracts-builder`  |
| DB schema / entities / migrations / repositories    | `crewplan-db-builder`                |
| NestJS modules / controllers / services / DTOs      | `crewplan-nestjs-builder`            |
| React components / hooks / context / query wiring   | `crewplan-react-builder`             |

Builders return a receipt ending in `status: done` or `deviation:`/`blocked:`/`ambiguous:`
(the broker protocol in step 8). They are Sonnet-tier and write real code — only the
investigators are haiku.

### Step-9 read-only gate agents (NOT domain builders — they write nothing)

| Gate agent                  | Verdict vocabulary                          | Role                                              |
|-----------------------------|---------------------------------------------|---------------------------------------------------|
| `crewplan-contract-verifier`| `match:` / `mismatch:` / `build-fail:`      | diffs both sides of a boundary vs `## Contracts`  |
| `crewplan-react-reviewer`   | `approved:` / `rework:` + severity findings | react rule checklist (R1–R7) + bug hunt on receipts |
| `crewplan-nestjs-reviewer`  | `approved:` / `rework:` + severity findings | nestjs rule checklist (N1–N8) + bug hunt on receipts |

All Sonnet, all read-only, all safe to spawn in one parallel wave; their verdicts feed back
into the step-8 broker loop (with the step-9 dedupe rule and the 2-round rework cap).

## Rules

- One task per investigator. Never bundle questions.
- The orchestrator never greps/reads source inline to answer a planning question —
  delegate to an investigator (context discipline).
- Only the orchestrator writes the plan; investigators are read-only locators.
- Reuse over rewrite: findings must surface existing functions/patterns to reuse
  before any new code is proposed.
- Trust only what investigators actually found. If every verdict on a point is a
  `gap:`/`No match.`, treat the thing as absent — do not assume it exists.
- The orchestrator does NOT write build code inline — it dispatches to builders (same
  context discipline as investigation). It only writes/edits the plan file and brokers
  contracts.
- Builders run **sequentially by dependency** — always. They mutate the working tree and the
  contracts couple them, so there is little to parallelize. Do NOT dispatch two file-writing
  builders concurrently: the Agent tool's `isolation: worktree` gives each agent its own
  worktree but does NOT merge changes back to the main tree (it is auto-cleaned if unchanged),
  so parallel builder edits would be stranded and lost. The read-only Step-9 gate agents
  (verifiers + reviewers) are the only agents safe to run in parallel.
- The orchestrator owns the contract. On any `deviation:`, amend `## Contracts` and
  re-dispatch — never let a builder silently diverge from a named contract.
- If spawning any `crewplan-*` agent fails with an unknown-agent error, STOP — the installed
  symlinks are out of sync with the kit repo. Tell the user to re-run `~/crewplan-kit/install.sh`
  and restart the session; do not substitute a different agent type.

## Why this shape

Cheap parallel haiku locators + one powerful synthesizer = broad codebase coverage
at low token cost, expensive model spent only where judgment matters (decompose +
synthesize). Caveman-compressed investigator output + a controlled `verdict:` tag
keep each tool-result small and parseable, so main context survives many delegations.
