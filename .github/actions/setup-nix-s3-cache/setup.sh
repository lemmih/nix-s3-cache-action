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

# Set AWS credentials
AWS_ACCESS_KEY_ID="${INPUT_AWS_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID}}"
AWS_SECRET_ACCESS_KEY="${INPUT_AWS_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY}}"
AWS_DEFAULT_REGION="${INPUT_REGION:-${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}}"

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  sudo mkdir -p /root/.aws
  printf '%s\n' \
    '[default]' \
    "aws_access_key_id = ${AWS_ACCESS_KEY_ID}" \
    "aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}" \
    "region = ${AWS_DEFAULT_REGION}" \
    | sudo tee /root/.aws/credentials > /dev/null
  sudo chmod 600 /root/.aws/credentials

  # Export for AWS CLI usage
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

  # Check if bucket exists
  if ! aws s3 ls "s3://${INPUT_BUCKET}/" --endpoint-url "https://${INPUT_S3_ENDPOINT}" >/dev/null 2>&1; then
    echo "Error: S3 bucket '${INPUT_BUCKET}' does not exist or is not accessible with the provided credentials."
    exit 1
  fi
fi

# Create signing key file if provided
if [ -n "$INPUT_PRIVATE_KEY" ]; then
  sudo tee /etc/nix/cache-priv-key.pem > /dev/null <<< "$INPUT_PRIVATE_KEY"
  sudo chmod 644 /etc/nix/cache-priv-key.pem
  SECRET_KEY_PARAM="&secret-key=/etc/nix/cache-priv-key.pem"
else
  SECRET_KEY_PARAM=""
fi

# Create post-build hook
printf '%s\n' \
  '#!/bin/bash' \
  'set -eu' \
  'set -o pipefail' \
  '' \
  "export AWS_ACCESS_KEY_ID=\"${AWS_ACCESS_KEY_ID}\"" \
  "export AWS_SECRET_ACCESS_KEY=\"${AWS_SECRET_ACCESS_KEY}\"" \
  "export AWS_DEFAULT_REGION=\"${AWS_DEFAULT_REGION}\"" \
  '' \
  'echo "Uploading to S3: $OUT_PATHS"' \
  "exec /nix/var/nix/profiles/default/bin/nix copy --to \"s3://${INPUT_BUCKET}?endpoint=${INPUT_S3_ENDPOINT}${SECRET_KEY_PARAM}&compression=zstd\" \$OUT_PATHS" \
  | sudo tee /etc/nix/post-build-hook.sh > /dev/null
sudo chmod +x /etc/nix/post-build-hook.sh

# Configure Nix
sudo tee -a "$CONFIG_FILE" > /dev/null << EOF
extra-substituters = s3://${INPUT_BUCKET}?endpoint=${INPUT_S3_ENDPOINT}
extra-trusted-public-keys = ${INPUT_PUBLIC_KEY}
post-build-hook = /etc/nix/post-build-hook.sh
EOF

# Restart nix-daemon
sudo systemctl restart nix-daemon || true