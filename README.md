# nix-s3-cache

GitHub Action for caching Nix derivations with S3

## Usage

This action configures Nix to use an S3-backed cache for both downloading and uploading derivations. It works with both vanilla Nix and Determinate Nix by detecting the appropriate configuration file.

### Basic Example

```yaml
- name: Install Nix
  uses: DeterminateSystems/nix-installer-action@main

- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1

- name: Setup Nix S3 Cache
  uses: ./.github/actions/setup-nix-s3-cache
  with:
    s3-endpoint: https://s3.amazonaws.com
    bucket: my-nix-cache
    public-key: my-cache:public-key-here
    private-key: ${{ secrets.NIX_CACHE_PRIVATE_KEY }}
```

### With Cloudflare R2

```yaml
- name: Setup Nix S3 Cache
  uses: ./.github/actions/setup-nix-s3-cache
  with:
    s3-endpoint: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}.r2.cloudflarestorage.com
    bucket: nix-cache
    public-key: my-cache:public-key-here
    private-key: ${{ secrets.NIX_CACHE_PRIVATE_KEY }}
```

### Inputs

- `s3-endpoint` (required): S3 endpoint URL (e.g., `https://s3.amazonaws.com` or `https://account.r2.cloudflarestorage.com`)
- `bucket` (required): S3 bucket name
- `public-key` (required): Public key for verifying cache contents
- `private-key` (optional): Private key for signing uploads. If omitted, uploads will not be signed.
- `aws-access-key-id` (optional): AWS access key ID. Defaults to `AWS_ACCESS_KEY_ID` environment variable.
- `aws-secret-access-key` (optional): AWS secret access key. Defaults to `AWS_SECRET_ACCESS_KEY` environment variable.
- `region` (optional): AWS region. Defaults to `AWS_DEFAULT_REGION`, `AWS_REGION`, or `us-east-1`.

## Compatibility

- **Vanilla Nix**: Appends configuration to `/etc/nix/nix.conf`
- **Determinate Nix**: Appends configuration to `/etc/nix/nix.custom.conf`
- **AWS Credentials**: Compatible with `aws-actions/configure-aws-credentials`
