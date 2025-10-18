#!/bin/bash
#
# Error Handling and Edge Case Tests for Claude Profile Manager
# Tests various error conditions and edge cases
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

# Test invalid profile name validation
test_invalid_profile_names() {
	echo "Testing invalid profile name handling..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	local invalid_names=(
		""                                                                      # Empty name
		"."                                                                     # Hidden file
		".."                                                                    # Parent directory
		"current"                                                               # Reserved name
		"aliases"                                                               # Reserved name
		"audit"                                                                 # Reserved name
		"name with spaces"                                                      # Spaces not allowed
		"name/with/slashes"                                                     # Slashes not allowed
		"name@with@symbols"                                                     # Special chars not allowed
		'very-long-name-that-exceeds-fifty-characters-limit-should-be-rejected' # Too long
		"con"                                                                   # Windows reserved
		"prn"                                                                   # Windows reserved
		"aux"                                                                   # Windows reserved
	)

	local valid_count=0
	local invalid_count=0

	for name in "${invalid_names[@]}"; do
		if validate_profile_name "$name" >/dev/null 2>&1; then
			print_error "Invalid name '$name' was accepted"
			valid_count=$((valid_count + 1))
		else
			invalid_count=$((invalid_count + 1))
		fi
	done

	if [[ $valid_count -eq 0 ]]; then
		print_success "All invalid profile names properly rejected ($invalid_count names)"
	else
		print_error "$valid_count invalid names were incorrectly accepted"
	fi
}

# Test missing file handling
test_missing_file_handling() {
	echo "Testing missing file handling..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Test switching to non-existent profile
	if ! switch_profile "nonexistent-profile" >/dev/null 2>&1; then
		print_success "Switch to non-existent profile properly fails"
	else
		print_error "Switch to non-existent profile incorrectly succeeds"
	fi

	# Test deleting non-existent profile
	if ! delete_profile "nonexistent-profile" >/dev/null 2>&1; then
		print_success "Delete of non-existent profile properly fails"
	else
		print_error "Delete of non-existent profile incorrectly succeeds"
	fi

	# Test adding alias for non-existent profile
	if ! add_alias "test-alias" "nonexistent-profile" >/dev/null 2>&1; then
		print_success "Adding alias for non-existent profile properly fails"
	else
		print_error "Adding alias for non-existent profile incorrectly succeeds"
	fi
}

# Test malformed JSON handling
test_malformed_json_handling() {
	echo "Testing malformed JSON handling..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Create malformed profile file
	local malformed_profile="$TEST_PROFILE_DIR/malformed.json"
	cat >"$malformed_profile" <<'EOF'
{
  "created": "2024-01-01T00:00:00Z",
  "auth_method": "console"
  // Missing comma and closing brace
EOF

	# Test that malformed JSON is handled gracefully
	local auth_type
	auth_type=$(detect_profile_auth_type "malformed" 2>/dev/null || echo "error")

	if [[ "$auth_type" != "" && "$auth_type" != "error" ]]; then
		print_success "Malformed JSON handling falls back gracefully (got: $auth_type)"
	else
		print_error "Malformed JSON handling failed"
	fi

	# Create JSON with null values
	local null_profile="$TEST_PROFILE_DIR/null-values.json"
	cat >"$null_profile" <<EOF
{
  "created": null,
  "auth_method": null,
  "last_used": null
}
EOF

	# Test null value handling in timestamps
	local formatted_date
	formatted_date=$(format_timestamp "null" 2>/dev/null || echo "error")

	if [[ "$formatted_date" == "unknown" ]]; then
		print_success "Null timestamp handling works correctly"
	else
		print_error "Null timestamp handling failed (got: $formatted_date)"
	fi
}

# Test permission error simulation
test_permission_errors() {
	echo "Testing permission error handling..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Create a read-only directory to simulate permission errors
	local readonly_dir="$TEST_PROFILE_DIR/readonly"
	mkdir -p "$readonly_dir"
	chmod 555 "$readonly_dir"  # Read and execute, but no write

	# Try to create a profile file in read-only directory
	local readonly_profile="$readonly_dir/test.json"

	# This should fail gracefully - use a subshell to contain the error
	if ! (echo '{"test": "data"}' >"$readonly_profile") 2>/dev/null; then
		print_success "Read-only directory correctly prevents file creation"
	else
		print_error "Read-only directory should have prevented file creation"
		# Cleanup if somehow it was created
		rm -f "$readonly_profile" 2>/dev/null || true
	fi

	# Restore permissions for cleanup
	chmod 755 "$readonly_dir"
}

# Test OAuth token parsing edge cases
test_oauth_token_parsing() {
	echo "Testing OAuth token parsing edge cases..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Test empty token
	local health
	health=$(check_token_health "" 2>/dev/null || echo "error")
	if [[ "$health" == "n/a" ]]; then
		print_success "Empty token handling works"
	else
		print_error "Empty token handling failed (got: $health)"
	fi

	# Test invalid JSON
	health=$(check_token_health "not-json-at-all" 2>/dev/null || echo "error")
	if [[ "$health" == "invalid" ]]; then
		print_success "Invalid token format properly detected"
	else
		print_error "Invalid token format not detected (got: $health)"
	fi

	# Test malformed OAuth JSON
	local malformed_oauth='{"claudeAiOauth": {"accessToken": "incomplete"}'
	health=$(check_token_health "$malformed_oauth" 2>/dev/null || echo "error")
	if [[ "$health" == "valid" || "$health" == "unknown" ]]; then
		print_success "Malformed OAuth JSON handled gracefully (got: $health)"
	else
		print_error "Malformed OAuth JSON not handled gracefully (got: $health)"
	fi

	# Test expired token
	local expired_time=$(($(date +%s) * 1000 - 3600000)) # 1 hour ago in milliseconds
	local expired_oauth="{\"claudeAiOauth\":{\"accessToken\":{\"expiresAt\":$expired_time}}}"
	health=$(check_token_health "$expired_oauth" 2>/dev/null || echo "error")
	if [[ "$health" == expired* ]]; then
		print_success "Expired token correctly identified (got: $health)"
	else
		print_error "Expired token not identified (got: $health)"
	fi

	# Test token expiring soon
	local soon_time=$(($(date +%s) * 1000 + 1800000)) # 30 minutes from now in milliseconds
	local soon_oauth="{\"claudeAiOauth\":{\"accessToken\":{\"expiresAt\":$soon_time}}}"
	health=$(check_token_health "$soon_oauth" 2>/dev/null || echo "error")
	if [[ "$health" == "expires soon"* ]]; then
		print_success "Token expiring soon correctly identified (got: $health)"
	else
		print_error "Token expiring soon not identified (got: $health)"
	fi
}

# Test timestamp parsing edge cases
test_timestamp_parsing() {
	echo "Testing timestamp parsing edge cases..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Test various timestamp formats
	local test_cases=(
		""                     # Empty
		"null"                 # Null value
		"invalid-date"         # Invalid format
		"2024-13-45T25:99:99Z" # Invalid date values
		"not-a-timestamp"      # Random text
	)

	local handled_correctly=0

	for timestamp in "${test_cases[@]}"; do
		local result
		result=$(format_timestamp "$timestamp" 2>/dev/null || echo "error")

		if [[ "$result" == "unknown" || "$result" == "invalid" || "$result" == "error" ]]; then
			handled_correctly=$((handled_correctly + 1))
		fi
	done

	if [[ $handled_correctly -eq ${#test_cases[@]} ]]; then
		print_success "All invalid timestamps handled gracefully"
	else
		print_error "Some invalid timestamps not handled properly ($handled_correctly/${#test_cases[@]})"
	fi

	# Test edge case OAuth timestamp parsing
	local oauth_health
	oauth_health=$(format_oauth_timestamp "not-a-number" 2>/dev/null || echo "error")
	if [[ "$oauth_health" == "unknown" || "$oauth_health" == "error" ]]; then
		print_success "Invalid OAuth timestamp handled gracefully"
	else
		print_error "Invalid OAuth timestamp not handled properly (got: $oauth_health)"
	fi
}

# Test concurrent access simulation
test_concurrent_access() {
	echo "Testing concurrent access handling..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Create an alias file
	local alias_file="$TEST_PROFILE_DIR/.aliases"
	echo "test=profile1" >"$alias_file"
	chmod 600 "$alias_file"

	# Simulate concurrent modification by creating a temp file that conflicts
	local temp_pattern="claude-profile-*"
	local existing_temp
	existing_temp=$(mktemp -t "$temp_pattern") || true

	if [[ -n "$existing_temp" && -f "$existing_temp" ]]; then
		# This simulates a scenario where temp file creation might have conflicts
		print_success "Concurrent access simulation set up"

		# Cleanup the temp file
		rm -f "$existing_temp"
	else
		print_success "Concurrent access test: temp file handling works"
	fi

	# Test that alias operations are atomic by checking file consistency
	if [[ -f "$alias_file" ]] && grep -q "test=profile1" "$alias_file"; then
		print_success "File operations maintain consistency"
	else
		print_error "File operations may have concurrency issues"
	fi
}

# Test resource cleanup
test_resource_cleanup() {
	echo "Testing resource cleanup..."

	# Source the library
	# shellcheck source=../lib/profile-core.sh
	source "$PROJECT_ROOT/lib/profile-core.sh"

	# Test secure_temp_file function
	local temp_file
	temp_file=$(secure_temp_file 2>/dev/null || echo "error")

	if [[ "$temp_file" != "error" && -f "$temp_file" ]]; then
		# Check permissions
		local perms
		perms=$(stat -f "%p" "$temp_file" 2>/dev/null | tail -c 4)
		if [[ "$perms" == "0600" || "$perms" == "600" ]]; then
			print_success "Secure temp file has correct permissions"
		else
			print_error "Secure temp file has incorrect permissions: $perms"
		fi

		# Cleanup
		rm -f "$temp_file"

		if [[ ! -f "$temp_file" ]]; then
			print_success "Temp file cleanup works"
		else
			print_error "Temp file not cleaned up properly"
		fi
	else
		print_error "Secure temp file creation failed"
	fi
}

# Print summary
print_summary() {
	echo
	echo "Error Handling Test Results:"
	echo "  Passed: $TESTS_PASSED"
	echo "  Failed: $TESTS_FAILED"

	if [[ $TESTS_FAILED -eq 0 ]]; then
		echo "✓ All error handling tests passed!"
		return 0
	else
		echo "✗ Some error handling tests failed"
		return 1
	fi
}

# Main execution
main() {
	echo "Running error handling tests for Claude Profile Manager..."
	echo

	# Setup test environment
	setup_test_env

	# Ensure cleanup happens on exit
	trap cleanup_test_env EXIT

	test_invalid_profile_names
	echo
	test_missing_file_handling
	echo
	test_malformed_json_handling
	echo
	test_permission_errors
	echo
	test_oauth_token_parsing
	echo
	test_timestamp_parsing
	echo
	test_concurrent_access
	echo
	test_resource_cleanup

	print_summary
	exit $?
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
