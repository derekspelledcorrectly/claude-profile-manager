#!/bin/bash

# Debug script to isolate the switch_profile issue

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create test environment
TEST_PROFILE_DIR=$(mktemp -d -t "claude-profile-test-XXXXXX")
export PROFILE_SETTINGS_DIR="$TEST_PROFILE_DIR"
export CLAUDE_PROFILE_LOG=""

echo "Test directory: $TEST_PROFILE_DIR"

# Mock functions
mock_keychain_save_password() {
	local account="$1"
	local password="$2"
	local service="${3:-Claude Profile Manager}"
	echo "$password" >"$TEST_PROFILE_DIR/.keychain_${service//[^a-zA-Z0-9]/_}_$account"
	return 0
}

mock_keychain_get_password() {
	local account="$1"
	local service="${2:-Claude Profile Manager}"
	local keychain_file="$TEST_PROFILE_DIR/.keychain_${service//[^a-zA-Z0-9]/_}_$account"
	if [[ -f "$keychain_file" ]]; then
		cat "$keychain_file"
		return 0
	fi
	return 1
}

mock_keychain_delete_password() {
	local account="$1"
	local service="${2:-Claude Profile Manager}"
	local keychain_file="$TEST_PROFILE_DIR/.keychain_${service//[^a-zA-Z0-9]/_}_$account"
	rm -f "$keychain_file"
	return 0
}

# Source the library
source "$PROJECT_ROOT/lib/profile-core.sh"

# Override functions with mocks
keychain_save_password() { mock_keychain_save_password "$@"; }
keychain_get_password() { mock_keychain_get_password "$@"; }
keychain_delete_password() { mock_keychain_delete_password "$@"; }
detect_auth_method() { echo "console"; }
get_claude_console_api_key() { echo "sk-ant-api01-test-key"; }
save_claude_console_api_key() { echo "Mock: Saving console API key: $1"; return 0; }
backup_claude_subscription_credentials() { echo "Mock: Backup subscription credentials"; return 0; }
restore_claude_subscription_credentials() { echo "Mock: Restore subscription credentials"; return 0; }
delete_claude_subscription_backup() { echo "Mock: Delete subscription backup"; return 0; }
secure_temp_file() {
	local temp_file
	temp_file=$(mktemp -t "claude-profile-test-XXXXXXXXXX")
	chmod 600 "$temp_file"
	echo "$temp_file"
}
log_operation() { echo "Mock: Log operation $*"; return 0; }
whoami() { echo "testuser"; }

echo "Creating test profile..."
save_profile "test-work" >/dev/null 2>&1

echo "Profile created. Attempting switch..."
set -x
switch_profile "test-work"
set +x

echo "Switch completed successfully!"

# Cleanup
rm -rf "$TEST_PROFILE_DIR"