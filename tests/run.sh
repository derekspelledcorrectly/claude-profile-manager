#!/bin/bash
#
# Test Runner for Claude Profile Manager
# Makes test files executable and runs all tests
#

set -euo pipefail

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

print_header() {
	echo -e "${YELLOW}$1${NC}"
	printf '%.0s=' {1..50}
}

print_success() {
	echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
	echo -e "${RED}✗ $1${NC}"
}

run_test_suite() {
	local test_file="$1"
	local test_name="$2"

	echo
	print_header "Running $test_name"

	if [[ -x "$test_file" ]]; then
		if "$test_file"; then
			print_success "$test_name completed"
			PASSED_TESTS=$((PASSED_TESTS + 1))
			return 0
		else
			print_error "$test_name failed"
			FAILED_TESTS=$((FAILED_TESTS + 1))
			return 1
		fi
	else
		print_error "$test_name - file not executable: $test_file"
		FAILED_TESTS=$((FAILED_TESTS + 1))
		return 1
	fi
}

print_final_summary() {
	echo
	printf '%.0s=' {1..60}
	echo "FINAL TEST RESULTS"
	printf '%.0s=' {1..60}
	echo "Total test suites: $TOTAL_TESTS"
	echo "Passed: $PASSED_TESTS"
	echo "Failed: $FAILED_TESTS"
	echo

	if [[ $FAILED_TESTS -eq 0 ]]; then
		print_success "ALL TEST SUITES PASSED!"
		echo
		echo "Your Claude Profile Manager is working correctly!"
		return 0
	else
		print_error "SOME TEST SUITES FAILED"
		echo
		echo "Please review the failed tests above and fix any issues."
		return 1
	fi
}

main() {
	print_header "Claude Profile Manager Test Suite"
	echo "Setting up test environment..."

	# Make all test files executable
	chmod +x "$PROJECT_ROOT/tests/"*.sh
	print_success "Made test files executable"

	# Define test suites in order of execution
	local test_suites=(
		"$PROJECT_ROOT/tests/smoke.sh:Smoke Tests"
		"$PROJECT_ROOT/tests/ui-functionality-test.sh:UI Functionality Tests"
		"$PROJECT_ROOT/tests/list-command-integration-test.sh:List Command Tests"
		"$PROJECT_ROOT/tests/core-operations-test.sh:Core Profile Operations Tests"
		"$PROJECT_ROOT/tests/error-handling-test.sh:Error Handling & Edge Case Tests"
		"$PROJECT_ROOT/tests/workflow-integration-test.sh:Workflow Integration Tests"
	)

	TOTAL_TESTS=${#test_suites[@]}

	# Run each test suite
	for test_suite in "${test_suites[@]}"; do
		IFS=':' read -r test_file test_name <<<"$test_suite"
		run_test_suite "$test_file" "$test_name"
	done

	# Print final summary
	print_final_summary
	exit $?
}

main "$@"
