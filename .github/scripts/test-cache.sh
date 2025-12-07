#!/bin/bash
# Comprehensive test script for verifying S3 cache functionality
set -eu

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test configuration
SLEEP_DURATION="${SLEEP_DURATION:-20}"
MAX_CACHE_FETCH_TIME="${MAX_CACHE_FETCH_TIME:-15}"

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
DERIVATION_FILE=$(mktemp --suffix=.nix)
trap 'rm -f "$DERIVATION_FILE"' EXIT

cat >"$DERIVATION_FILE" <<EOF
derivation {
  name = "${DERIVATION_NAME}";
  system = builtins.currentSystem;
  builder = "/bin/sh";
  args = [ "-c" "sleep ${SLEEP_DURATION} && echo test-output > \$out" ];
}
EOF

build_slow_derivation() {
  log_info "Building slow derivation '${DERIVATION_NAME}' (takes ${SLEEP_DURATION}s)..."
  local start_time end_time duration

  start_time=$(date +%s)
  nix build --impure --no-link --print-out-paths --file "$DERIVATION_FILE"
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  log_info "Initial build took ${duration} seconds"
  echo "$duration"
}

get_store_path() {
  nix build --impure --no-link --print-out-paths --file "$DERIVATION_FILE"
}

# Test 1: Build and upload to cache
test_build_and_upload() {
  log_info "=== Test 1: Build and Upload ==="

  build_slow_derivation

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

# Test 4: Clear local store and rebuild from cache (timing test)
test_cache_fetch_timing() {
  log_info "=== Test 4: Cache Fetch Timing Test ==="

  local store_path start_time end_time duration
  store_path=$(get_store_path)

  log_info "Deleting path from local store: ${store_path}"

  # Use nix-store --delete which works better than nix store delete
  # Also need to remove GC roots first
  sudo nix-store --delete "${store_path}" 2>/dev/null || true

  # Double check with nix store gc for this specific path
  sudo nix store gc 2>/dev/null || true

  # Give daemon time to update
  sleep 1

  # Verify it's gone by checking if we can stat it
  if [[ -e "${store_path}" ]]; then
    log_info "Warning: Path still exists, trying harder to remove..."
    # Try to invalidate by removing from database
    sudo nix-store --delete --ignore-liveness "${store_path}" 2>/dev/null || true
  fi

  # Check if the path exists in local store
  if [[ -e "${store_path}" ]]; then
    log_error "Failed to delete path from local store (path still exists on filesystem)"
    return 1
  fi

  log_info "Rebuilding from cache (should be fast)..."
  start_time=$(date +%s)

  # Rebuild - this should fetch from cache
  nix build --impure --no-link --file "$DERIVATION_FILE"

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  log_info "Rebuild took ${duration} seconds (threshold: ${MAX_CACHE_FETCH_TIME}s)"

  if [[ $duration -lt $MAX_CACHE_FETCH_TIME ]]; then
    log_success "Cache fetch successful! Build completed in ${duration}s (< ${MAX_CACHE_FETCH_TIME}s threshold)"
    return 0
  else
    log_error "Build took ${duration}s, which is >= ${MAX_CACHE_FETCH_TIME}s - cache may not be working"
    return 1
  fi
}

# Test 5: Verify copy from cache works
test_nix_copy_from_cache() {
  log_info "=== Test 5: Nix Copy From Cache ==="

  local store_path
  store_path=$(get_store_path)

  # Delete local path first
  sudo nix-store --delete "${store_path}" 2>/dev/null || true

  log_info "Copying from cache: ${store_path}"

  if nix copy --from "${NIX_S3_URL}" "${store_path}" 2>&1; then
    log_success "Successfully copied path from S3 cache"
    return 0
  else
    log_error "Failed to copy path from S3 cache"
    return 1
  fi
}

# Test 6: Count objects in bucket
test_bucket_has_objects() {
  log_info "=== Test 6: Verify Bucket Has Objects ==="

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

  test_cache_fetch_timing || ((failed++))
  echo ""

  test_nix_copy_from_cache || ((failed++))
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
