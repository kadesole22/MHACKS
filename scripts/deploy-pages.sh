#!/usr/bin/env bash
# Builds web/ (including the Godot export in web/public/game) and force-pushes it to the gh-pages branch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE="$(git -C "$ROOT" remote get-url origin)"
NAME="$(git -C "$ROOT" config user.name)"
EMAIL="$(git -C "$ROOT" config user.email)"

if [ ! -f "$ROOT/web/public/game/index.js" ]; then
  echo "No Godot web export found in web/public/game. Export it from Godot first." >&2
  exit 1
fi

npm --prefix "$ROOT/web" run build

cd "$ROOT/web/dist"
touch .nojekyll
git init -q -b gh-pages
git add -A
git -c user.name="$NAME" -c user.email="$EMAIL" commit -q -m "Deploy $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push -f "$REMOTE" gh-pages
rm -rf .git
