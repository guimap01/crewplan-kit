# crewplan-kit

Orchestrated **plan → build → verify** tooling for Claude Code: a planning skill that fans out
cheap read-only investigators, then dispatches specialist builder agents to execute the plan,
owning the contracts between them and gating on a post-build integration check.

Version-controlled here so it survives machine changes; symlinked into `~/.claude/` so it runs
live. **Standalone agents use bare `subagent_type`** (`crewplan-react-builder`, not `plugin:crewplan-react-builder`)
— this is a dotfiles repo, **not** a Claude plugin, so the bare names the skill dispatches keep
working unchanged.

## Layout

```
agents/                                 # spawnable agent personas (bare subagent_type)
  crewplan-investigator.md              #   haiku read-only locator (planning phase)
  crewplan-shared-contracts-builder.md  #   sonnet — FE↔BE types/DTO/GraphQL (contract authority)
  crewplan-db-builder.md                #   sonnet — ORM schema/migrations/repositories
  crewplan-nestjs-builder.md            #   sonnet — NestJS modules/services/controllers
  crewplan-react-builder.md             #   sonnet — React components/hooks/context
  crewplan-contract-verifier.md         #   sonnet read-only — post-build integration gate
  crewplan-react-reviewer.md            #   sonnet read-only — step-9 react domain review
  crewplan-nestjs-reviewer.md           #   sonnet read-only — step-9 nestjs domain review
skills/crewplan/
  SKILL.md                              # the /crewplan orchestrator procedure
  BUILDERS.md                           # roster + contract/deviation protocol reference
install.sh                              # symlinks the above into ~/.claude/
```

## Install

```sh
git clone <this-repo-url> ~/crewplan-kit
cd ~/crewplan-kit
./install.sh            # symlinks agents/ + skills/crewplan/ into ~/.claude/
```

Restart Claude Code (or start a new session) so the newly-linked agents register. Override the
target with `CLAUDE_HOME=/path ./install.sh`.

## How it works

1. `/crewplan <task>` — decompose → parallel haiku `crewplan-investigator` fan-out → synthesize
   a plan with a `## Contracts` section (boundary shapes + owners).
2. After approval, dispatch builders in dependency order
   `shared-contracts → db → nestjs → react` (sequential — they mutate the tree). Each builder
   conforms to its boundary contract or halts with a `deviation:` the orchestrator brokers.
3. Post-build gate (one parallel read-only wave): `crewplan-contract-verifier` diffs both sides
   of each boundary against the contract + runs typecheck/build, while
   `crewplan-react-reviewer` / `crewplan-nestjs-reviewer` audit each dispatched builder's
   receipts against its domain rule checklist (quoted evidence per finding, checklist verdict
   even when clean). Mismatches and blocker/major findings loop back into the broker —
   bounded (3 broker rounds per boundary, 2 review rounds per domain), then surfaced to you.

Every builder's **Definition of Done** requires green **unit + integration** tests it wrote
(e2e is forbidden). Full detail in `skills/crewplan/BUILDERS.md` and `skills/crewplan/SKILL.md`.

## Updating

The installed files are symlinks, so edits to files in this repo are live immediately. After
editing, `git commit` + `git push` to save. **Always re-run `./install.sh` after pulling** — a
pull can rename or add agent files, and the installer both links new ones and prunes symlinks
left dangling by renames. Then restart Claude Code so the agent registry refreshes.

### Troubleshooting

- **Moved the repo?** Old symlinks point at the previous path and the pruner only recognizes
  links into the *current* repo dir — delete stale `crewplan-*` links in `~/.claude/agents/`
  manually, then re-run `./install.sh`.
- **`/crewplan` reports an unknown `crewplan-*` agent?** The repo and the installed links are
  out of sync — re-run `./install.sh` and restart the session.

## Uninstall

```sh
rm ~/.claude/agents/{crewplan-investigator,crewplan-shared-contracts-builder,crewplan-db-builder,crewplan-nestjs-builder,crewplan-react-builder,crewplan-contract-verifier,crewplan-react-reviewer,crewplan-nestjs-reviewer}.md
rm -rf ~/.claude/skills/crewplan
```
(These remove the symlinks only; the repo copies stay.)
