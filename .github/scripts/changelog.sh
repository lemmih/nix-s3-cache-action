#!/usr/bin/env bash
# Shared functions for CHANGELOG parsing in release workflows
#
# Usage:
#   source .github/scripts/changelog.sh
#   detect_new_version "current_changelog.md" "base_changelog.md"
#   extract_release_notes "changelog.md" "1.0.0"

set -euo pipefail

# Extract version numbers from a CHANGELOG.md file
# Format expected: ## [1.0.0] - 2024-01-15
# Args: $1 = path to changelog file
# Output: space-separated list of versions (e.g., "1.0.0 0.9.0 0.8.0")
get_versions() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$file" |
    sed -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/' || true
}

# Detect a new version by comparing two changelogs
# Args: $1 = current changelog, $2 = base changelog
# Output: Sets NEW_VERSION variable, or empty if no new version
detect_new_version() {
  local current_file="$1"
  local base_file="$2"

  local current_versions
  local base_versions
  current_versions=$(get_versions "$current_file")
  base_versions=$(get_versions "$base_file")

  NEW_VERSION=""
  for version in $current_versions; do
    if ! echo "$base_versions" | grep -qw "$version"; then
      NEW_VERSION="$version"
      break
    fi
  done

  echo "$NEW_VERSION"
}

# Extract release notes for a specific version from CHANGELOG.md
# Args: $1 = changelog file, $2 = version (e.g., "1.0.0")
# Output: The release notes content
extract_release_notes() {
  local file="$1"
  local version="$2"

  awk -v ver="$version" '
$0 ~ "^## \\[" ver "\\]" { capture=1; next }
/^## \[/ { capture=0 }
capture { print }
' "$file"
}
