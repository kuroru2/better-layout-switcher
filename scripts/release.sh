#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/release.sh <major|minor|patch>
# Bumps version, generates release notes from conventional commits,
# commits, and creates an annotated tag.

BUMP_TYPE="${1:-}"
if [[ ! "$BUMP_TYPE" =~ ^(major|minor|patch)$ ]]; then
  echo "Usage: $0 <major|minor|patch>"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- Read current version from VERSION file ---
CURRENT=$(cat VERSION | tr -d '[:space:]')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP_TYPE" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo "Bumping $CURRENT → $NEW_VERSION"

# --- Bump version ---
echo "$NEW_VERSION" > VERSION

# --- Generate release notes from commits since last tag ---
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [[ -n "$LAST_TAG" ]]; then
  RANGE="${LAST_TAG}..HEAD"
else
  RANGE="HEAD"
fi

FEATS=""
FIXES=""
OTHER=""

while IFS= read -r line; do
  line="$(echo "$line" | sed 's/^ *//')"
  [[ -z "$line" ]] && continue

  # Skip version bump and merge commits
  [[ "$line" =~ ^chore:\ bump\ version ]] && continue
  [[ "$line" =~ ^chore\(release\) ]] && continue

  if [[ "$line" =~ ^feat ]]; then
    msg="$(echo "$line" | sed 's/^feat[^:]*: //')"
    FEATS="${FEATS}- ${msg}\n"
  elif [[ "$line" =~ ^fix ]]; then
    msg="$(echo "$line" | sed 's/^fix[^:]*: //')"
    FIXES="${FIXES}- ${msg}\n"
  elif [[ "$line" =~ ^docs: ]]; then
    continue
  else
    OTHER="${OTHER}- ${line}\n"
  fi
done <<< "$(git log "$RANGE" --pretty=format:'%s' --no-merges)"

# Build release notes
NOTES="v${NEW_VERSION}\n"

if [[ -n "$FEATS" ]]; then
  NOTES="${NOTES}\n### Features\n${FEATS}"
fi
if [[ -n "$FIXES" ]]; then
  NOTES="${NOTES}\n### Fixes\n${FIXES}"
fi
if [[ -n "$OTHER" ]]; then
  NOTES="${NOTES}\n### Other\n${OTHER}"
fi

echo ""
echo "--- Release Notes ---"
echo -e "$NOTES"
echo "---------------------"
echo ""

# --- Commit and tag ---
git add VERSION
git commit -m "chore: bump version to ${NEW_VERSION}"
git tag -a "v${NEW_VERSION}" -m "$(echo -e "$NOTES")"

echo "Done! Created tag v${NEW_VERSION}"
echo "Run 'git push && git push --tags' to publish."
