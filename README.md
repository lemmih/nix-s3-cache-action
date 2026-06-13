# nix-s3-cache-action 🚀

We love Nix! ❄️ Reproducible builds, declarative configs, and that warm fuzzy feeling when `nix build` just works.

But let's be honest - without caching, your CI will spend more time compiling than a philosophy major spends contemplating existence. ☕

This GitHub Action hooks up your Nix builds to any S3-compatible storage, so you can stop recompiling the universe on every push.

## 🤔 Alternatives

There are other great caching solutions out there:

- **[Cachix](https://www.cachix.org/)** - The OG Nix cache. Polished and reliable, but can get pricey for larger teams.
- **[Magic Nix Cache](https://github.com/DeterminateSystems/magic-nix-cache)** - Zero-config caching using GitHub Actions cache. Super convenient, but limited to 10 GiB and artifacts expire after 7 days.
- **[FlakeHub Cache](https://flakehub.com/)** - Integrated with FlakeHub's flake registry. Nice if you're already in that ecosystem.

**nix-s3-cache-action** gives you full control over your cache with any S3-compatible storage. Bring your own bucket, pay only for what you use (or nothing at all with free tiers! 🎉).

## 💸 S3 Providers with Free Tiers

| Provider | Free Storage |
|----------|--------------|
| [Backblaze B2](https://www.backblaze.com/cloud-storage) | 10 GiB |
| [Cloudflare R2](https://www.cloudflare.com/developer-platform/r2/) | 10 GiB |
| [AWS S3](https://aws.amazon.com/s3/) | 5 GiB |

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| `s3-endpoint` | Yes | S3 endpoint (e.g., `s3.amazonaws.com`, `<account>.r2.cloudflarestorage.com`) |
| `bucket` | Yes | S3 bucket name |
| `public-key` | Yes | Public key for verifying cached derivations |
| `private-key` | No | Private key for signing uploads (omit for read-only) |
| `aws-access-key-id` | No | Falls back to `AWS_ACCESS_KEY_ID` env var |
| `aws-secret-access-key` | No | Falls back to `AWS_SECRET_ACCESS_KEY` env var |
| `aws-session-token` | No | Falls back to `AWS_SESSION_TOKEN` env var (for OIDC/temporary creds) |
| `region` | No | Falls back to `AWS_DEFAULT_REGION`, `AWS_REGION`, or `us-east-1` |
| `create-bucket` | No | Create bucket if it doesn't exist (default: `false`) |

## Failure Behavior and Secret Files

Cache uploads run from Nix's post-build hook. Upload failures are reported as warnings, but they do not fail the build or test command that produced the store paths.

The action writes the cache signing key, AWS environment file, AWS credentials file, and post-build hook as root-owned files with restrictive permissions. AWS credentials are stored in `/etc/nix/s3-cache.env` and sourced by the hook instead of being embedded directly in the hook script.

## Generating Cache Keys

```bash
nix key generate-secret --key-name my-cache > cache-priv-key.pem
nix key convert-secret-to-public < cache-priv-key.pem
# Output: my-cache:BASE64...
```

Store the private key as a GitHub secret (`NIX_CACHE_PRIVATE_KEY`). The public key goes in `public-key`.

## Examples

### AWS S3 with OIDC (Recommended)

Uses temporary credentials via GitHub's OIDC provider. No long-lived secrets required.

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsNixCache
          aws-region: us-east-1

      - uses: lemmih/nix-s3-cache-action@main
        with:
          s3-endpoint: s3.amazonaws.com
          bucket: my-nix-cache
          public-key: my-cache:BASE64PUBLIC...
          private-key: ${{ secrets.NIX_CACHE_PRIVATE_KEY }}

      - run: nix build
```

IAM policy for the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::my-nix-cache",
        "arn:aws:s3:::my-nix-cache/*"
      ]
    }
  ]
}
```

### AWS S3 with Access Keys

Uses static IAM credentials stored as GitHub secrets.

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: lemmih/nix-s3-cache-action@main
        with:
          s3-endpoint: s3.amazonaws.com
          bucket: my-nix-cache
          region: us-west-2
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          public-key: my-cache:BASE64PUBLIC...
          private-key: ${{ secrets.NIX_CACHE_PRIVATE_KEY }}

      - run: nix build
```

### Cloudflare R2

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: lemmih/nix-s3-cache-action@main
        with:
          s3-endpoint: ${{ secrets.CF_ACCOUNT_ID }}.r2.cloudflarestorage.com
          bucket: nix-cache
          aws-access-key-id: ${{ secrets.R2_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.R2_SECRET_ACCESS_KEY }}
          public-key: my-cache:BASE64PUBLIC...
          private-key: ${{ secrets.NIX_CACHE_PRIVATE_KEY }}

      - run: nix build
```

R2 credentials are generated in Cloudflare Dashboard > R2 > Manage R2 API Tokens.

### Backblaze B2

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: lemmih/nix-s3-cache-action@main
        with:
          s3-endpoint: s3.us-west-004.backblazeb2.com
          bucket: nix-cache
          region: us-west-004
          aws-access-key-id: ${{ secrets.B2_APPLICATION_KEY_ID }}
          aws-secret-access-key: ${{ secrets.B2_APPLICATION_KEY }}
          public-key: my-cache:BASE64PUBLIC...
          private-key: ${{ secrets.NIX_CACHE_PRIVATE_KEY }}

      - run: nix build
```

Use the S3 endpoint shown for your Backblaze B2 bucket, and set `region` to the region in that endpoint.
