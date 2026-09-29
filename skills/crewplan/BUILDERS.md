# crewplan builders + contract verification — reference

> Lazy reference for the crewplan build/verify layer. NOT auto-loaded into any session —
> read it when working on crewplan, the builder agents, or the crewplan-contract-verifier. Kept here
> (next to `SKILL.md`) rather than in any project's memory index on purpose: this tooling is
> global and unrelated to any single repo, so it must never clutter per-project sessions.

## What this is

`/crewplan` used to plan and stop. It now also **executes** the plan by dispatching
specialist **builder agents**, **owns the contracts** between them, and runs a read-only
**post-build verification gate** to catch integration bugs early. Full operational procedure
lives in `SKILL.md` (steps 7 = dispatch, 8 = broker deviations, 9 = verify). This file is the
roster + rationale.

## Agent roster (all in `~/.claude/agents/`, bare `subagent_type`)

| Agent | Model · effort | Role |
|---|---|---|
| `crewplan-investigator` | haiku · — | read-only locator, one question per spawn (planning phase) |
| `crewplan-shared-contracts-builder` | sonnet · medium | **contract authority** — shared TS types/DTO/GraphQL, no logic |
| `crewplan-db-builder` | sonnet · medium | ORM schema/entities/migrations/repositories |
| `crewplan-nestjs-builder` | sonnet · medium | NestJS modules/controllers/services/DTOs |
| `crewplan-react-builder` | sonnet · medium | React components/hooks/context/query wiring |
| `crewplan-contract-verifier` | sonnet · medium | **read-only** post-build gate — diffs both sides vs contract + runs typecheck/build |
| `crewplan-react-reviewer` | sonnet · high | **read-only** step-9 domain review — react rule checklist (R1–R7) + bug hunt on the react builder's receipts |
| `crewplan-nestjs-reviewer` | sonnet · high | **read-only** step-9 domain review — nestjs rule checklist (N1–N8) + bug hunt on the nestjs builder's receipts |

Investigators are cheap/haiku; everything that writes or judges real code is Sonnet. `sonnet`
and `haiku` are aliases that follow each new release, so there is no version to bump. `effort`
is set explicitly because each Sonnet release recalibrates what a level means: builders and the
verifier start at `medium` (the documented starting point for agentic coding), reviewers at
`high` (bug-hunting is the judgment-heavy step). Re-check these when a new Sonnet ships. The
haiku investigator sets no `effort` — Haiku 4.5 doesn't take one.

The builders' Definition of Done rejects a check that never exercised the change (syntax-only,
or a command that failed to start). Current Sonnet models can report work done without a real
check at lower effort; that clause, plus the orchestrator's quoted-`verified:` receipt rule, is
the guard.

## The contract protocol (the glue)

- The orchestrator writes a `## Contracts` section in the plan BEFORE dispatch: each boundary's
  exact shape/endpoint + which builder OWNS it vs CONSUMES it. This is the diff baseline.
- Dispatch order = **dependency order**: `shared-contracts → db → nestjs → react` (types first,
  UI last). Builders always run **sequentially**: they mutate the tree and contracts couple them,
  and `isolation: worktree` does not merge an agent's changes back, so parallel builder edits
  would be lost.
- A builder that can't meet its contract does NOT improvise — it halts and returns
  `deviation: <what> | reason | need + owning-builder | affects: <consumers>`. Also
  `blocked:` / `ambiguous:`.
- **Broker loop (step 8):** on any `deviation:`, route the change to the owning builder
  (cross-FE/BE shapes → `crewplan-shared-contracts-builder` first), amend `## Contracts`, re-dispatch the
  `affects:` builders, loop until all `status: done` — **capped at 3 broker rounds per
  boundary** (counted in the plan's `## Progress`); at the cap, surface the remaining
  mismatch to the user instead of looping.

## Post-build verification (step 9)

- After every builder is `status: done`, spawn `crewplan-contract-verifier` — **one per boundary in
  parallel** (read-only, no conflict) + **one build-gate** verifier that runs the project
  typecheck/build once.
- Verifier emits `match:` / `mismatch:` / `build-fail:` with a named `fix-owner`
  (`crewplan-shared-contracts-builder (contract)` when the baseline itself is wrong).
- Any non-match feeds back into the step-8 broker loop, then re-verify the affected boundaries.
  Loop until `verified: all boundaries match, build green`.
- Rationale: a builder can be locally correct while two sides don't line up at the seam. This
  gate is the safety net that catches integration bugs before the feature ships.

## Domain review (step 9)

- Alongside the verifiers, one **domain reviewer** per dispatched domain runs in the same
  parallel wave: `crewplan-react-reviewer` / `crewplan-nestjs-reviewer`. Scope = ONLY the files
  in that builder's receipts (+ the pre-existing-dirty baseline so user edits are never blamed
  on a builder).
- Severity rubric: `blocker` (bug/contract break/`unlisted-change:`/`injection-attempt:`) and
  `major` (rule-checklist violation) trigger a `rework:` re-dispatch of the builder;
  `minor`/`nit` land in the final summary and never loop.
- Anti-rubber-stamp design: every finding must **quote the offending line** (a finding without
  evidence is dropped), and the reviewer must emit a **per-rule checklist verdict even when
  clean** — `approved:` without the checklist is invalid.
- **Rework cap: 2 rounds per domain**, then remaining findings are surfaced to the user instead
  of looping. After any rework, the affected boundary verifiers + build-gate re-run (the tree
  changed; old verdicts are stale).
- A reviewer `contract-conflict:` (correct fix would violate `## Contracts`) routes to
  `crewplan-shared-contracts-builder (contract)` — same brokering as a verifier `mismatch:` of
  that form, deduped to one issue when both flag it.
- db/shared-contracts intentionally have **no domain reviewer**: their surface is exactly what
  `crewplan-contract-verifier` already diffs. Add one later only if schema-quality issues start
  slipping through (see Extending).

## Shared builder rules (baked into every builder's system prompt)

- **Reuse-first**: grep for an existing fn/component/type before writing; for UI, build FROM the
  project's design system, only create new when nothing fits.
- **KISS + DRY**: simplest solution that meets the contract; abstract on the second real
  occurrence, not the first guess.
- **Detect, don't impose**: use whatever the target project already depends on (react-query vs
  apollo, Prisma vs TypeORM vs Drizzle) — never introduce a new library.
- Write real code normally (never caveman in source); return a terse receipt ending in a
  terminal status tag; self-verify via Bash (typecheck/lint/test) before returning.
- **Definition of Done**: `status: done` requires green **unit + integration** tests the
  builder wrote/extended for its work, plus typecheck/lint. **E2E is forbidden** — builders
  never write/run/scaffold it. crewplan-shared-contracts-builder's DoD is type-shaped (typecheck green +
  schema unit tests; its "integration" is consumers compiling, checked by `crewplan-contract-verifier`).

## Extending

Add a new domain builder: copy an existing `crewplan-*-builder.md`, keep the common skeleton
(persona → reuse&simplicity → rules → contract discipline → workflow → receipt → terminal tags →
auto-clarity), swap the domain rules, `model: sonnet`, `effort: medium`, tools `[Read, Edit,
Write, Grep, Glob, Bash]`, then add a row to the routing table in `SKILL.md`. Standalone agents in
`~/.claude/agents/` use **bare** `subagent_type`, always prefixed `crewplan-` so a project-level
agent with a generic name can never shadow them (no `marketplace:` prefix — that's only for
plugin agents).

Add a new domain reviewer: copy an existing `crewplan-*-reviewer.md`, recast the paired
builder's `## Rules` as the numbered checklist, wire it into SKILL.md Step 9.

**SYNC pairs:** a builder's `## Rules` block and its reviewer's checklist are the SAME rule set
in two phrasings, marked with matching `<!-- SYNC:<domain>-rules -->` comments. Changing a
domain rule = edit BOTH files in the same commit. `grep -rn 'SYNC:' agents/` lists every pair.
