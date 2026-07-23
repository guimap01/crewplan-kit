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

| Agent | Model | Role |
|---|---|---|
| `crewplan-investigator` | haiku | read-only locator, one question per spawn (planning phase) |
| `crewplan-shared-contracts-builder` | sonnet | **contract authority** — shared TS types/DTO/GraphQL, no logic |
| `crewplan-db-builder` | sonnet | ORM schema/entities/migrations/repositories |
| `crewplan-nestjs-builder` | sonnet | NestJS modules/controllers/services/DTOs |
| `crewplan-react-builder` | sonnet | React components/hooks/context/query wiring |
| `crewplan-contract-verifier` | sonnet | **read-only** post-build gate — diffs both sides vs contract + runs typecheck/build |

Investigators are cheap/haiku; everything that writes or judges real code is Sonnet.

## The contract protocol (the glue)

- The orchestrator writes a `## Contracts` section in the plan BEFORE dispatch: each boundary's
  exact shape/endpoint + which builder OWNS it vs CONSUMES it. This is the diff baseline.
- Dispatch order = **dependency order**: `shared-contracts → db → nestjs → react` (types first,
  UI last). Builders run **sequentially** by default (they mutate files, contracts couple them);
  parallelize only independent steps and only with `isolation: worktree`.
- A builder that can't meet its contract does NOT improvise — it halts and returns
  `deviation: <what> | reason | need + owning-builder | affects: <consumers>`. Also
  `blocked:` / `ambiguous:`.
- **Broker loop (step 8):** on any `deviation:`, route the change to the owning builder
  (cross-FE/BE shapes → `crewplan-shared-contracts-builder` first), amend `## Contracts`, re-dispatch the
  `affects:` builders, loop until all `status: done`.

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

Add a new domain builder: copy an existing `*-builder.md`, keep the common skeleton (persona →
reuse&simplicity → rules → contract discipline → workflow → receipt → terminal tags →
auto-clarity), swap the domain rules, `model: sonnet`, tools `[Read, Edit, Write, Grep, Glob,
Bash]`, then add a row to the routing table in `SKILL.md`. Standalone agents in
`~/.claude/agents/` use **bare** `subagent_type` (no `marketplace:` prefix — that's only for
plugin agents).
