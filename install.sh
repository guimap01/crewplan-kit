#!/usr/bin/env bash
# Symlink the skills + agents from this repo into ~/.claude so they are LIVE
# while staying version-controlled here. Idempotent — safe to re-run after `git pull`.
#
# After install, e.g. ~/.claude/agents/crewplan-react-builder.md is a symlink to this repo's copy,
# so editing the repo file changes the live agent, and `git commit` versions it.
#
# Every directory under skills/ is linked (crewplan, uiplan, ...). Skills are kept FLAT:
# SKILL.md plus sibling reference files, no subdirectories.
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
# Sets PRUNED=1 if it actually removed something, so callers can tell an emptied dir from a
# dir that was already empty and belongs to someone else.
prune() {
  local dir="$1" f
  PRUNED=0
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -L "$f" ] || continue
    case "$(readlink "$f")" in
      "$REPO_DIR"/*) [ -e "$f" ] || { rm "$f"; echo "pruned    $f"; PRUNED=1; } ;;
    esac
  done
}

for f in "$REPO_DIR"/agents/*.md; do
  [ -e "$f" ] || continue
  link "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done

for d in "$REPO_DIR"/skills/*/; do
  [ -d "$d" ] || continue
  s="$(basename "$d")"
  for f in "$d"*; do
    [ -e "$f" ] || continue
    [ -d "$f" ] && { echo "skip dir   $f (skills must be flat)"; continue; }
    link "$f" "$CLAUDE_DIR/skills/$s/$(basename "$f")"
  done
done

# Prune over INSTALLED dirs, not repo dirs: a skill deleted from the kit still has to have its
# now-dangling links cleaned up, and prune() already ignores anything not owned by this repo.
prune "$CLAUDE_DIR/agents"
for d in "$CLAUDE_DIR"/skills/*/; do
  [ -d "$d" ] || continue
  prune "$d"
  # Only clean up a dir THIS run emptied. An already-empty dir we did not touch belongs to
  # someone else (a user's WIP skill scaffold) and is left alone.
  if [ "$PRUNED" = 1 ]; then rmdir "$d" 2>/dev/null || true; fi
done

agents=$(find "$REPO_DIR/agents" -name '*.md' | wc -l | tr -d ' ')
skills=$(find "$REPO_DIR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "done. $skills skills + $agents agents linked into $CLAUDE_DIR"
echo "restart Claude Code (or start a new session) to pick up newly-linked agents."
