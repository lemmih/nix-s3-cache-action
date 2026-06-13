#!/bin/bash
set -eu

# Check if Nix is installed
if ! command -v nix >/dev/null 2>&1; then
  echo "Error: Nix is not installed. Please install Nix first using DeterminateSystems/nix-installer-action (https://github.com/DeterminateSystems/nix-installer-action)."
  exit 1
fi

# Determine config file
if [ -f /etc/nix/nix.custom.conf ]; then
  CONFIG_FILE="/etc/nix/nix.custom.conf"
else
  CONFIG_FILE="/etc/nix/nix.conf"
fi

install_root_file() {
  local mode="$1"
  local path="$2"

  sudo install -o root -g root -m "$mode" /dev/stdin "$path"
}

write_env_export() {
  local name="$1"
  local value="$2"

  printf 'export %s=' "$name"
  printf '%q' "$value"
  printf '\n'
}

# Set AWS credentials
AWS_ACCESS_KEY_ID="${INPUT_AWS_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
AWS_SECRET_ACCESS_KEY="${INPUT_AWS_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
AWS_SESSION_TOKEN="${INPUT_AWS_SESSION_TOKEN:-${AWS_SESSION_TOKEN:-}}"
AWS_DEFAULT_REGION="${INPUT_REGION:-${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}}"
INPUT_CREATE_BUCKET="${INPUT_CREATE_BUCKET:-false}"

# Determine if we need --endpoint-url (not needed for native AWS S3)
# Also build the Nix S3 URL parameters accordingly
if [[ "$INPUT_S3_ENDPOINT" == "s3.amazonaws.com" || "$INPUT_S3_ENDPOINT" == s3.*.amazonaws.com ]]; then
  ENDPOINT_URL_ARG=""
  NIX_S3_PARAMS="region=${AWS_DEFAULT_REGION}"
else
  ENDPOINT_URL_ARG="--endpoint-url https://${INPUT_S3_ENDPOINT}"
  NIX_S3_PARAMS="endpoint=${INPUT_S3_ENDPOINT}"
fi

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  sudo install -d -o root -g root -m 700 /root/.aws
  {
    printf '%s\n' \
      '[default]' \
      "aws_access_key_id = ${AWS_ACCESS_KEY_ID}" \
      "aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}" \
      "region = ${AWS_DEFAULT_REGION}"
    if [ -n "$AWS_SESSION_TOKEN" ]; then
      printf '%s\n' "aws_session_token = ${AWS_SESSION_TOKEN}"
    fi
  } | install_root_file 600 /root/.aws/credentials

  # Export for AWS CLI usage
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
  if [ -n "$AWS_SESSION_TOKEN" ]; then
    export AWS_SESSION_TOKEN
  fi

  # Check if bucket exists
  # shellcheck disable=SC2086 # Word splitting is intentional for ENDPOINT_URL_ARG
  if ! aws s3 ls "s3://${INPUT_BUCKET}/" $ENDPOINT_URL_ARG >/dev/null 2>&1; then
    if [ "$INPUT_CREATE_BUCKET" = "true" ]; then
      echo "Bucket '${INPUT_BUCKET}' does not exist. Creating..."
      # shellcheck disable=SC2086 # Word splitting is intentional for ENDPOINT_URL_ARG
      aws s3 mb "s3://${INPUT_BUCKET}" $ENDPOINT_URL_ARG
    else
      echo "Error: S3 bucket '${INPUT_BUCKET}' does not exist or is not accessible with the provided credentials."
      exit 1
    fi
  fi
fi

if sudo test -f /root/.aws/credentials; then
  sudo chown root:root /root/.aws/credentials
  sudo chmod 600 /root/.aws/credentials
fi

# Create signing key file if provided
if [ -n "$INPUT_PRIVATE_KEY" ]; then
  install_root_file 600 /etc/nix/cache-priv-key.pem <<<"$INPUT_PRIVATE_KEY"
  SECRET_KEY_PARAM="&secret-key=/etc/nix/cache-priv-key.pem"
else
  SECRET_KEY_PARAM=""
fi

# Create root-only environment file for the post-build hook
{
  write_env_export AWS_DEFAULT_REGION "$AWS_DEFAULT_REGION"
  if [ -n "$AWS_ACCESS_KEY_ID" ]; then
    write_env_export AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
  fi
  if [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    write_env_export AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
  fi
  if [ -n "$AWS_SESSION_TOKEN" ]; then
    write_env_export AWS_SESSION_TOKEN "$AWS_SESSION_TOKEN"
  fi
} | install_root_file 600 /etc/nix/s3-cache.env

# Create post-build hook
# shellcheck disable=SC2016 # Single quotes intentional - variables should expand at runtime, not now
{
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '' \
    'source /etc/nix/s3-cache.env' \
    '' \
    'echo "Uploading to S3: $OUT_PATHS"' \
    "if ! /nix/var/nix/profiles/default/bin/nix copy --to \"s3://${INPUT_BUCKET}?${NIX_S3_PARAMS}${SECRET_KEY_PARAM}&compression=zstd\" \$OUT_PATHS; then" \
    '  echo "Warning: failed to upload build outputs to the S3 cache; continuing without failing the build." >&2' \
    'fi'
} | install_root_file 700 /etc/nix/post-build-hook.sh

sudo chown root:root /etc/nix/post-build-hook.sh
sudo chmod 700 /etc/nix/post-build-hook.sh
sudo chown root:root /etc/nix/s3-cache.env
sudo chmod 600 /etc/nix/s3-cache.env
if [ -n "$INPUT_PRIVATE_KEY" ]; then
  sudo chown root:root /etc/nix/cache-priv-key.pem
  sudo chmod 600 /etc/nix/cache-priv-key.pem
fi

# Configure Nix
sudo touch "$CONFIG_FILE"
TMP_CONFIG="$(mktemp)"
sudo awk \
  -v substituter="s3://${INPUT_BUCKET}?${NIX_S3_PARAMS}" \
  -v public_key="${INPUT_PUBLIC_KEY}" \
  '
  /^# BEGIN nix-s3-cache-action$/ { in_managed_block = 1; next }
  /^# END nix-s3-cache-action$/ { in_managed_block = 0; next }
  in_managed_block { next }
  $0 == "extra-substituters = " substituter { next }
  $0 == "extra-trusted-public-keys = " public_key { next }
  $0 == "post-build-hook = /etc/nix/post-build-hook.sh" { next }
  { print }
  ' "$CONFIG_FILE" | tee "$TMP_CONFIG" >/dev/null
cat >>"$TMP_CONFIG" <<EOF
# BEGIN nix-s3-cache-action
extra-substituters = s3://${INPUT_BUCKET}?${NIX_S3_PARAMS}
extra-trusted-public-keys = ${INPUT_PUBLIC_KEY}
post-build-hook = /etc/nix/post-build-hook.sh
# END nix-s3-cache-action
EOF
sudo install -o root -g root -m 644 "$TMP_CONFIG" "$CONFIG_FILE"
rm -f "$TMP_CONFIG"

# Restart nix-daemon
sudo systemctl restart nix-daemon || true
