# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## How to Use This Changelog

This changelog is maintained manually and follows these conventions:

### For Maintainers

When merging a PR, add an entry to the `[Unreleased]` section under the appropriate subsection:

- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for vulnerability fixes

Each entry should:

1. Be a concise description of the change
2. Include a link to the PR in the format `([#123](link-to-pr))`
3. Credit the contributor if applicable with `@username`

### Example Entry

```markdown
### Added
- New caching strategy for improved performance ([#42](https://github.com/lemmih/nix-s3-cache-action/pull/42)) @contributor
```

### Creating a Release

When creating a new release:

1. Create a new section with the version number and date: `## [1.0.0] - 2024-01-15`
2. Move all items from `[Unreleased]` to this new section
3. Update the links at the bottom of the file
4. Commit with message: `docs: release v1.0.0`

## [Unreleased]

## [1.0.2] - 2025-12-08

### Fixed

- Fix major version tag not being updated after automated releases ([#17](https://github.com/lemmih/nix-s3-cache-action/pull/17))

## [1.0.1] - 2025-12-07

### Fixed

- Update README references to new repo name `nix-s3-cache-action` ([#13](https://github.com/lemmih/nix-s3-cache-action/pull/13))

## [1.0.0] - 2025-12-07

Initial release of nix-s3-cache.

### Added

- GitHub Action for configuring Nix to use S3-compatible storage as a binary cache
- Support for AWS S3, Cloudflare R2, Tebi, and other S3-compatible providers
- Read-only and read-write cache modes
- AWS OIDC authentication support
- Optional automatic bucket creation

[Unreleased]: https://github.com/lemmih/nix-s3-cache-action/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/lemmih/nix-s3-cache-action/releases/tag/v1.0.2
[1.0.1]: https://github.com/lemmih/nix-s3-cache-action/releases/tag/v1.0.1
[1.0.0]: https://github.com/lemmih/nix-s3-cache-action/releases/tag/v1.0.0
