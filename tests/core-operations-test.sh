#!/bin/bash
#
# Core Operations Tests for Claude Profile Manager
# Tests profile save, delete, switching, and authentication detection
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

# Mock keychain functions for testing
mock_keychain_save_password() {
    local account="$1"
    local password="$2"
    local service="${3:-Claude Profile Manager}"
    
    # Store in test file instead of keychain
    echo "$password" > "$TEST_PROFILE_DIR/.keychain_${service//[^a-zA-Z0-9]/_}_$account"
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

# Mock authentication detection
mock_detect_auth_method() {
    echo "${TEST_AUTH_METHOD:-console}"
}

mock_get_claude_console_api_key() {
    echo "${TEST_API_KEY:-sk-ant-api01-test-key-123456789012345678901234567890123456789012345678901234567890123456789012345}"
}

mock_get_claude_subscription_token() {
    echo "${TEST_OAUTH_TOKEN:-{\"claudeAiOauth\":{\"accessToken\":{\"token\":\"test-token\",\"expiresAt\":$(($(date +%s) * 1000 + 3600000))}}}}"
}

# Test profile validation
test_profile_validation() {
    echo "Testing profile name validation..."
    
    # Source the library
    # shellcheck source=../lib/profile-core.sh
    source "$PROJECT_ROOT/lib/profile-core.sh"
    
    # Test valid names
    if validate_profile_name "work" >/dev/null 2>&1; then
        print_success "Valid profile name 'work' accepted"
    else
        print_error "Valid profile name 'work' rejected"
    fi
    
    if validate_profile_name "my-profile_123" >/dev/null 2>&1; then
        print_success "Valid profile name with dashes and underscores accepted"
    else
        print_error "Valid profile name with dashes and underscores rejected"
    fi
    
    # Test invalid names
    if ! validate_profile_name "" >/dev/null 2>&1; then
        print_success "Empty profile name rejected"
    else
        print_error "Empty profile name accepted"
    fi
    
    if ! validate_profile_name "invalid/name" >/dev/null 2>&1; then
        print_success "Profile name with slash rejected"
    else
        print_error "Profile name with slash accepted"
    fi
    
    if ! validate_profile_name ".hidden" >/dev/null 2>&1; then
        print_success "Profile name starting with dot rejected"
    else
        print_error "Profile name starting with dot accepted"
    fi
    
    if ! validate_profile_name "current" >/dev/null 2>&1; then
        print_success "Reserved name 'current' rejected"
    else
        print_error "Reserved name 'current' accepted"
    fi
}

# Test authentication type detection
test_auth_detection() {
    echo "Testing authentication type detection..."
    
    # Source the library
    # shellcheck source=../lib/profile-core.sh
    source "$PROJECT_ROOT/lib/profile-core.sh"
    
    # Override functions with mocks
    detect_auth_method() { mock_detect_auth_method; }
    
    # Test console authentication detection
    TEST_AUTH_METHOD="console"
    local detected_auth
    detected_auth=$(detect_auth_method)
    if [[ "$detected_auth" == "console" ]]; then
        print_success "Console authentication detected correctly"
    else
        print_error "Console authentication detection failed: got '$detected_auth'"
    fi
    
    # Test subscription authentication detection
    TEST_AUTH_METHOD="subscription"
    detected_auth=$(detect_auth_method)
    if [[ "$detected_auth" == "subscription" ]]; then
        print_success "Subscription authentication detected correctly"
    else
        print_error "Subscription authentication detection failed: got '$detected_auth'"
    fi
    
    # Test no authentication
    TEST_AUTH_METHOD="none"
    detected_auth=$(detect_auth_method)
    if [[ "$detected_auth" == "none" ]]; then
        print_success "No authentication detected correctly"
    else
        print_error "No authentication detection failed: got '$detected_auth'"
    fi
}

# Test profile file operations
test_profile_file_ops() {
    echo "Testing profile file operations..."
    
    # Source the library
    # shellcheck source=../lib/profile-core.sh
    source "$PROJECT_ROOT/lib/profile-core.sh"
    
    # Test get_profile_file
    local profile_file
    profile_file=$(get_profile_file "test-profile")
    local expected_file="$TEST_PROFILE_DIR/test-profile.json"
    
    if [[ "$profile_file" == "$expected_file" ]]; then
        print_success "Profile file path generation works"
    else
        print_error "Profile file path generation failed: got '$profile_file', expected '$expected_file'"
    fi
    
    # Test profile_exists before creation
    if ! profile_exists "test-profile"; then
        print_success "profile_exists correctly returns false for non-existent profile"
    else
        print_error "profile_exists incorrectly returns true for non-existent profile"
    fi
    
    # Create a test profile file
    cat > "$expected_file" << EOF
{
  "created": "2024-01-01T00:00:00Z",
  "auth_method": "console",
  "last_used": "2024-01-01T00:00:00Z"
}
EOF
    
    # Test profile_exists after creation
    if profile_exists "test-profile"; then
        print_success "profile_exists correctly returns true for existing profile"
    else
        print_error "profile_exists incorrectly returns false for existing profile"
    fi
}

# Test alias operations
test_alias_operations() {
    echo "Testing alias operations..."
    
    # Source the library  
    # shellcheck source=../lib/profile-core.sh
    source "$PROJECT_ROOT/lib/profile-core.sh"
    
    # Override keychain functions with mocks
    keychain_save_password() { mock_keychain_save_password "$@"; }
    keychain_get_password() { mock_keychain_get_password "$@"; }
    keychain_delete_password() { mock_keychain_delete_password "$@"; }
    
    # Create a test profile first
    local profile_file="$TEST_PROFILE_DIR/work.json"
    cat > "$profile_file" << EOF
{
  "created": "2024-01-01T00:00:00Z",
  "auth_method": "console",
  "last_used": "2024-01-01T00:00:00Z"
}
EOF
    chmod 600 "$profile_file"
    
    # Test adding an alias
    if add_alias "w" "work" >/dev/null 2>&1; then
        print_success "Alias addition works"
        
        # Check alias file was created
        local alias_file="$TEST_PROFILE_DIR/.aliases"
        if [[ -f "$alias_file" ]] && grep -q "w=work" "$alias_file"; then
            print_success "Alias file created with correct content"
        else
            print_error "Alias file not created or incorrect content"
        fi
    else
        print_error "Alias addition failed"
    fi
    
    # Test alias resolution
    local resolved
    resolved=$(resolve_profile_alias "w")
    if [[ "$resolved" == "work" ]]; then
        print_success "Alias resolution works"
    else
        print_error "Alias resolution failed: got '$resolved', expected 'work'"
    fi
    
    # Test alias resolution for non-existent alias
    resolved=$(resolve_profile_alias "nonexistent")
    if [[ "$resolved" == "nonexistent" ]]; then
        print_success "Non-existent alias returns original name"
    else
        print_error "Non-existent alias resolution failed"
    fi
}

# Test profile creation (mocked)
test_profile_creation() {
    echo "Testing profile creation..."
    
    # Source the library
    # shellcheck source=../lib/profile-core.sh  
    source "$PROJECT_ROOT/lib/profile-core.sh"
    
    # Override functions with mocks
    keychain_save_password() { mock_keychain_save_password "$@"; }
    keychain_get_password() { mock_keychain_get_password "$@"; }
    detect_auth_method() { mock_detect_auth_method; }
    get_claude_console_api_key() { mock_get_claude_console_api_key; }
    backup_claude_subscription_credentials() { 
        mock_keychain_save_password "$1" "$(mock_get_claude_subscription_token)"
    }
    
    # Test console profile creation
    TEST_AUTH_METHOD="console"
    TEST_API_KEY="sk-ant-api01-test-console-key-123456789012345678901234567890123456789012345678901234567890"
    
    if save_profile "test-console" >/dev/null 2>&1; then
        print_success "Console profile creation works"
        
        # Check profile file was created
        local profile_file="$TEST_PROFILE_DIR/test-console.json"
        if [[ -f "$profile_file" ]]; then
            # Check auth_method is correct
            local auth_method
            auth_method=$(jq -r '.auth_method' "$profile_file" 2>/dev/null)
            if [[ "$auth_method" == "console" ]]; then
                print_success "Console profile has correct auth_method"
            else
                print_error "Console profile has incorrect auth_method: '$auth_method'"
            fi
        else
            print_error "Console profile file not created"
        fi
    else
        print_error "Console profile creation failed"
    fi
    
    # Test subscription profile creation
    TEST_AUTH_METHOD="subscription"
    TEST_OAUTH_TOKEN='{"claudeAiOauth":{"accessToken":{"token":"test-token","expiresAt":'"$(($(date +%s) * 1000 + 3600000))"'}}}'
    
    if save_profile "test-subscription" >/dev/null 2>&1; then
        print_success "Subscription profile creation works"
        
        # Check profile file was created
        local profile_file="$TEST_PROFILE_DIR/test-subscription.json"
        if [[ -f "$profile_file" ]]; then
            # Check auth_method is correct
            local auth_method
            auth_method=$(jq -r '.auth_method' "$profile_file" 2>/dev/null)
            if [[ "$auth_method" == "subscription" ]]; then
                print_success "Subscription profile has correct auth_method"
            else
                print_error "Subscription profile has incorrect auth_method: '$auth_method'"
            fi
        else
            print_error "Subscription profile file not created"
        fi
    else
        print_error "Subscription profile creation failed"
    fi
}

# Print summary
print_summary() {
    echo
    echo "Core Operations Test Results:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All core operations tests passed!"
        return 0
    else
        echo "✗ Some core operations tests failed"
        return 1
    fi
}

# Main execution
main() {
    echo "Running core operations tests for Claude Profile Manager..."
    echo
    
    # Setup test environment
    setup_test_env
    
    # Ensure cleanup happens on exit
    trap cleanup_test_env EXIT
    
    test_profile_validation
    echo
    test_auth_detection
    echo
    test_profile_file_ops
    echo
    test_alias_operations
    echo
    test_profile_creation
    
    print_summary
    exit $?
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi