#!/bin/bash

KEYCHAIN_SERVICE="Claude Profile Manager"
CLAUDE_KEYCHAIN_SERVICE="Claude Code"

keychain_save_password() {
    local account="$1"
    local password="$2"
    local service="${3:-$KEYCHAIN_SERVICE}"
    
    # Verify we're using the user keychain
    if ! security list-keychains | grep -q "login.keychain"; then
        echo "Error: Login keychain not accessible" >&2
        return 1
    fi
    
    security add-generic-password -a "$account" -s "$service" -w "$password" -U 2>/dev/null
}

keychain_get_password() {
    local account="$1"
    local service="${2:-$KEYCHAIN_SERVICE}"
    
    # Verify we're using the user keychain
    if ! security list-keychains | grep -q "login.keychain"; then
        echo "Error: Login keychain not accessible" >&2
        return 1
    fi
    
    # Record start time for consistent timing
    local start_time
    start_time=$(date +%s%N)
    local result
    result=$(security find-generic-password -a "$account" -s "$service" -w 2>/dev/null)
    local exit_code=$?
    
    # Enforce minimum operation time (10ms) to prevent timing attacks
    local elapsed=$(($(date +%s%N) - start_time))
    local min_time=10000000  # 10ms in nanoseconds
    if [[ $elapsed -lt $min_time ]]; then
        local sleep_ns=$((min_time - elapsed))
        local sleep_seconds=$(((sleep_ns + 500000000) / 1000000000))
        if [[ $sleep_seconds -gt 0 ]]; then
            sleep "$sleep_seconds"
        else
            sleep 0.01
        fi
    fi
    
    # Only return result if successful and non-empty
    if [[ $exit_code -eq 0 ]] && [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi
    
    # Return failure without exposing error details
    return 1
}

keychain_delete_password() {
    local account="$1"
    local service="${2:-$KEYCHAIN_SERVICE}"
    
    # Verify we're using the user keychain
    if ! security list-keychains | grep -q "login.keychain"; then
        echo "Error: Login keychain not accessible" >&2
        return 1
    fi
    
    local result
    result=$(security delete-generic-password -a "$account" -s "$service" 2>&1)
    local exit_code=$?
    
    # Return success if deleted or if item didn't exist
    if [[ $exit_code -eq 0 ]] || [[ "$result" == *"could not be found"* ]]; then
        return 0
    fi
    
    # Return failure for actual errors
    return 1
}

keychain_list_accounts() {
    local service="${1:-$KEYCHAIN_SERVICE}"
    
    # Escape service name to prevent command and regex injection
    local escaped_service
    escaped_service=$(printf '%s' "$service" | sed 's/[^a-zA-Z0-9._-]//g' | sed "s/[[\.*^$()+?{|]/\\\\&/g")
    
    security dump-keychain 2>/dev/null | grep -A 1 "\"svce\"<blob>=\"$escaped_service\"" | grep "\"acct\"<blob>=" | sed 's/.*"acct"<blob>="\([^"]*\)".*/\1/' | sort -u
}

get_claude_console_api_key() {
    local username
    username=$(whoami)
    keychain_get_password "$username" "$CLAUDE_KEYCHAIN_SERVICE"
}

save_claude_console_api_key() {
    local api_key="$1"
    local username
    username=$(whoami)
    keychain_save_password "$username" "$api_key" "$CLAUDE_KEYCHAIN_SERVICE"
}

get_claude_subscription_token() {
    # On macOS, subscription credentials are also in keychain
    local username
    username=$(whoami)
    
    local result
    result=$(security find-generic-password -a "$username" -s "Claude Code-credentials" -w 2>/dev/null)
    local exit_code=$?
    
    # Only return result if successful and non-empty
    if [[ $exit_code -eq 0 ]] && [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi
    
    # Return failure without exposing error details
    return 1
}

backup_claude_subscription_credentials() {
    local profile_name="$1"
    local session_key
    session_key=$(get_claude_subscription_token)
    
    if [[ -n "$session_key" ]]; then
        keychain_save_password "$profile_name" "$session_key"
        return 0
    fi
    return 1
}

restore_claude_subscription_credentials() {
    local profile_name="$1"
    local session_key
    session_key=$(keychain_get_password "$profile_name")
    
    if [[ -n "$session_key" ]]; then
        local username
        username=$(whoami)
        keychain_save_password "$username" "$session_key" "Claude Code-credentials"
        return 0
    fi
    return 1
}

delete_claude_subscription_backup() {
    local profile_name="$1"
    keychain_delete_password "$profile_name"
}

detect_auth_method() {
    local console_api_key
    local subscription_token
    
    console_api_key=$(get_claude_console_api_key)
    subscription_token=$(get_claude_subscription_token)
    
    if [[ -n "$subscription_token" ]]; then
        echo "subscription"
    elif [[ -n "$console_api_key" ]]; then
        echo "console"
    else
        echo "none"
    fi
}