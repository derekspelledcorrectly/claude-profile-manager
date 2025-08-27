#!/bin/bash
#
# Basic tests for Claude Profile Manager
# Simple validation that the main functionality works
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

# Test basic script execution
test_basic_functionality() {
    echo "Testing basic functionality..."
    
    # Test help command
    if "$PROJECT_ROOT/bin/claude-profile" --help >/dev/null 2>&1; then
        print_success "Help command works"
    else
        print_error "Help command failed"
    fi
    
    
    # Test invalid command handling
    if ! "$PROJECT_ROOT/bin/claude-profile" invalid-command >/dev/null 2>&1; then
        print_success "Invalid commands rejected properly"
    else
        print_error "Invalid commands not rejected"
    fi
}

# Test profile name validation
test_validation() {
    echo "Testing validation functions..."
    
    # Source the library to test validation
    # shellcheck source=../lib/profile-core.sh
    source "$PROJECT_ROOT/lib/profile-core.sh"
    
    # Test valid names
    if validate_profile_name "work" >/dev/null 2>&1; then
        print_success "Valid profile name accepted"
    else
        print_error "Valid profile name rejected"
    fi
    
    # Test invalid names
    if ! validate_profile_name "" >/dev/null 2>&1; then
        print_success "Empty profile name rejected"
    else
        print_error "Empty profile name accepted"
    fi
    
    if ! validate_profile_name "current" >/dev/null 2>&1; then
        print_success "Reserved name 'current' rejected"
    else
        print_error "Reserved name 'current' accepted"
    fi
}

# Test syntax of all shell files
test_syntax() {
    echo "Testing shell syntax..."
    
    local shell_files=(
        "$PROJECT_ROOT/bin/claude-profile"
        "$PROJECT_ROOT/lib/profile-core.sh"
        "$PROJECT_ROOT/lib/keychain-utils.sh"
        "$PROJECT_ROOT/tests/ui-functionality-test.sh"
        "$PROJECT_ROOT/tests/list-command-integration-test.sh"
        "$PROJECT_ROOT/tests/core-operations-test.sh"
        "$PROJECT_ROOT/tests/error-handling-test.sh"
        "$PROJECT_ROOT/tests/workflow-integration-test.sh"
    )
    
    for file in "${shell_files[@]}"; do
        if [[ -f "$file" ]] && bash -n "$file" 2>/dev/null; then
            print_success "Syntax OK: $(basename "$file")"
        else
            print_error "Syntax error: $(basename "$file")"
        fi
    done
}

# Print summary
print_summary() {
    echo
    echo "Test Results:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All tests passed!"
        return 0
    else
        echo "✗ Some tests failed"
        return 1
    fi
}

# Run UI functionality tests if available
run_ui_tests() {
    echo "Running UI functionality tests..."
    
    if [[ -x "$PROJECT_ROOT/tests/ui-functionality-test.sh" ]]; then
        if "$PROJECT_ROOT/tests/ui-functionality-test.sh"; then
            print_success "UI functionality tests passed"
        else
            print_error "UI functionality tests failed"
        fi
    else
        print_error "UI functionality test script not executable"
    fi
}

# Run list command integration tests if available
run_integration_tests() {
    echo "Running list command integration tests..."
    
    if [[ -x "$PROJECT_ROOT/tests/list-command-integration-test.sh" ]]; then
        if "$PROJECT_ROOT/tests/list-command-integration-test.sh"; then
            print_success "List command integration tests passed"
        else
            print_error "List command integration tests failed"
        fi
    else
        print_error "List command integration test script not executable"
    fi
}

# Main execution
main() {
    echo "Running basic tests for Claude Profile Manager..."
    echo
    
    test_basic_functionality
    echo
    test_validation
    echo
    test_syntax
    echo
    run_ui_tests
    echo
    run_integration_tests
    
    print_summary
    exit $?
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi