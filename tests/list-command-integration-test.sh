#!/bin/bash
#
# Integration Tests for List Command UI/UX Changes
# Tests the actual output format of the list command
#

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

print_success() {
	echo "✓ $1"
	TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_error() {
	echo "✗ $1"
	TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Create a temporary test environment
setup_test_env() {
	local test_profile_dir
	test_profile_dir=$(mktemp -d)
	export PROFILE_SETTINGS_DIR="$test_profile_dir"
	echo "$test_profile_dir"
}

# Cleanup test environment
cleanup_test_env() {
	local test_dir="$1"
	if [[ -n "$test_dir" && -d "$test_dir" ]]; then
		rm -rf "$test_dir"
	fi
}

# Create mock profile files for testing
create_mock_profiles() {
	local test_dir="$1"

	# Create a console profile
	cat >"$test_dir/console.json" <<EOF
{
  "created": "2024-08-26T10:00:00Z",
  "auth_method": "console",
  "last_used": "2024-08-27T12:00:00Z"
}
EOF

	# Create a subscription profile
	cat >"$test_dir/subscription.json" <<EOF
{
  "created": "2024-08-27T09:00:00Z",
  "auth_method": "subscription",
  "last_used": "2024-08-27T11:30:00Z"
}
EOF

	# Create aliases file
	cat >"$test_dir/.aliases" <<EOF
api=console
sub=subscription
EOF

	# Set current profile
	echo "subscription" >"$test_dir/.current"

	chmod 600 "$test_dir"/*.json "$test_dir"/.aliases "$test_dir"/.current
}

# Test list command output structure
test_list_output_structure() {
	echo "Testing list command output structure..."

	local test_dir
	test_dir=$(setup_test_env)
	create_mock_profiles "$test_dir"

	# Source the library with our test environment first
	PROFILE_SETTINGS_DIR="$test_dir" source "$PROJECT_ROOT/lib/profile-core.sh"

	# Mock keychain functions to avoid actual keychain access (after sourcing to override)
	keychain_get_password() {
		local profile_name="$1"
		case "$profile_name" in
		"console")
			echo "sk-ant-api01-mock-key"
			;;
		"subscription")
			local current_time
			current_time=$(date +%s)
			local future_time=$((current_time + 7200)) # +2 hours
			local future_time_ms=$((future_time * 1000))
			echo "{\"claudeAiOauth\":{\"accessToken\":{\"expiresAt\":$future_time_ms}}}"
			;;
		*)
			return 1
			;;
		esac
	}

	# Capture the list output
	local list_output
	list_output=$(PROFILE_SETTINGS_DIR="$test_dir" list_profiles 2>/dev/null)

	# Test that output contains header
	if echo "$list_output" | grep -q "Available profiles:"; then
		print_success "List output contains proper header"
	else
		print_error "List output missing header"
	fi

	# Test that output contains column headers
	if echo "$list_output" | grep -q "PROFILE.*TYPE.*CREATED.*LAST USED.*STATUS"; then
		print_success "List output contains column headers"
	else
		print_error "List output missing column headers"
	fi

	# Test that current profile indicator appears
	if echo "$list_output" | grep -q "➤.*subscription"; then
		print_success "Current profile indicator (➤) appears correctly"
	else
		print_error "Current profile indicator missing or incorrect"
	fi

	# Test that aliases are displayed
	if echo "$list_output" | grep -q "console (api)"; then
		print_success "Profile aliases displayed correctly"
	else
		print_error "Profile aliases not displayed"
	fi

	# Test console profile status
	if echo "$list_output" | grep -q "console.*ready"; then
		print_success "Console profile shows 'ready' status"
	else
		print_error "Console profile status incorrect"
	fi

	# Test subscription profile status (should show expiration info)
	if echo "$list_output" | grep -q "subscription.*expires"; then
		print_success "Subscription profile shows expiration status"
	else
		print_error "Subscription profile status missing expiration info"
	fi

	cleanup_test_env "$test_dir"
}

# Test empty profiles scenario
test_empty_profiles_output() {
	echo "Testing empty profiles output..."

	local test_dir
	test_dir=$(setup_test_env)

	# Source the library with empty test environment
	PROFILE_SETTINGS_DIR="$test_dir" source "$PROJECT_ROOT/lib/profile-core.sh"

	local list_output
	list_output=$(PROFILE_SETTINGS_DIR="$test_dir" list_profiles 2>/dev/null)

	if echo "$list_output" | grep -q "No profiles saved"; then
		print_success "Empty profiles list shows appropriate message"
	else
		print_error "Empty profiles list message incorrect"
	fi

	cleanup_test_env "$test_dir"
}

# Test table formatting consistency
test_table_formatting() {
	echo "Testing table formatting consistency..."

	local test_dir
	test_dir=$(setup_test_env)
	create_mock_profiles "$test_dir"

	# Source the library
	PROFILE_SETTINGS_DIR="$test_dir" source "$PROJECT_ROOT/lib/profile-core.sh"

	# Mock keychain functions (after sourcing to override)
	keychain_get_password() {
		return 1 # No credentials found
	}

	local list_output
	list_output=$(PROFILE_SETTINGS_DIR="$test_dir" list_profiles 2>/dev/null)

	# Test that both header and data rows exist
	local header_exists
	header_exists=$(echo "$list_output" | grep -c "PROFILE.*TYPE" || true)

	local data_exists
	data_exists=$(echo "$list_output" | grep -cE "console|subscription" || true)

	if [[ $header_exists -eq 1 && $data_exists -gt 0 ]]; then
		print_success "Table formatting has proper header and data rows"
	else
		print_error "Table formatting missing header or data rows (header: $header_exists, data: $data_exists)"
	fi

	# Test that all rows have proper indentation
	local indented_rows
	indented_rows=$(echo "$list_output" | grep -cE "^\s+[➤ ]")

	if [[ $indented_rows -gt 0 ]]; then
		print_success "Table rows have proper indentation"
	else
		print_error "Table rows missing proper indentation"
	fi

	cleanup_test_env "$test_dir"
}

# Test current profile indicator edge cases
test_current_profile_indicator_edge_cases() {
	echo "Testing current profile indicator edge cases..."

	local test_dir
	test_dir=$(setup_test_env)
	create_mock_profiles "$test_dir"

	# Test with no current profile set
	rm -f "$test_dir/.current"

	# Source the library
	PROFILE_SETTINGS_DIR="$test_dir" source "$PROJECT_ROOT/lib/profile-core.sh"

	# Mock keychain functions (after sourcing to override)
	keychain_get_password() {
		echo "mock-key"
	}

	local list_output
	list_output=$(PROFILE_SETTINGS_DIR="$test_dir" list_profiles 2>/dev/null)

	# Should show no current profile indicators
	local indicator_count
	indicator_count=$(echo "$list_output" | grep -c "➤" || true)

	if [[ $indicator_count -eq 0 ]]; then
		print_success "No current profile indicators when no current profile set"
	else
		print_error "Current profile indicator appeared when no current profile set"
	fi

	cleanup_test_env "$test_dir"
}

# Print summary
print_summary() {
	echo
	echo "List Command Integration Test Results:"
	echo "  Passed: $TESTS_PASSED"
	echo "  Failed: $TESTS_FAILED"

	if [[ $TESTS_FAILED -eq 0 ]]; then
		echo "✓ All list command integration tests passed!"
		return 0
	else
		echo "✗ Some list command integration tests failed"
		return 1
	fi
}

# Main execution
main() {
	echo "Running list command integration tests..."
	echo

	test_list_output_structure
	echo
	test_empty_profiles_output
	echo
	test_table_formatting
	echo
	test_current_profile_indicator_edge_cases

	print_summary
	exit $?
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
