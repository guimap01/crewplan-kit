# crewplan-kit

Orchestrated **plan → build → verify** tooling for Claude Code: a planning skill that fans out
cheap read-only investigators, then dispatches specialist builder agents to execute the plan,
owning the contracts between them and gating on a post-build integration check.

Version-controlled here so it survives machine changes; symlinked into `~/.claude/` so it runs
live. **Standalone agents use bare `subagent_type`** (`react-builder`, not `plugin:react-builder`)
— this is a dotfiles repo, **not** a Claude plugin, so the bare names the skill dispatches keep
working unchanged.

## Layout

```
agents/                          # spawnable agent personas (bare subagent_type)
  crewplan-investigator.md       #   haiku read-only locator (planning phase)
  shared-contracts-builder.md    #   sonnet — FE↔BE types/DTO/GraphQL (contract authority)
  db-builder.md                  #   sonnet — ORM schema/migrations/repositories
  nestjs-builder.md              #   sonnet — NestJS modules/services/controllers
  react-builder.md               #   sonnet — React components/hooks/context
  contract-verifier.md           #   sonnet read-only — post-build integration gate
skills/crewplan/
  SKILL.md                       # the /crewplan orchestrator procedure
  BUILDERS.md                    # roster + contract/deviation protocol reference
install.sh                       # symlinks the above into ~/.claude/
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
3. Post-build gate: read-only `contract-verifier` diffs both sides of each boundary against the
   contract + runs typecheck/build. Any mismatch loops back into the broker until green.

Every builder's **Definition of Done** requires green **unit + integration** tests it wrote
(e2e is forbidden). Full detail in `skills/crewplan/BUILDERS.md` and `skills/crewplan/SKILL.md`.

## Updating

The installed files are symlinks, so edits to files in this repo are live immediately. After
editing, `git commit` + `git push` to save. Pull on another machine + re-run `./install.sh`.

## Uninstall

```sh
rm ~/.claude/agents/{crewplan-investigator,shared-contracts-builder,db-builder,nestjs-builder,react-builder,contract-verifier}.md
rm -rf ~/.claude/skills/crewplan
```
(These remove the symlinks only; the repo copies stay.)
