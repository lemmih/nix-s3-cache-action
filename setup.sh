#!/bin/bash
set -eu

# Check if Nix is installed
if ! command -v nix >/dev/null 2>&1; then
  echo "Error: Nix is not installed. Please install Nix first using DeterminateSystems/nix-installer-action (https://github.com/DeterminateSystems/nix-installer-action)."
  exit 1
fi

# Check if nix-daemon is running (multi-user mode) or not (single-user/root-only mode)
is_daemon_running() {
  pgrep -x "nix-daemon" >/dev/null 2>&1
}

# Wait for nix-daemon socket to appear
wait_for_nix_socket() {
  local socket_path="/nix/var/nix/daemon-socket/socket"
  local max_attempts=120  # 2 minutes at 1 second intervals
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if [ -S "$socket_path" ]; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "Timed out waiting for nix-daemon socket"
  return 1
}

# Start nix-daemon directly as a background process (for environments without systemd)
start_daemon_directly() {
  local daemon_bin="/nix/var/nix/profiles/default/bin/nix-daemon"

  if [ ! -x "$daemon_bin" ]; then
    echo "nix-daemon binary not found at $daemon_bin"
    return 1
  fi

  echo "Starting nix-daemon directly..."

  # Kill any existing daemon first
  sudo pkill -TERM -x "nix-daemon" 2>/dev/null || true
  sleep 1

  # Start the daemon as a detached background process
  # Using nohup to ensure it survives after this script exits
  sudo nohup "$daemon_bin" >/dev/null 2>&1 &

  # Wait for the socket to appear
  if wait_for_nix_socket; then
    echo "nix-daemon started successfully"
    return 0
  else
    return 1
  fi
}

# Function to restart nix-daemon using available init system
restart_nix_daemon() {
  # Try systemctl (Linux with systemd)
  if command -v systemctl >/dev/null 2>&1; then
    if sudo systemctl restart nix-daemon 2>/dev/null; then
      echo "Restarted nix-daemon via systemctl"
      return 0
    fi
  fi

  # Try launchctl (macOS)
  if command -v launchctl >/dev/null 2>&1; then
    # Try common launchd service names
    for service in "systems.determinate.nix-daemon" "org.nixos.nix-daemon"; do
      if sudo launchctl kickstart -k "system/${service}" 2>/dev/null; then
        echo "Restarted nix-daemon via launchctl (${service})"
        return 0
      fi
    done
  fi

  # No init system available - start daemon directly
  # This is common in Docker containers and similar environments
  if start_daemon_directly; then
    return 0
  fi

  # No restart method worked
  return 1
}

# Determine config file
if [ -f /etc/nix/nix.custom.conf ]; then
  CONFIG_FILE="/etc/nix/nix.custom.conf"
else
  CONFIG_FILE="/etc/nix/nix.conf"
fi

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
  sudo mkdir -p /root/.aws
  {
    printf '%s\n' \
      '[default]' \
      "aws_access_key_id = ${AWS_ACCESS_KEY_ID}" \
      "aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}" \
      "region = ${AWS_DEFAULT_REGION}"
    if [ -n "$AWS_SESSION_TOKEN" ]; then
      printf '%s\n' "aws_session_token = ${AWS_SESSION_TOKEN}"
    fi
  } | sudo tee /root/.aws/credentials >/dev/null
  sudo chmod 600 /root/.aws/credentials

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

# Create signing key file if provided
if [ -n "$INPUT_PRIVATE_KEY" ]; then
  sudo tee /etc/nix/cache-priv-key.pem >/dev/null <<<"$INPUT_PRIVATE_KEY"
  sudo chmod 644 /etc/nix/cache-priv-key.pem
  SECRET_KEY_PARAM="&secret-key=/etc/nix/cache-priv-key.pem"
else
  SECRET_KEY_PARAM=""
fi

# Create post-build hook
# shellcheck disable=SC2016 # Single quotes intentional - variables should expand at runtime, not now
{
  printf '%s\n' \
    '#!/bin/bash' \
    'set -eu' \
    'set -o pipefail' \
    '' \
    "export AWS_ACCESS_KEY_ID=\"${AWS_ACCESS_KEY_ID}\"" \
    "export AWS_SECRET_ACCESS_KEY=\"${AWS_SECRET_ACCESS_KEY}\"" \
    "export AWS_DEFAULT_REGION=\"${AWS_DEFAULT_REGION}\""
  if [ -n "$AWS_SESSION_TOKEN" ]; then
    printf '%s\n' "export AWS_SESSION_TOKEN=\"${AWS_SESSION_TOKEN}\""
  fi
  printf '%s\n' \
    '' \
    'echo "Uploading to S3: $OUT_PATHS"' \
    "exec /nix/var/nix/profiles/default/bin/nix copy --to \"s3://${INPUT_BUCKET}?${NIX_S3_PARAMS}${SECRET_KEY_PARAM}&compression=zstd\" \$OUT_PATHS"
} | sudo tee /etc/nix/post-build-hook.sh >/dev/null
sudo chmod +x /etc/nix/post-build-hook.sh

# Configure Nix
# Build the configuration lines
NIX_EXTRA_CONFIG="extra-substituters = s3://${INPUT_BUCKET}?${NIX_S3_PARAMS}
extra-trusted-public-keys = ${INPUT_PUBLIC_KEY}
post-build-hook = /etc/nix/post-build-hook.sh"

# Write config to file
echo "$NIX_EXTRA_CONFIG" | sudo tee -a "$CONFIG_FILE" >/dev/null

# Check if we're running in single-user mode (no daemon) or multi-user mode (with daemon)
if is_daemon_running; then
  # Multi-user mode: need to restart daemon to pick up new config
  if restart_nix_daemon; then
    echo "Nix daemon restarted successfully. Configuration is active."
  else
    # Daemon restart failed - fall back to NIX_CONFIG for substituter settings
    echo "Warning: Could not restart nix-daemon."
    echo "         Configuring substituter via NIX_CONFIG environment variable."

    # Export NIX_CONFIG to GITHUB_ENV so subsequent steps pick up the substituter
    # NIX_CONFIG takes precedence and doesn't require daemon restart for client-side settings
    NIX_CONFIG_VALUE="extra-substituters = s3://${INPUT_BUCKET}?${NIX_S3_PARAMS}
extra-trusted-public-keys = ${INPUT_PUBLIC_KEY}"

    # Append to existing NIX_CONFIG if set
    if [ -n "${NIX_CONFIG:-}" ]; then
      NIX_CONFIG_VALUE="${NIX_CONFIG}
${NIX_CONFIG_VALUE}"
    fi

    # Export to current shell
    export NIX_CONFIG="$NIX_CONFIG_VALUE"

    # Export to GITHUB_ENV for subsequent steps (if running in GitHub Actions)
    if [ -n "${GITHUB_ENV:-}" ]; then
      # Use heredoc delimiter for multi-line value
      {
        echo "NIX_CONFIG<<EOF_NIX_CONFIG"
        echo "$NIX_CONFIG_VALUE"
        echo "EOF_NIX_CONFIG"
      } >> "$GITHUB_ENV"
    fi

    echo "Note: post-build-hook requires nix-daemon restart to take effect."
    echo "      Cache downloads will work, but automatic uploads after builds may not."
  fi
else
  # Single-user mode (no daemon) - common in Docker containers
  # In this mode, Nix reads config directly from nix.conf without needing a daemon restart
  echo "Detected single-user Nix installation (no daemon)."
  echo "Configuration written to ${CONFIG_FILE}. All settings are active."
fi
