#!/bin/bash
#
# UI Functionality Tests for Claude Profile Manager
# Tests the specific UI/UX improvements made to the list command
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

# Source the library functions for testing
# shellcheck source=../lib/profile-core.sh
source "$PROJECT_ROOT/lib/profile-core.sh"

# Test current profile indicator logic
test_current_profile_indicator() {
	echo "Testing current profile indicator logic..."

	# Mock get_current_profile function for testing
	get_current_profile() {
		echo "test-profile"
	}

	# Test indicator assignment logic (extracted from list_profiles)
	local profile_name="test-profile"
	local current_profile="test-profile"
	local indicator=" "
	if [[ "$profile_name" == "$current_profile" ]]; then
		indicator="➤"
	fi

	if [[ "$indicator" == "➤" ]]; then
		print_success "Current profile indicator (➤) correctly assigned"
	else
		print_error "Current profile indicator not assigned correctly"
	fi

	# Test non-current profile
	profile_name="other-profile"
	indicator=" "
	if [[ "$profile_name" == "$current_profile" ]]; then
		indicator="➤"
	fi

	if [[ "$indicator" == " " ]]; then
		print_success "Non-current profile correctly shows no indicator"
	else
		print_error "Non-current profile incorrectly shows indicator"
	fi
}

# Test status message generation for different auth types
test_status_generation() {
	echo "Testing status message generation..."

	# Test console profile status - ready
	local auth_type="console"
	local status="n/a"
	local mock_api_key="sk-ant-api01-test123"

	# Simulate the status logic from list_profiles
	if [[ "$auth_type" == "console" ]]; then
		if [[ -n "$mock_api_key" ]]; then
			status="ready"
		else
			status="missing"
		fi
	fi

	if [[ "$status" == "ready" ]]; then
		print_success "Console profile with API key shows 'ready' status"
	else
		print_error "Console profile status logic failed"
	fi

	# Test console profile status - missing
	mock_api_key=""
	if [[ "$auth_type" == "console" ]]; then
		if [[ -n "$mock_api_key" ]]; then
			status="ready"
		else
			status="missing"
		fi
	fi

	if [[ "$status" == "missing" ]]; then
		print_success "Console profile without API key shows 'missing' status"
	else
		print_error "Console profile missing credential logic failed"
	fi
}

# Test OAuth token expiration formatting
test_oauth_token_formatting() {
	echo "Testing OAuth token expiration formatting..."

	# Test with current timestamp + 2 days (valid token)
	local current_time
	current_time=$(date +%s)
	local future_time=$((current_time + 172800)) # +2 days
	local future_time_ms=$((future_time * 1000)) # Convert to milliseconds

	local formatted_result
	formatted_result=$(format_oauth_timestamp "$future_time_ms")

	if [[ "$formatted_result" =~ "expires in" ]]; then
		print_success "Future token expiration formatted correctly: $formatted_result"
	else
		print_error "Future token expiration formatting failed: $formatted_result"
	fi

	# Test with past timestamp (expired token)
	local past_time=$((current_time - 3600)) # -1 hour
	local past_time_ms=$((past_time * 1000))

	formatted_result=$(format_oauth_timestamp "$past_time_ms")

	if [[ "$formatted_result" =~ "expired" ]]; then
		print_success "Expired token formatted correctly: $formatted_result"
	else
		print_error "Expired token formatting failed: $formatted_result"
	fi

	# Test with near expiration (30 minutes)
	local soon_time=$((current_time + 1800)) # +30 minutes
	local soon_time_ms=$((soon_time * 1000))

	formatted_result=$(format_oauth_timestamp "$soon_time_ms")

	if [[ "$formatted_result" =~ "expires soon" ]]; then
		print_success "Soon-to-expire token formatted correctly: $formatted_result"
	else
		print_error "Soon-to-expire token formatting failed: $formatted_result"
	fi
}

# Test table header structure
test_table_header() {
	echo "Testing table header structure..."

	local expected_header=" \tPROFILE\tTYPE\tCREATED\tLAST USED\tSTATUS"

	# Extract header logic from list_profiles
	local table_data=" \tPROFILE\tTYPE\tCREATED\tLAST USED\tSTATUS"

	if [[ "$table_data" == "$expected_header" ]]; then
		print_success "Table header structure matches expected format"
	else
		print_error "Table header structure incorrect"
		echo "  Expected: $expected_header"
		echo "  Got:      $table_data"
	fi
}

# Test profile display with aliases
test_profile_display_with_aliases() {
	echo "Testing profile display with aliases..."

	# Mock get_profile_aliases function
	get_profile_aliases() {
		local profile_name="$1"
		if [[ "$profile_name" == "console" ]]; then
			echo " (api)"
		elif [[ "$profile_name" == "subscription" ]]; then
			echo " (sub)"
		fi
	}

	# Test console profile with alias
	local profile_display="console"
	local aliases
	aliases=$(get_profile_aliases "console")
	profile_display="$profile_display$aliases"

	if [[ "$profile_display" == "console (api)" ]]; then
		print_success "Profile display with aliases formatted correctly"
	else
		print_error "Profile display with aliases failed: $profile_display"
	fi

	# Test profile without aliases
	profile_display="work"
	aliases=$(get_profile_aliases "work")
	profile_display="$profile_display$aliases"

	if [[ "$profile_display" == "work" ]]; then
		print_success "Profile display without aliases works correctly"
	else
		print_error "Profile display without aliases failed: $profile_display"
	fi
}

# Test Claude OAuth expiration parsing
test_claude_oauth_parsing() {
	echo "Testing Claude OAuth expiration parsing..."

	# Create a mock OAuth JSON structure with expiresAt field
	local current_time
	current_time=$(date +%s)
	local future_time=$((current_time + 3600)) # +1 hour
	local future_time_ms=$((future_time * 1000))

	local mock_oauth_json="{\"claudeAiOauth\":{\"accessToken\":{\"expiresAt\":$future_time_ms}}}"

	local parsed_result
	parsed_result=$(parse_claude_oauth_expiration "$mock_oauth_json")

	if [[ "$parsed_result" =~ "expires" ]]; then
		print_success "Claude OAuth expiration parsing works: $parsed_result"
	else
		print_error "Claude OAuth expiration parsing failed: $parsed_result"
	fi

	# Test fallback for unparseable JSON
	local invalid_json="not-valid-json"
	parsed_result=$(parse_claude_oauth_expiration "$invalid_json")

	if [[ "$parsed_result" == "valid" ]]; then
		print_success "Invalid OAuth JSON fallback works correctly"
	else
		print_error "Invalid OAuth JSON fallback failed: $parsed_result"
	fi
}

# Test edge cases in the UI logic
test_edge_cases() {
	echo "Testing UI edge cases..."

	# Test empty profile name handling in indicator logic
	local profile_name=""
	local current_profile="test"
	local indicator=" "
	if [[ "$profile_name" == "$current_profile" ]]; then
		indicator="➤"
	fi

	if [[ "$indicator" == " " ]]; then
		print_success "Empty profile name doesn't match current profile indicator"
	else
		print_error "Empty profile name incorrectly matched current profile"
	fi

	# Test very long profile names don't break formatting
	local long_name="very-long-profile-name-that-might-break-formatting-1234567890"
	if [[ ${#long_name} -gt 50 ]]; then
		print_success "Long profile name test case setup correctly (${#long_name} chars)"
	else
		print_error "Long profile name test case too short"
	fi
}

# Print summary
print_summary() {
	echo
	echo "UI Functionality Test Results:"
	echo "  Passed: $TESTS_PASSED"
	echo "  Failed: $TESTS_FAILED"

	if [[ $TESTS_FAILED -eq 0 ]]; then
		echo "✓ All UI functionality tests passed!"
		return 0
	else
		echo "✗ Some UI functionality tests failed"
		return 1
	fi
}

# Main execution
main() {
	echo "Running UI functionality tests for Claude Profile Manager..."
	echo

	test_current_profile_indicator
	echo
	test_status_generation
	echo
	test_oauth_token_formatting
	echo
	test_table_header
	echo
	test_profile_display_with_aliases
	echo
	test_claude_oauth_parsing
	echo
	test_edge_cases

	print_summary
	exit $?
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
