# Releasing

This document describes the release process for nix-s3-cache.

## Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (`v1.0.0` -> `v2.0.0`): Breaking changes to the action interface
- **MINOR** (`v1.0.0` -> `v1.1.0`): New features, backward compatible
- **PATCH** (`v1.0.0` -> `v1.0.1`): Bug fixes, backward compatible

Users reference this action via a major version tag (e.g., `@v1`), which always
points to the latest release within that major version.

## Creating a Release

Releases are driven by CHANGELOG.md - the single source of truth for versions.

### Steps

1. **Create a PR** that updates CHANGELOG.md:
   - Move entries from `[Unreleased]` to a new version section
   - Use the format: `## [1.0.0] - 2024-01-15`
   - Keep the `[Unreleased]` section (empty) for future changes

2. **The workflow automatically comments** on your PR:
   - Detects the new version in CHANGELOG.md
   - Shows what will happen when the PR is merged

3. **Merge the PR** - The workflow automatically:
   - Creates and pushes the version tag (e.g., `v1.0.0`)
   - Creates a GitHub Release with notes from CHANGELOG.md
   - Updates the major version tag (e.g., `v1`)

### Example CHANGELOG Update

Before (in your PR):

```markdown
## [Unreleased]

### Added
- New feature X

### Fixed
- Bug Y
```

After (in your PR):

```markdown
## [Unreleased]

## [1.1.0] - 2024-12-07

### Added
- New feature X

### Fixed
- Bug Y
```

## How the Release Workflow Works

### On PR Open/Update

1. Compares CHANGELOG.md in the PR against the base branch
2. Detects any new version entries (e.g., `## [1.0.0] - 2024-01-15`)
3. Comments on the PR explaining what will happen on merge

### On Push to Main

When a commit lands on `main` (via merge, squash, or rebase):

1. Compares CHANGELOG.md against the parent commit
2. Detects any new version entries
3. Extracts release notes for that version
4. Creates the version tag on the correct commit
5. Creates a GitHub Release with the extracted notes

This approach ensures the tag is always on the actual commit that landed on
`main`, regardless of merge strategy (merge commit, squash, or rebase).

### On Tag Push

1. Extracts the major version (`v1.2.3` -> `v1`)
2. Compares against the current highest version for that major
3. Only updates `v1` if `1.2.3` is greater (prevents accidental downgrades)
4. Creates the major tag if it doesn't exist yet

This means you can safely:

- Push hotfix tags for older versions (e.g., `v1.0.1` after `v1.1.0` exists)
- Re-tag commits if needed
- Push tags in any order

## Release Checklist

Before merging a release PR:

- [ ] **Update CHANGELOG.md**
  - Create a new version section with date (e.g., `## [1.0.0] - 2024-01-15`)
  - Move all entries from `[Unreleased]` to the new section
  - Keep the `[Unreleased]` section for future changes

- [ ] **Verify CI passes**
  - All tests pass on the PR
  - Linting checks pass

- [ ] **Review the release bot comment**
  - Confirm the detected version is correct

- [ ] **Test the action manually** (for significant changes)
  - Test with at least one S3 provider

## Manual Releases

For hotfixes or special cases, you can still create releases manually:

```bash
git checkout main
git pull origin main
git tag v1.2.3
git push origin v1.2.3
```

The workflow will automatically update the major version tag.

To create a GitHub Release manually:

```bash
gh release create v1.2.3 --title "v1.2.3" --notes "Release notes here"
```

## Breaking Changes (Major Version Bump)

When making breaking changes:

1. Document the migration path in CHANGELOG.md
2. Consider maintaining the old major version for critical fixes
3. Update README.md examples to use the new major version
4. Announce the breaking change in the GitHub Release notes
