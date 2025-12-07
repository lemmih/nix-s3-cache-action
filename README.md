# nix-s3-cache

GitHub Action for caching Nix derivations with S3-compatible storage.

Configures Nix to use an S3-backed cache for downloading and uploading derivations. Works with vanilla Nix and Determinate Nix.

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

      - uses: lemmih/nix-s3-cache/.github/actions/setup-nix-s3-cache@main
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

      - uses: lemmih/nix-s3-cache/.github/actions/setup-nix-s3-cache@main
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

      - uses: lemmih/nix-s3-cache/.github/actions/setup-nix-s3-cache@main
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

### Tebi

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: lemmih/nix-s3-cache/.github/actions/setup-nix-s3-cache@main
        with:
          s3-endpoint: s3.tebi.io
          bucket: nix-cache
          aws-access-key-id: ${{ secrets.TEBI_ACCESS_KEY }}
          aws-secret-access-key: ${{ secrets.TEBI_SECRET_KEY }}
          public-key: my-cache:BASE64PUBLIC...
          private-key: ${{ secrets.NIX_CACHE_PRIVATE_KEY }}

      - run: nix build
```

## Compatibility

- **Vanilla Nix**: Appends to `/etc/nix/nix.conf`
- **Determinate Nix**: Appends to `/etc/nix/nix.custom.conf`
- **AWS Credentials**: Works with `aws-actions/configure-aws-credentials` for OIDC
