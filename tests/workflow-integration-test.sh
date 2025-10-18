#!/bin/bash
#
# Workflow Integration Tests for Claude Profile Manager
# Tests real-world usage workflows and end-to-end functionality
#

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test environment setup
TEST_PROFILE_DIR=""
ORIGINAL_PROFILE_DIR=""

print_success() {
	echo "✓ $1"
	TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_error() {
	echo "✗ $1"
	TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Setup test environment with isolated profile directory
setup_test_env() {
	# Create temporary directory for testing
	TEST_PROFILE_DIR=$(mktemp -d -t "claude-profile-test-XXXXXX")

	# Store original value and override
	ORIGINAL_PROFILE_DIR="${PROFILE_SETTINGS_DIR:-$HOME/.claude/profiles}"
	export PROFILE_SETTINGS_DIR="$TEST_PROFILE_DIR"

	# Create test directory structure
	mkdir -p "$TEST_PROFILE_DIR"
	chmod 700 "$TEST_PROFILE_DIR"

	# Disable audit logging for tests
	export CLAUDE_PROFILE_LOG=""
}

# Cleanup test environment
cleanup_test_env() {
	if [[ -n "$TEST_PROFILE_DIR" && -d "$TEST_PROFILE_DIR" ]]; then
		rm -rf "$TEST_PROFILE_DIR"
	fi

	# Restore original directory
	if [[ -n "$ORIGINAL_PROFILE_DIR" ]]; then
		export PROFILE_SETTINGS_DIR="$ORIGINAL_PROFILE_DIR"
	fi
}

# Mock keychain functions for testing
mock_keychain_save_password() {
	local account="$1"
	local password="$2"
	local service="${3:-Claude Profile Manager}"

	# Store in test file instead of keychain
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

# Mock authentication functions
mock_detect_auth_method() {
	echo "${TEST_AUTH_METHOD:-console}"
}

mock_get_claude_console_api_key() {
	echo "${TEST_API_KEY:-sk-ant-api01-test-console-key-123456789012345678901234567890123456789012345678901234567890}"
}

mock_get_claude_subscription_token() {
	echo "${TEST_OAUTH_TOKEN:-{\"claudeAiOauth\":{\"accessToken\":{\"token\":\"test-token\",\"expiresAt\":$(($(date +%s) * 1000 + 3600000))}}}}"
}

# Test: Create → List → Switch → Delete workflow
test_basic_profile_workflow() {
	echo "Testing basic profile workflow (create → list → switch → delete)..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Override functions with mocks
	keychain_save_password() { mock_keychain_save_password "$@"; }
	keychain_get_password() { mock_keychain_get_password "$@"; }
	keychain_delete_password() { mock_keychain_delete_password "$@"; }
	detect_auth_method() { mock_detect_auth_method; }
	get_claude_console_api_key() { mock_get_claude_console_api_key; }
	save_claude_console_api_key() { mock_keychain_save_password "${USER:-testuser}" "$1" "Claude Code"; }
	backup_claude_subscription_credentials() {
		mock_keychain_save_password "$1" "$(mock_get_claude_subscription_token)"
	}
	restore_claude_subscription_credentials() {
		local creds
		creds=$(mock_keychain_get_password "$1")
		if [[ -n "$creds" ]]; then
			mock_keychain_save_password "${USER:-testuser}" "$creds" "Claude Code-credentials"
			return 0
		fi
		return 1
	}
	delete_claude_subscription_backup() { mock_keychain_delete_password "$1"; }

	# Step 1: Create a work profile
	TEST_AUTH_METHOD="console"
	TEST_API_KEY="sk-ant-api01-work-key-123456789012345678901234567890123456789012345678901234567890123456"

	if save_profile "work" >/dev/null 2>&1; then
		print_success "Step 1: Work profile created successfully"

		# Verify profile file exists
		if [[ -f "$TEST_PROFILE_DIR/work.json" ]]; then
			print_success "Step 1a: Work profile file created"
		else
			print_error "Step 1a: Work profile file not created"
		fi
	else
		print_error "Step 1: Work profile creation failed"
		return 1
	fi

	# Step 2: Create a personal profile with different auth method
	TEST_AUTH_METHOD="subscription"
	TEST_OAUTH_TOKEN='{"claudeAiOauth":{"accessToken":{"token":"personal-token","expiresAt":'"$(($(date +%s) * 1000 + 7200000))"'}}}'

	if save_profile "personal" >/dev/null 2>&1; then
		print_success "Step 2: Personal profile created successfully"
	else
		print_error "Step 2: Personal profile creation failed"
		return 1
	fi

	# Step 3: List profiles and verify both exist
	local list_output
	list_output=$(list_profiles 2>/dev/null)

	if echo "$list_output" | grep -q "work" && echo "$list_output" | grep -q "personal"; then
		print_success "Step 3: Both profiles appear in list"
	else
		print_error "Step 3: Profiles missing from list output"
	fi

	# Verify auth types in list
	if echo "$list_output" | grep "work" | grep -q "console"; then
		print_success "Step 3a: Work profile shows console auth type"
	else
		print_error "Step 3a: Work profile auth type incorrect"
	fi

	if echo "$list_output" | grep "personal" | grep -q "subscription"; then
		print_success "Step 3b: Personal profile shows subscription auth type"
	else
		print_error "Step 3b: Personal profile auth type incorrect"
	fi

	# Step 4: Switch to work profile
	if switch_profile "work" >/dev/null 2>&1; then
		print_success "Step 4: Switch to work profile succeeded"

		# Verify current profile is set
		local current_profile
		current_profile=$(get_current_profile)
		if [[ "$current_profile" == "work" ]]; then
			print_success "Step 4a: Current profile correctly set to work"
		else
			print_error "Step 4a: Current profile not set correctly (got: $current_profile)"
		fi
	else
		print_error "Step 4: Switch to work profile failed"
	fi

	# Step 5: Switch to personal profile
	if switch_profile "personal" >/dev/null 2>&1; then
		print_success "Step 5: Switch to personal profile succeeded"

		local current_profile
		current_profile=$(get_current_profile)
		if [[ "$current_profile" == "personal" ]]; then
			print_success "Step 5a: Current profile correctly set to personal"
		else
			print_error "Step 5a: Current profile not set correctly (got: $current_profile)"
		fi
	else
		print_error "Step 5: Switch to personal profile failed"
	fi

	# Step 6: Delete work profile
	if delete_profile "work" >/dev/null 2>&1; then
		print_success "Step 6: Work profile deleted successfully"

		# Verify profile file is gone
		if [[ ! -f "$TEST_PROFILE_DIR/work.json" ]]; then
			print_success "Step 6a: Work profile file removed"
		else
			print_error "Step 6a: Work profile file not removed"
		fi
	else
		print_error "Step 6: Work profile deletion failed"
	fi

	# Step 7: Verify work profile no longer in list
	list_output=$(list_profiles 2>/dev/null)
	if ! echo "$list_output" | grep -q "work"; then
		print_success "Step 7: Work profile no longer in list"
	else
		print_error "Step 7: Work profile still appears in list"
	fi
}

# Test: Profile creation with aliases workflow
test_profile_with_aliases_workflow() {
	echo "Testing profile creation with aliases workflow..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Override functions with mocks (simplified for aliases test)
	keychain_save_password() { mock_keychain_save_password "$@"; }
	keychain_get_password() { mock_keychain_get_password "$@"; }
	detect_auth_method() { echo "console"; }
	get_claude_console_api_key() { echo "sk-ant-api01-test-key-123456789012345678901234567890123456789012345678901234567890123456"; }
	backup_claude_subscription_credentials() { return 0; }

	# Step 1: Create profile with aliases
	if save_profile "development" "dev" "d" >/dev/null 2>&1; then
		print_success "Step 1: Profile with aliases created"

		# Verify alias file exists and contains correct mappings
		local alias_file="$TEST_PROFILE_DIR/.aliases"
		if [[ -f "$alias_file" ]]; then
			print_success "Step 1a: Alias file created"

			if grep -q "dev=development" "$alias_file" && grep -q "d=development" "$alias_file"; then
				print_success "Step 1b: Aliases correctly saved"
			else
				print_error "Step 1b: Aliases not saved correctly"
			fi
		else
			print_error "Step 1a: Alias file not created"
		fi
	else
		print_error "Step 1: Profile with aliases creation failed"
		return 1
	fi

	# Step 2: Test alias resolution
	local resolved
	resolved=$(resolve_profile_alias "dev")
	if [[ "$resolved" == "development" ]]; then
		print_success "Step 2: Short alias 'dev' resolves correctly"
	else
		print_error "Step 2: Short alias 'dev' resolution failed (got: $resolved)"
	fi

	resolved=$(resolve_profile_alias "d")
	if [[ "$resolved" == "development" ]]; then
		print_success "Step 2a: Single char alias 'd' resolves correctly"
	else
		print_error "Step 2a: Single char alias 'd' resolution failed (got: $resolved)"
	fi

	# Step 3: List profiles should show aliases
	local list_output
	list_output=$(list_profiles 2>/dev/null)

	if echo "$list_output" | grep "development" | grep -q "(dev, d)"; then
		print_success "Step 3: Profile list shows aliases correctly"
	else
		print_error "Step 3: Profile list doesn't show aliases correctly"
	fi

	# Step 4: Add additional alias
	if add_alias "work" "development" >/dev/null 2>&1; then
		print_success "Step 4: Additional alias added"

		# Verify new alias works
		resolved=$(resolve_profile_alias "work")
		if [[ "$resolved" == "development" ]]; then
			print_success "Step 4a: New alias resolves correctly"
		else
			print_error "Step 4a: New alias resolution failed"
		fi
	else
		print_error "Step 4: Additional alias addition failed"
	fi

	# Step 5: Remove an alias
	if remove_alias "d" >/dev/null 2>&1; then
		print_success "Step 5: Alias removal succeeded"

		# Verify alias no longer resolves
		resolved=$(resolve_profile_alias "d")
		if [[ "$resolved" == "d" ]]; then # Should return original name when not found
			print_success "Step 5a: Removed alias no longer resolves"
		else
			print_error "Step 5a: Removed alias still resolves (got: $resolved)"
		fi
	else
		print_error "Step 5: Alias removal failed"
	fi
}

# Test: Current profile tracking workflow
test_current_profile_tracking() {
	echo "Testing current profile tracking workflow..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Override functions with mocks
	keychain_save_password() { mock_keychain_save_password "$@"; }
	keychain_get_password() { mock_keychain_get_password "$@"; }
	keychain_delete_password() { mock_keychain_delete_password "$@"; }
	detect_auth_method() { echo "console"; }
	get_claude_console_api_key() { echo "sk-ant-api01-test-key"; }
	save_claude_console_api_key() { return 0; }
	backup_claude_subscription_credentials() { return 0; }

	# Step 1: Check current profile when none exists
	local current_profile
	current_profile=$(get_current_profile)

	if [[ "$current_profile" =~ ^\(.*\)$ ]]; then # Should be in parentheses like "(unnamed console)"
		print_success "Step 1: No current profile correctly reported"
	else
		print_error "Step 1: No current profile reporting failed (got: $current_profile)"
	fi

	# Step 2: Create and switch to profile
	save_profile "test1" >/dev/null 2>&1
	switch_profile "test1" >/dev/null 2>&1

	current_profile=$(get_current_profile)
	if [[ "$current_profile" == "test1" ]]; then
		print_success "Step 2: Current profile tracking after switch"
	else
		print_error "Step 2: Current profile tracking failed (got: $current_profile)"
	fi

	# Step 3: Create second profile and switch
	save_profile "test2" >/dev/null 2>&1
	switch_profile "test2" >/dev/null 2>&1

	current_profile=$(get_current_profile)
	if [[ "$current_profile" == "test2" ]]; then
		print_success "Step 3: Current profile updates correctly"
	else
		print_error "Step 3: Current profile update failed (got: $current_profile)"
	fi

	# Step 4: Test current profile indicator in list
	local list_output
	list_output=$(list_profiles 2>/dev/null)

	if echo "$list_output" | grep "test2" | grep -q "➤"; then
		print_success "Step 4: Current profile indicator shown in list"
	else
		print_error "Step 4: Current profile indicator missing from list"
	fi

	# Step 5: Delete current profile
	delete_profile "test2" >/dev/null 2>&1

	# Current profile should be cleared
	if [[ ! -f "$TEST_PROFILE_DIR/.current" ]]; then
		print_success "Step 5: Current profile cleared when deleted"
	else
		print_error "Step 5: Current profile not cleared when deleted"
	fi
}

# Test: Save without arguments (current profile) workflow
test_save_current_profile_workflow() {
	echo "Testing save current profile workflow..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Override functions with mocks
	keychain_save_password() { mock_keychain_save_password "$@"; }
	keychain_get_password() { mock_keychain_get_password "$@"; }
	detect_auth_method() { echo "console"; }
	get_claude_console_api_key() { echo "sk-ant-api01-updated-key"; }
	backup_claude_subscription_credentials() { return 0; }

	# Step 1: Create initial profile and set as current
	save_profile "current-test" >/dev/null 2>&1
	echo "current-test" >"$TEST_PROFILE_DIR/.current"

	# Step 2: Save without profile name (should update current)
	# Note: This requires user interaction, so we'll test the logic directly

	# Verify current profile exists
	local current_file="$TEST_PROFILE_DIR/.current"
	if [[ -f "$current_file" ]] && [[ "$(cat "$current_file")" == "current-test" ]]; then
		print_success "Step 1: Current profile setup correctly"
	else
		print_error "Step 1: Current profile setup failed"
		return 1
	fi

	# Test the save logic when no profile name is provided
	# We can't test the interactive part, but we can test the detection
	local profile_file="$TEST_PROFILE_DIR/current-test.json"
	if [[ -f "$profile_file" ]]; then
		local created_time
		created_time=$(jq -r '.created' "$profile_file" 2>/dev/null)

		if [[ -n "$created_time" && "$created_time" != "null" ]]; then
			print_success "Step 2: Current profile file exists and is valid"
		else
			print_error "Step 2: Current profile file is invalid"
		fi
	else
		print_error "Step 2: Current profile file missing"
	fi
}

# Test: Mixed authentication types workflow
test_mixed_auth_types_workflow() {
	echo "Testing mixed authentication types workflow..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Override functions with mocks
	keychain_save_password() { mock_keychain_save_password "$@"; }
	keychain_get_password() { mock_keychain_get_password "$@"; }
	keychain_delete_password() { mock_keychain_delete_password "$@"; }
	detect_auth_method() { mock_detect_auth_method; }
	get_claude_console_api_key() { mock_get_claude_console_api_key; }
	save_claude_console_api_key() { return 0; }
	backup_claude_subscription_credentials() {
		mock_keychain_save_password "$1" "$(mock_get_claude_subscription_token)"
	}
	restore_claude_subscription_credentials() {
		local creds
		creds=$(mock_keychain_get_password "$1")
		[[ -n "$creds" ]]
	}

	# Step 1: Create console profile
	TEST_AUTH_METHOD="console"
	save_profile "console-profile" >/dev/null 2>&1

	# Step 2: Create subscription profile
	TEST_AUTH_METHOD="subscription"
	save_profile "subscription-profile" >/dev/null 2>&1

	# Step 3: List profiles and verify different auth types
	local list_output
	list_output=$(list_profiles 2>/dev/null)

	if echo "$list_output" | grep "console-profile" | grep -q "console"; then
		print_success "Step 1: Console profile type correctly displayed"
	else
		print_error "Step 1: Console profile type incorrect"
	fi

	if echo "$list_output" | grep "subscription-profile" | grep -q "subscription"; then
		print_success "Step 2: Subscription profile type correctly displayed"
	else
		print_error "Step 2: Subscription profile type incorrect"
	fi

	# Step 4: Test switching between different auth types
	if switch_profile "console-profile" >/dev/null 2>&1; then
		print_success "Step 3: Switch to console profile succeeded"
	else
		print_error "Step 3: Switch to console profile failed"
	fi

	if switch_profile "subscription-profile" >/dev/null 2>&1; then
		print_success "Step 4: Switch to subscription profile succeeded"
	else
		print_error "Step 4: Switch to subscription profile failed"
	fi
}

# Test: Auto-save functionality during profile switching
test_auto_save_functionality() {
	echo "Testing auto-save functionality during profile switching..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Override functions with mocks
	keychain_save_password() { mock_keychain_save_password "$@"; }
	keychain_get_password() { mock_keychain_get_password "$@"; }
	keychain_delete_password() { mock_keychain_delete_password "$@"; }
	detect_auth_method() { echo "subscription"; }
	get_claude_console_api_key() { mock_get_claude_console_api_key; }
	save_claude_console_api_key() { return 0; }
	backup_claude_subscription_credentials() {
		mock_keychain_save_password "$1" "$(mock_get_claude_subscription_token)"
	}
	restore_claude_subscription_credentials() {
		local creds
		creds=$(mock_keychain_get_password "$1")
		[[ -n "$creds" ]]
	}
	delete_claude_subscription_backup() { mock_keychain_delete_password "$1"; }

	# Create test profiles (no overwrite prompts expected for new profiles)
	save_profile "source-profile" >/dev/null 2>&1
	save_profile "target-profile" >/dev/null 2>&1

	# Set current profile to source-profile
	echo "source-profile" >"$TEST_PROFILE_DIR/.current"

	# Test 1: Auto-save success (should proceed silently)
	save_current_credentials() { return 0; } # Mock success
	export -f save_current_credentials

	local switch_output
	switch_output=$(switch_profile "target-profile" 2>&1)
	local switch_result=$?

	if [[ $switch_result -eq 0 ]]; then
		print_success "Step 1: Auto-save success allows switch to proceed"
	else
		print_error "Step 1: Auto-save success should allow switch"
	fi

	if echo "$switch_output" | grep -q "Auto-saving current subscription credentials"; then
		print_success "Step 1a: Shows auto-save message"
	else
		print_error "Step 1a: Missing auto-save message"
	fi

	if ! echo "$switch_output" | grep -q "Continue with profile switch anyway"; then
		print_success "Step 1b: No confirmation prompt on success"
	else
		print_error "Step 1b: Unexpected confirmation prompt on success"
	fi

	# Test 2: Auto-save failure with user choosing to continue
	save_current_credentials() { return 1; } # Mock failure
	export -f save_current_credentials

	# Reset current profile
	echo "source-profile" >"$TEST_PROFILE_DIR/.current"

	# Override confirm_continue_switch to return "yes" (continue)
	confirm_continue_switch() {
		echo "Continue with profile switch anyway? [y/N]: y"
		return 0 # Yes, continue
	}

	switch_output=$(switch_profile "target-profile" 2>&1)
	switch_result=$?

	if [[ $switch_result -eq 0 ]]; then
		print_success "Step 2: Auto-save failure with 'y' allows switch to proceed"
	else
		print_error "Step 2: Auto-save failure with 'y' should allow switch"
	fi

	if echo "$switch_output" | grep -q "Failed to save credentials"; then
		print_success "Step 2a: Shows save failure message"
	else
		print_error "Step 2a: Missing save failure message"
	fi

	if echo "$switch_output" | grep -q "Continue with profile switch anyway"; then
		print_success "Step 2b: Shows confirmation prompt on failure"
	else
		print_error "Step 2b: Missing confirmation prompt on failure"
	fi

	# Test 3: Auto-save failure with user choosing to cancel
	echo "source-profile" >"$TEST_PROFILE_DIR/.current"

	# Override confirm_continue_switch to return "no" (cancel)
	confirm_continue_switch() {
		echo "Continue with profile switch anyway? [y/N]: n"
		return 1 # No, cancel
	}

	switch_output=$(switch_profile "target-profile" 2>&1)
	switch_result=$?

	if [[ $switch_result -eq 1 ]]; then
		print_success "Step 3: Auto-save failure with 'n' cancels switch"
	else
		print_error "Step 3: Auto-save failure with 'n' should cancel switch"
	fi

	if echo "$switch_output" | grep -q "Profile switch cancelled"; then
		print_success "Step 3a: Shows cancellation message"
	else
		print_error "Step 3a: Missing cancellation message"
	fi

	if echo "$switch_output" | grep -q "Current profile is 'source-profile'"; then
		print_success "Step 3b: Shows current profile after cancellation"
	else
		print_error "Step 3b: Missing current profile information"
	fi

	# Test 4: Verify current profile is unchanged after cancellation
	local current_profile
	current_profile=$(get_current_profile)
	if [[ "$current_profile" == "source-profile" ]]; then
		print_success "Step 4: Current profile unchanged after cancellation"
	else
		print_error "Step 4: Current profile incorrectly changed after cancellation"
	fi
}

# Print summary
print_summary() {
	echo
	echo "Workflow Integration Test Results:"
	echo "  Passed: $TESTS_PASSED"
	echo "  Failed: $TESTS_FAILED"

	if [[ $TESTS_FAILED -eq 0 ]]; then
		echo "✓ All workflow integration tests passed!"
		return 0
	else
		echo "✗ Some workflow integration tests failed"
		return 1
	fi
}

# Main execution
main() {
	echo "Running workflow integration tests for Claude Profile Manager..."
	echo

	# Setup test environment
	setup_test_env

	# Ensure cleanup happens on exit
	trap cleanup_test_env EXIT

	test_basic_profile_workflow
	echo
	test_profile_with_aliases_workflow
	echo
	test_current_profile_tracking
	echo
	test_save_current_profile_workflow
	echo
	test_mixed_auth_types_workflow
	echo
	test_auto_save_functionality

	print_summary
	exit $?
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
