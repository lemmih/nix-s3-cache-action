#!/bin/bash
# Comprehensive test script for verifying S3 cache functionality
set -eu

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
  echo -e "${RED}[FAIL]${NC} $1"
}

# Parse arguments
S3_ENDPOINT=""
BUCKET=""
RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --endpoint)
      S3_ENDPOINT="$2"
      shift 2
      ;;
    --bucket)
      BUCKET="$2"
      shift 2
      ;;
    --run-id)
      RUN_ID="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$S3_ENDPOINT" ]] || [[ -z "$BUCKET" ]]; then
  echo "Usage: $0 --endpoint <s3-endpoint> --bucket <bucket-name> [--run-id <unique-id>]"
  exit 1
fi

# Build S3 URL for nix commands
# For AWS, we need to include the region
AWS_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}"
if [[ "$S3_ENDPOINT" == "s3.amazonaws.com" || "$S3_ENDPOINT" == s3.*.amazonaws.com ]]; then
  NIX_S3_URL="s3://${BUCKET}?region=${AWS_REGION}"
  AWS_ENDPOINT_ARG=""
else
  NIX_S3_URL="s3://${BUCKET}?endpoint=${S3_ENDPOINT}"
  AWS_ENDPOINT_ARG="--endpoint-url https://${S3_ENDPOINT}"
fi

# Create a unique slow derivation that won't be in any cache
DERIVATION_NAME="nix-s3-cache-test-${RUN_ID}"

# Write a temporary nix file for the derivation to avoid shell quoting issues
# BSD mktemp has no --suffix option, so put the file in a temporary directory.
DERIVATION_DIR=$(mktemp -d)
DERIVATION_FILE="$DERIVATION_DIR/test.nix"
trap 'rm -rf "$DERIVATION_DIR"' EXIT

# Create a simple unique derivation
cat >"$DERIVATION_FILE" <<EOF
let
  pkgs = import <nixpkgs> {};
in
pkgs.runCommand "${DERIVATION_NAME}" {} ''
  echo "test-output-${RUN_ID}" > \$out
''
EOF

build_derivation() {
  log_info "Building test derivation '${DERIVATION_NAME}'..."
  nix-build --no-out-link "$DERIVATION_FILE"
}

get_store_path() {
  nix-build --no-out-link "$DERIVATION_FILE"
}

# Test 1: Build and upload to cache
test_build_and_upload() {
  log_info "=== Test 1: Build and Upload ==="

  build_derivation

  # Wait for post-build hook to complete upload
  log_info "Waiting for upload to complete..."
  sleep 5

  STORE_PATH=$(get_store_path)
  log_info "Store path: ${STORE_PATH}"
}

# Test 2: Verify narinfo exists in S3
test_narinfo_exists() {
  log_info "=== Test 2: Verify Narinfo Exists in S3 ==="

  local store_path hash narinfo_path
  store_path=$(get_store_path)
  # Extract hash from store path (format: /nix/store/<hash>-<name>)
  hash=$(basename "$store_path" | cut -d'-' -f1)
  narinfo_path="${hash}.narinfo"

  log_info "Looking for narinfo: ${narinfo_path}"

  # shellcheck disable=SC2086 # Word splitting is intentional for AWS_ENDPOINT_ARG
  if aws s3 ls "s3://${BUCKET}/${narinfo_path}" $AWS_ENDPOINT_ARG >/dev/null 2>&1; then
    log_success "Narinfo file exists in S3 bucket"
    return 0
  else
    log_error "Narinfo file not found in S3 bucket"
    return 1
  fi
}

# Test 3: Verify cache is queryable via nix path-info
test_cache_queryable() {
  log_info "=== Test 3: Verify Cache is Queryable ==="

  local store_path
  store_path=$(get_store_path)

  log_info "Querying cache for path: ${store_path}"

  if nix path-info --store "${NIX_S3_URL}" "${store_path}" 2>/dev/null; then
    log_success "Path is queryable from S3 cache"
    return 0
  else
    log_error "Path is NOT queryable from S3 cache"
    return 1
  fi
}

# Test 4: Count objects in bucket
test_bucket_has_objects() {
  log_info "=== Test 4: Verify Bucket Has Objects ==="

  local object_count
  # shellcheck disable=SC2086 # Word splitting is intentional for AWS_ENDPOINT_ARG
  object_count=$(aws s3 ls "s3://${BUCKET}/" $AWS_ENDPOINT_ARG --recursive | wc -l)

  log_info "Found ${object_count} objects in bucket"

  if [[ "$object_count" -gt 0 ]]; then
    log_success "Bucket contains ${object_count} objects"
    return 0
  else
    log_error "Bucket is empty!"
    return 1
  fi
}

# Main test runner
main() {
  local failed=0

  echo ""
  echo "======================================"
  echo "  Nix S3 Cache Test Suite"
  echo "======================================"
  echo ""
  log_info "Endpoint: ${S3_ENDPOINT}"
  log_info "Bucket: ${BUCKET}"
  log_info "Run ID: ${RUN_ID}"
  log_info "S3 URL: ${NIX_S3_URL}"
  echo ""

  # Run tests
  test_build_and_upload || ((failed++))
  echo ""

  test_narinfo_exists || ((failed++))
  echo ""

  test_cache_queryable || ((failed++))
  echo ""

  test_bucket_has_objects || ((failed++))
  echo ""

  # Summary
  echo "======================================"
  if [[ $failed -eq 0 ]]; then
    log_success "All tests passed!"
    exit 0
  else
    log_error "${failed} test(s) failed"
    exit 1
  fi
}

main
