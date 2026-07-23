#!/usr/bin/env bash
# Symlink the crewplan skill + agents from this repo into ~/.claude so they are LIVE
# while staying version-controlled here. Idempotent — safe to re-run after `git pull`.
#
# After install, e.g. ~/.claude/agents/crewplan-react-builder.md is a symlink to this repo's copy,
# so editing the repo file changes the live agent, and `git commit` versions it.
#
# Env: set CLAUDE_HOME to override the target (defaults to ~/.claude).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    ln -sfn "$src" "$dst"; echo "relinked  $dst"
  elif [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      rm -f "$dst"                                   # identical → just replace with link
    else
      mv "$dst" "$dst.bak.$(date +%s)"; echo "backed up $dst -> $dst.bak.*"
    fi
    ln -s "$src" "$dst"; echo "linked    $dst"
  else
    ln -s "$src" "$dst"; echo "linked    $dst"
  fi
}

# Remove dangling symlinks that point into this repo (e.g. after a file was renamed here).
# Only repo-owned AND dangling links are touched — other agents/plugins are never affected.
prune() {
  local dir="$1" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -L "$f" ] || continue
    case "$(readlink "$f")" in
      "$REPO_DIR"/*) [ -e "$f" ] || { rm "$f"; echo "pruned    $f"; } ;;
    esac
  done
}

for f in "$REPO_DIR"/agents/*.md; do
  link "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done
for f in "$REPO_DIR"/skills/crewplan/*; do
  link "$f" "$CLAUDE_DIR/skills/crewplan/$(basename "$f")"
done
prune "$CLAUDE_DIR/agents"
prune "$CLAUDE_DIR/skills/crewplan"

count=$(find "$REPO_DIR/agents" -name '*.md' | wc -l | tr -d ' ')
echo "done. crewplan skill + $count agents linked into $CLAUDE_DIR"
echo "restart Claude Code (or start a new session) to pick up newly-linked agents."
