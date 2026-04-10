#!/usr/bin/env bash
# Install Solidity skills for Claude Code
# Usage:
#   ./install.sh          — install to ~/.claude/skills/ (personal, all projects)
#   ./install.sh --local  — install to .claude/skills/ (current project only)

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=("design-solidity" "develop-solidity" "solidity-security" "solidity-test")

if [[ "$1" == "--local" ]]; then
  SKILLS_DIR="$(pwd)/.claude/skills"
  SCOPE="local (current project)"
else
  SKILLS_DIR="$HOME/.claude/skills"
  SCOPE="personal (all projects)"
fi

mkdir -p "$SKILLS_DIR"

echo "Installing to: $SKILLS_DIR ($SCOPE)"
echo ""

for skill in "${SKILLS[@]}"; do
  src="$REPO_DIR/$skill"
  dst="$SKILLS_DIR/$skill"

  if [[ ! -d "$src" ]]; then
    echo "  skip: $skill (directory not found)"
    continue
  fi

  if [[ -L "$dst" ]]; then
    rm "$dst"
  elif [[ -d "$dst" ]]; then
    echo "  skip: $skill (already exists at $dst — remove it manually to reinstall)"
    continue
  fi

  ln -s "$src" "$dst"
  echo "  installed: $skill"
done

echo ""
echo "Done. Restart Claude Code to pick up the new skills."
