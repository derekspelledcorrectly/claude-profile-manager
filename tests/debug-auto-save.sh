#!/bin/bash

# Debug script to test auto-save functionality

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
detect_auth_method() { echo "subscription"; }
get_claude_console_api_key() { echo "sk-ant-api01-test-key"; }
save_claude_console_api_key() { return 0; }
backup_claude_subscription_credentials() {
	mock_keychain_save_password "$1" '{"test": "token"}'
}
restore_claude_subscription_credentials() {
	local creds
	creds=$(mock_keychain_get_password "$1")
	[[ -n "$creds" ]]
}
delete_claude_subscription_backup() { mock_keychain_delete_password "$1"; }
secure_temp_file() {
	local temp_file
	temp_file=$(mktemp -t "claude-profile-test-XXXXXXXXXX")
	chmod 600 "$temp_file"
	echo "$temp_file"
}
log_operation() { return 0; }
whoami() { echo "testuser"; }

echo "Creating test profiles..."
save_profile "source-profile" >/dev/null 2>&1
save_profile "target-profile" >/dev/null 2>&1

echo "Setting current profile to source-profile..."
echo "source-profile" >"$TEST_PROFILE_DIR/.current"

echo "Test 1: save_current_credentials success"
save_current_credentials() {
	echo "Mock: save_current_credentials called successfully"
	return 0
}
export -f save_current_credentials

echo "Running switch_profile..."
set -x
switch_profile "target-profile"
set +x

echo "Test 2: save_current_credentials failure + continue"
save_current_credentials() {
	echo "Mock: save_current_credentials failed"
	return 1
}
confirm_continue_switch() {
	echo "Continue with profile switch anyway? [y/N]: y"
	return 0 # Yes, continue
}
export -f save_current_credentials confirm_continue_switch

echo "source-profile" >"$TEST_PROFILE_DIR/.current"
echo "Running switch_profile with failure + continue..."
set -x
switch_profile "target-profile"
set +x

echo "Test completed successfully!"

# Cleanup
rm -rf "$TEST_PROFILE_DIR"