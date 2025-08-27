#!/bin/bash

PROFILE_SETTINGS_DIR="$HOME/.claude/profiles"

# shellcheck source=lib/keychain-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/keychain-utils.sh"

validate_profile_name() {
    local name="$1"
    
    # Check if name is empty
    if [[ -z "$name" ]]; then
        echo "Error: Profile name cannot be empty" >&2
        return 1
    fi
    
    # Only allow alphanumeric characters, dashes, and underscores
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Profile name can only contain letters, numbers, dashes, and underscores" >&2
        return 1
    fi
    
    # Prevent names starting with dots (hidden files)
    if [[ "$name" =~ ^\. ]]; then
        echo "Error: Profile name cannot start with a dot" >&2
        return 1
    fi
    
    # Prevent excessively long names
    if [[ ${#name} -gt 50 ]]; then
        echo "Error: Profile name cannot exceed 50 characters" >&2
        return 1
    fi
    
    # Check for reserved names
    local reserved_names=("." ".." "current" "aliases" "audit" "tmp" "temp" "con" "prn" "aux" "nul")
    for reserved in "${reserved_names[@]}"; do
        if [[ "$name" == "$reserved" ]]; then
            echo "Error: '$name' is a reserved profile name" >&2
            return 1
        fi
    done
    
    return 0
}

validate_alias_name() {
    local name="$1"
    
    # Aliases follow same rules as profile names
    validate_profile_name "$name"
}

get_profile_file() {
    local profile_name="$1"
    echo "$PROFILE_SETTINGS_DIR/$profile_name.json"
}

detect_profile_auth_type() {
    local profile_name="$1"
    local profile_file
    profile_file=$(get_profile_file "$profile_name")
    
    # First try to get auth method from profile JSON
    if [[ -f "$profile_file" ]]; then
        local stored_auth
        stored_auth=$(jq -r '.auth_method // empty' "$profile_file" 2>/dev/null)
        if [[ -n "$stored_auth" && "$stored_auth" != "null" ]]; then
            echo "$stored_auth"
            return
        fi
    fi
    
    # Fallback: check keychain and make educated guess
    if keychain_get_password "$profile_name" >/dev/null 2>&1; then
        case "$profile_name" in
            "console"|"api")
                echo "console"
                ;;
            "subscription"|"sub")
                echo "subscription"
                ;;
            *)
                # Check credential format for proper detection using generic patterns
                local cred
                cred=$(keychain_get_password "$profile_name")
                local cred_length=${#cred}
                if [[ $cred_length -eq 108 && "$cred" =~ ^sk-ant-api ]]; then
                    echo "console"
                elif [[ "$cred" =~ ^\. && "$cred" == *.*.* ]]; then
                    echo "subscription"
                else
                    echo "unknown"
                fi
                ;;
        esac
    else
        # Final fallback: detect from current active auth
        detect_auth_method
    fi
}

log_operation() {
    local operation="$1"
    local profile="$2"
    local details="${3:-}"
    
    # Only log if explicitly enabled
    if [[ "${CLAUDE_PROFILE_LOG:-}" == "true" ]]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local log_file="$PROFILE_SETTINGS_DIR/.audit.log"
        
        # Ensure log file has secure permissions
        if [[ ! -f "$log_file" ]]; then
            touch "$log_file"
            chmod 600 "$log_file"
        fi
        
        # Log the operation
        local log_entry="[$timestamp] $operation: $profile"
        if [[ -n "$details" ]]; then
            log_entry="$log_entry ($details)"
        fi
        
        echo "$log_entry" >> "$log_file"
    fi
}

ensure_profile_dir() {
    # Create directory with secure permissions
    if [[ ! -d "$PROFILE_SETTINGS_DIR" ]]; then
        mkdir -p "$PROFILE_SETTINGS_DIR"
        chmod 700 "$PROFILE_SETTINGS_DIR"
    else
        # Ensure correct permissions even if directory already exists
        chmod 700 "$PROFILE_SETTINGS_DIR"
    fi
    
    # Ensure secure permissions on parent directory too
    chmod 700 "$(dirname "$PROFILE_SETTINGS_DIR")" 2>/dev/null || true
}

secure_temp_file() {
    local temp_file
    
    # Use mktemp with secure random template and explicit directory
    temp_file=$(mktemp -t "claude-profile-XXXXXXXXXX") || {
        echo "Error: Could not create temporary file" >&2
        return 1
    }
    
    # Set restrictive permissions immediately
    chmod 600 "$temp_file" || {
        rm -f "$temp_file"
        echo "Error: Could not set file permissions" >&2
        return 1
    }
    
    echo "$temp_file"
}

resolve_profile_alias() {
    local profile_name="$1"
    local alias_file="$PROFILE_SETTINGS_DIR/.aliases"
    
    if [[ -f "$alias_file" ]]; then
        local resolved
        # Escape profile name to prevent command injection
        local escaped_name
        escaped_name=$(printf '%q' "$profile_name")
        
        resolved=$(grep "^$escaped_name=" "$alias_file" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$resolved" ]]; then
            echo "$resolved"
            return
        fi
    fi
    
    echo "$profile_name"
}

profile_exists() {
    local profile_name="$1"
    local profile_file
    profile_file=$(get_profile_file "$profile_name")
    [[ -f "$profile_file" ]]
}

save_profile() {
    local profile_name="$1"
    shift
    local aliases=("$@")
    
    # If no profile name provided, try to use current profile
    if [[ -z "$profile_name" ]]; then
        local current_file="$PROFILE_SETTINGS_DIR/.current"
        if [[ -f "$current_file" ]]; then
            profile_name=$(cat "$current_file")
            echo "No profile name specified. Using current profile: $profile_name"
            
            # Check if profile already exists and prompt for confirmation
            if profile_exists "$profile_name"; then
                echo -n "Profile '$profile_name' already exists. Overwrite existing credentials? [y/N]: "
                read -r -n 10 response
                case "$response" in
                    [Yy]|[Yy][Ee][Ss])
                        ;;
                    *)
                        echo "Save cancelled."
                        return 0
                        ;;
                esac
            fi
        else
            echo "Error: No profile name specified and no current profile active." >&2
            echo "Usage: claude-profile save <name> [aliases...]" >&2
            return 1
        fi
    fi
    
    # Validate profile name
    if ! validate_profile_name "$profile_name"; then
        return 1
    fi
    
    # Validate all alias names
    for alias in "${aliases[@]}"; do
        if ! validate_alias_name "$alias"; then
            return 1
        fi
    done
    
    ensure_profile_dir
    
    local auth_method
    auth_method=$(detect_auth_method)
    
    if [[ "$auth_method" == "none" ]]; then
        echo "Error: No Claude authentication found. Please authenticate first." >&2
        return 1
    fi
    
    # Only show auth method detection for explicitly named profiles (not current profile)
    if [[ "$1" != "" ]]; then
        echo "Detected authentication method: $auth_method"
    fi
    
    # Save credentials to keychain
    case "$auth_method" in
        "console")
            local api_key
            api_key=$(get_claude_console_api_key)
            if [[ -n "$api_key" ]]; then
                keychain_save_password "$profile_name" "$api_key"
                echo "Saved console API profile: $profile_name"
            else
                echo "Error: Could not retrieve console API key" >&2
                return 1
            fi
            ;;
        "subscription")
            if backup_claude_subscription_credentials "$profile_name"; then
                echo "Saved subscription profile: $profile_name"
            else
                echo "Error: Could not backup subscription credentials" >&2
                return 1
            fi
            ;;
    esac
    
    # Create profile JSON file with minimal metadata
    local profile_file
    profile_file=$(get_profile_file "$profile_name")
    
    # Create basic profile structure with just metadata
    cat > "$profile_file" << EOF
{
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "auth_method": "$auth_method",
  "last_used": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    # Set secure permissions
    chmod 600 "$profile_file"
    
    # Log the profile creation
    log_operation "SAVE" "$profile_name" "$auth_method"
    
    # Save aliases if provided
    if [[ ${#aliases[@]} -gt 0 ]]; then
        local alias_file="$PROFILE_SETTINGS_DIR/.aliases"
        for alias in "${aliases[@]}"; do
            # Remove existing alias if it exists using secure temp file
            if [[ -f "$alias_file" ]]; then
                local temp_file
                temp_file=$(secure_temp_file "$alias_file") || return 1
                
                # Escape alias name for safe grep
                local escaped_alias
                escaped_alias=$(printf '%q' "$alias")
                
                grep -v "^$escaped_alias=" "$alias_file" > "$temp_file" 2>/dev/null || true
                mv "$temp_file" "$alias_file" || {
                    rm -f "$temp_file"
                    echo "Error: Could not update alias file" >&2
                    return 1
                }
            fi
            # Add new alias
            echo "$alias=$profile_name" >> "$alias_file"
            chmod 600 "$alias_file"
            echo "Added alias: $alias -> $profile_name"
        done
    fi
}

format_timestamp() {
    local iso_timestamp="$1"
    
    if [[ -z "$iso_timestamp" || "$iso_timestamp" == "null" ]]; then
        echo "unknown"
        return
    fi
    
    # Convert ISO timestamp to readable format (e.g., "Jan 15" or "never")
    if command -v date >/dev/null 2>&1; then
        # Try to parse the ISO timestamp
        local formatted_date
        formatted_date=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_timestamp" "+%b %d" 2>/dev/null)
        if [[ -n "$formatted_date" ]]; then
            echo "$formatted_date"
        else
            echo "invalid"
        fi
    else
        echo "unknown"
    fi
}

parse_claude_oauth_expiration() {
    local oauth_json="$1"
    
    if [[ "${CLAUDE_PROFILE_DEBUG:-}" == "true" ]]; then
        echo "DEBUG: Parsing Claude OAuth JSON for expiration data" >&2
    fi
    
    # Look for common expiration field names using jq
    local exp_fields=("expires_at" "expiresAt" "expires" "exp" "accessTokenExpiresAt" "refreshTokenExpiresAt")
    
    for field in "${exp_fields[@]}"; do
        local timestamp
        timestamp=$(echo "$oauth_json" | jq -r ".. | objects | select(has(\"$field\")) | .$field" 2>/dev/null | head -1)
        
        if [[ -n "$timestamp" && "$timestamp" != "null" ]]; then
            if [[ "${CLAUDE_PROFILE_DEBUG:-}" == "true" ]]; then
                echo "DEBUG: Found timestamp field '$field': $timestamp" >&2
            fi
            
            format_oauth_timestamp "$timestamp"
            return
        fi
    done
    
    # Look for nested access token expiration
    local access_token_exp
    access_token_exp=$(echo "$oauth_json" | jq -r '.claudeAiOauth.accessToken.expires_at // .claudeAiOauth.accessToken.expiresAt // empty' 2>/dev/null)
    
    if [[ -n "$access_token_exp" && "$access_token_exp" != "null" ]]; then
        if [[ "${CLAUDE_PROFILE_DEBUG:-}" == "true" ]]; then
            echo "DEBUG: Found access token expiration: $access_token_exp" >&2
        fi
        format_oauth_timestamp "$access_token_exp"
        return
    fi
    
    if [[ "${CLAUDE_PROFILE_DEBUG:-}" == "true" ]]; then
        echo "DEBUG: No expiration timestamps found in OAuth JSON" >&2
    fi
    
    # Fallback: assume valid if we can't parse expiration
    echo "valid"
}

format_oauth_timestamp() {
    local timestamp="$1"
    
    if [[ "${CLAUDE_PROFILE_DEBUG:-}" == "true" ]]; then
        echo "DEBUG: Formatting timestamp: $timestamp" >&2
    fi
    
    # Handle different timestamp formats
    local current_time
    current_time=$(date +%s)
    local exp_time
    
    # Try to parse as Unix timestamp (milliseconds) - check first since it's more specific
    if [[ ${#timestamp} -eq 13 && "$timestamp" =~ ^[0-9]+$ ]]; then
        exp_time=$((timestamp / 1000))
    # Try to parse as Unix timestamp (seconds)
    elif [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        exp_time="$timestamp"
    # Try to parse as ISO 8601 date
    elif [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        exp_time=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%.*}" "+%s" 2>/dev/null)
    else
        if [[ "${CLAUDE_PROFILE_DEBUG:-}" == "true" ]]; then
            echo "DEBUG: Unrecognized timestamp format: $timestamp" >&2
        fi
        echo "unknown"
        return
    fi
    
    if [[ -z "$exp_time" ]]; then
        echo "unknown"
        return
    fi
    
    if [[ "${CLAUDE_PROFILE_DEBUG:-}" == "true" ]]; then
        echo "DEBUG: Current time: $current_time, Expiration time: $exp_time" >&2
    fi
    
    # Calculate time difference
    local time_diff=$((exp_time - current_time))
    
    if [[ $time_diff -lt 0 ]]; then
        local hours_ago=$((-time_diff / 3600))
        if [[ $hours_ago -lt 24 ]]; then
            echo "expired ${hours_ago}h ago"
        else
            local days_ago=$((-time_diff / 86400))
            echo "expired ${days_ago}d ago"
        fi
    elif [[ $time_diff -lt 1800 ]]; then  # Less than 30 minutes
        local minutes=$((time_diff / 60))
        echo "expires soon (${minutes}m)"
    elif [[ $time_diff -lt 14400 ]]; then  # Less than 4 hours
        local hours=$((time_diff / 3600))
        echo "expires soon (${hours}h)"
    elif [[ $time_diff -lt 604800 ]]; then  # Less than 7 days
        local days=$((time_diff / 86400))
        local hours=$(((time_diff % 86400) / 3600))
        if [[ $hours -gt 0 ]]; then
            echo "expires in ${days}d ${hours}h"
        else
            echo "expires in ${days}d"
        fi
    else
        local days=$((time_diff / 86400))
        echo "valid (${days}d)"
    fi
}

check_token_health() {
    local token="$1"
    
    # Return "n/a" for console profiles or empty tokens
    if [[ -z "$token" ]]; then
        echo "n/a"
        return
    fi
    
    # Claude subscription tokens are JSON objects, not JWTs
    if [[ "$token" =~ ^\{.*claudeAiOauth.*\} ]]; then
        # This is a Claude OAuth JSON structure
        if [[ "${CLAUDE_PROFILE_DEBUG:-}" == "true" ]]; then
            echo "DEBUG: Claude OAuth JSON detected" >&2
            echo "DEBUG: Full JSON structure:" >&2
            echo "$token" | jq . 2>/dev/null >&2 || echo "$token" >&2
            echo "DEBUG: Looking for timestamp fields..." >&2
        fi
        
        # Parse the OAuth JSON for expiration data
        parse_claude_oauth_expiration "$token"
        return
    fi
    
    # Check if token looks like a JWT (three parts separated by dots)
    if [[ ! "$token" =~ ^[^.]+\.[^.]+\.[^.]+$ ]]; then
        echo "invalid"
        return
    fi
    
    # Extract the payload (second part) for JWT tokens
    local payload
    payload=$(echo "$token" | cut -d'.' -f2)
    
    # Add padding if needed for base64 decoding
    local padding_length=$((4 - ${#payload} % 4))
    if [[ $padding_length -ne 4 ]]; then
        payload="${payload}$(printf '%*s' $padding_length | tr ' ' '=')"
    fi
    
    # Decode base64 payload
    local decoded_payload
    decoded_payload=$(echo "$payload" | base64 -d 2>/dev/null)
    
    if [[ -z "$decoded_payload" ]]; then
        echo "invalid"
        return
    fi
    
    # Extract expiration timestamp using basic text parsing
    local exp_timestamp
    exp_timestamp=$(echo "$decoded_payload" | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')
    
    if [[ -z "$exp_timestamp" ]]; then
        echo "unknown"
        return
    fi
    
    # Get current time
    local current_time
    current_time=$(date +%s)
    
    # Calculate time difference
    local time_diff=$((exp_timestamp - current_time))
    
    if [[ $time_diff -lt 0 ]]; then
        echo "expired"
    elif [[ $time_diff -lt 14400 ]]; then  # Less than 4 hours
        local hours=$((time_diff / 3600))
        echo "expires soon (${hours}h)"
    elif [[ $time_diff -lt 604800 ]]; then  # Less than 7 days
        local days=$((time_diff / 86400))
        echo "valid (${days}d)"
    else
        echo "valid"
    fi
}

get_profile_aliases() {
    local profile_name="$1"
    local alias_file="$PROFILE_SETTINGS_DIR/.aliases"
    local aliases=()
    
    if [[ -f "$alias_file" ]]; then
        while IFS='=' read -r alias_name target_profile; do
            if [[ "$target_profile" == "$profile_name" ]]; then
                aliases+=("$alias_name")
            fi
        done < "$alias_file"
    fi
    
    if [[ ${#aliases[@]} -gt 0 ]]; then
        local alias_string
        alias_string=$(IFS=', '; echo "${aliases[*]}")
        echo " ($alias_string)"
    fi
}

list_profiles() {
    ensure_profile_dir
    
    local current_profile
    current_profile=$(get_current_profile)
    
    echo "Available profiles:"
    
    local found_profiles=false
    local table_data=""
    
    # Add header row
    table_data=" 	PROFILE	TYPE	CREATED	LAST USED	STATUS"
    
    for profile_file in "$PROFILE_SETTINGS_DIR"/*.json; do
        if [[ -f "$profile_file" ]]; then
            found_profiles=true
            local profile_name
            profile_name=$(basename "$profile_file" .json)
            
            # Get profile display name with aliases
            local profile_display="$profile_name"
            local aliases
            aliases=$(get_profile_aliases "$profile_name")
            profile_display="$profile_display$aliases"
            
            # Detect auth type for this profile
            local auth_type
            auth_type=$(detect_profile_auth_type "$profile_name")
            
            # Extract timestamps from profile JSON
            local created_date="unknown"
            local last_used_date="unknown"
            local created_raw
            local last_used_raw
            created_raw=$(jq -r '.created // empty' "$profile_file" 2>/dev/null)
            last_used_raw=$(jq -r '.last_used // empty' "$profile_file" 2>/dev/null)
            
            if [[ -n "$created_raw" ]]; then
                created_date=$(format_timestamp "$created_raw")
            fi
            
            if [[ -n "$last_used_raw" ]]; then
                last_used_date=$(format_timestamp "$last_used_raw")
            fi
            
            # Current profile indicator
            local indicator=" "
            if [[ "$profile_name" == "$current_profile" ]]; then
                indicator="➤"
            fi
            
            # Check status for different auth types
            local status="n/a"
            if [[ "$auth_type" == "subscription" ]]; then
                local token
                token=$(keychain_get_password "$profile_name" 2>/dev/null)
                if [[ -n "$token" ]]; then
                    status=$(check_token_health "$token")
                else
                    status="missing"
                fi
            elif [[ "$auth_type" == "console" ]]; then
                local api_key
                api_key=$(keychain_get_password "$profile_name" 2>/dev/null)
                if [[ -n "$api_key" ]]; then
                    status="ready"
                else
                    status="missing"
                fi
            fi
            
            # Add row to table data
            table_data="$table_data
$indicator	$profile_display	$auth_type	$created_date	$last_used_date	$status"
        fi
    done
    
    if [[ "$found_profiles" == false ]]; then
        echo "  No profiles saved"
    else
        # Format table with column alignment
        echo "$table_data" | column -t -s $'\t' | sed 's/^/  /'
        
    fi
}

switch_profile() {
    local profile_name="$1"
    
    if [[ -z "$profile_name" ]]; then
        echo "Error: Profile name required" >&2
        return 1
    fi
    
    # Validate input before resolving alias
    if ! validate_profile_name "$profile_name"; then
        return 1
    fi
    
    profile_name=$(resolve_profile_alias "$profile_name")
    
    # Validate resolved profile name as well
    if ! validate_profile_name "$profile_name"; then
        return 1
    fi
    
    local profile_file
    profile_file=$(get_profile_file "$profile_name")
    if [[ ! -f "$profile_file" ]]; then
        echo "Error: Profile '$profile_name' not found" >&2
        return 1
    fi
    
    # Check if we're switching away from an active subscription profile
    # and offer to save current credentials before switching
    local current_profile
    current_profile=$(get_current_profile)
    
    if [[ -n "$current_profile" && "$current_profile" != "$profile_name" ]]; then
        local current_auth_type
        current_auth_type=$(detect_profile_auth_type "$current_profile" 2>/dev/null)
        
        if [[ "$current_auth_type" == "subscription" ]]; then
            echo "Currently using subscription profile '$current_profile'"
            echo ""
            read -p "Save current subscription credentials before switching? (y/n): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if save_current_credentials "$current_profile"; then
                    echo "Credentials saved. Proceeding with switch..."
                else
                    echo "Failed to save credentials. Proceeding anyway..."
                fi
            else
                echo "Skipping credential save. Proceeding with switch..."
            fi
            echo ""
        fi
    fi
    
    # Detect auth type for this profile
    local auth_type
    auth_type=$(detect_profile_auth_type "$profile_name")
    
    # Check token health for subscription profiles before switching
    if [[ "$auth_type" == "subscription" ]]; then
        local token
        token=$(keychain_get_password "$profile_name" 2>/dev/null)
        if [[ -n "$token" ]]; then
            local token_health
            token_health=$(check_token_health "$token")
            case "$token_health" in
                "expired")
                    echo "Warning: Token for profile '$profile_name' has expired"
                    echo "You may encounter authentication errors."
                    echo ""
                    ;;
                "expires soon"*)
                    echo "Warning: Token for profile '$profile_name' $token_health"
                    echo ""
                    ;;
            esac
        fi
    fi
    
    case "$auth_type" in
        "console")
            local stored_api_key
            stored_api_key=$(keychain_get_password "$profile_name")
            if [[ -n "$stored_api_key" ]]; then
                save_claude_console_api_key "$stored_api_key"
                
                # Clear subscription credentials from keychain when switching to console
                local username
                username=$(whoami)
                local cleanup_result
                cleanup_result=$(security delete-generic-password -a "$username" -s "Claude Code-credentials" 2>&1)
                local cleanup_exit_code=$?
                
                # Only warn on actual errors, not "item not found"
                if [[ $cleanup_exit_code -ne 0 ]] && [[ "$cleanup_result" != *"could not be found"* ]]; then
                    echo "Warning: Failed to cleanup subscription credentials: Consider restarting" >&2
                fi
                
                echo "Switched to console API profile: $profile_name"
                log_operation "SWITCH" "$profile_name" "console"
            else
                echo "Error: Could not retrieve credentials for profile '$profile_name'" >&2
                return 1
            fi
            ;;
        "subscription")
            if restore_claude_subscription_credentials "$profile_name"; then
                # Clear console credentials when switching to subscription  
                local username
                username=$(whoami)
                local cleanup_result
                cleanup_result=$(security delete-generic-password -a "$username" -s "Claude Code" 2>&1)
                local cleanup_exit_code=$?
                
                # Only warn on actual errors, not "item not found"
                if [[ $cleanup_exit_code -ne 0 ]] && [[ "$cleanup_result" != *"could not be found"* ]]; then
                    echo "Warning: Failed to cleanup console credentials: Consider restarting" >&2
                fi
                
                echo "Switched to subscription profile: $profile_name"
                log_operation "SWITCH" "$profile_name" "subscription"
            else
                echo "Error: Could not restore subscription credentials for profile '$profile_name'" >&2
                return 1
            fi
            ;;
        *)
            echo "Error: Unknown authentication type '$auth_type' for profile '$profile_name'" >&2
            return 1
            ;;
    esac
    
    # Update last_used timestamp for this profile
    local temp_file
    temp_file=$(secure_temp_file "$profile_file") || true
    if [[ -n "$temp_file" ]]; then
        jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.last_used = $timestamp' "$profile_file" > "$temp_file" && \
           mv "$temp_file" "$profile_file"
    fi
    
    echo "$profile_name" > "$PROFILE_SETTINGS_DIR/.current"
    chmod 600 "$PROFILE_SETTINGS_DIR/.current"
    
    echo ""
    echo "Please restart Claude Code:"
    echo "  1. Press Ctrl+D twice to exit"
    echo "  2. Run: claude -c"
}

get_current_profile() {
    local current_file="$PROFILE_SETTINGS_DIR/.current"
    if [[ -f "$current_file" ]]; then
        cat "$current_file"
    else
        local auth_method
        auth_method=$(detect_auth_method)
        if [[ "$auth_method" != "none" ]]; then
            echo "(unnamed $auth_method)"
        else
            echo "(no authentication)"
        fi
    fi
}

show_current_profile() {
    local current_profile
    current_profile=$(get_current_profile)
    local auth_method
    auth_method=$(detect_auth_method)
    
    echo "Current profile: $current_profile"
    echo "Authentication method: $auth_method"
}

delete_profile() {
    local profile_name="$1"
    
    if [[ -z "$profile_name" ]]; then
        echo "Error: Profile name required" >&2
        return 1
    fi
    
    # Validate input before resolving alias
    if ! validate_profile_name "$profile_name"; then
        return 1
    fi
    
    profile_name=$(resolve_profile_alias "$profile_name")
    
    # Validate resolved profile name as well
    if ! validate_profile_name "$profile_name"; then
        return 1
    fi
    
    local profile_file
    profile_file=$(get_profile_file "$profile_name")
    if [[ ! -f "$profile_file" ]]; then
        echo "Error: Profile '$profile_name' not found" >&2
        return 1
    fi
    
    # Detect auth type to know how to clean up credentials
    local auth_type
    auth_type=$(detect_profile_auth_type "$profile_name")
    
    case "$auth_type" in
        "console")
            keychain_delete_password "$profile_name"
            ;;
        "subscription")
            delete_claude_subscription_backup "$profile_name"
            ;;
    esac
    
    # Remove the profile JSON file
    rm -f "$profile_file"
    
    local current_file="$PROFILE_SETTINGS_DIR/.current"
    if [[ -f "$current_file" ]] && [[ "$(cat "$current_file")" == "$profile_name" ]]; then
        rm "$current_file"
    fi
    
    echo "Deleted profile: $profile_name"
    log_operation "DELETE" "$profile_name" "$auth_type"
}

add_alias() {
    local alias_name="$1"
    local profile_name="$2"
    
    if [[ -z "$alias_name" || -z "$profile_name" ]]; then
        echo "Error: Both alias name and profile name required" >&2
        return 1
    fi
    
    # Validate alias name
    if ! validate_alias_name "$alias_name"; then
        return 1
    fi
    
    # Validate profile name
    if ! validate_profile_name "$profile_name"; then
        return 1
    fi
    
    ensure_profile_dir
    
    # Check if profile exists
    local profile_file
    profile_file=$(get_profile_file "$profile_name")
    if [[ ! -f "$profile_file" ]]; then
        echo "Error: Profile '$profile_name' not found" >&2
        return 1
    fi
    
    local alias_file="$PROFILE_SETTINGS_DIR/.aliases"
    
    # Remove existing alias if it exists using secure temp file
    if [[ -f "$alias_file" ]]; then
        local temp_file
        temp_file=$(secure_temp_file "$alias_file") || return 1
        
        # Escape alias name for safe grep
        local escaped_alias
        escaped_alias=$(printf '%q' "$alias_name")
        
        grep -v "^$escaped_alias=" "$alias_file" > "$temp_file" 2>/dev/null || true
        mv "$temp_file" "$alias_file" || {
            rm -f "$temp_file"
            echo "Error: Could not update alias file" >&2
            return 1
        }
    fi
    
    # Add new alias
    echo "$alias_name=$profile_name" >> "$alias_file"
    chmod 600 "$alias_file"
    echo "Added alias: $alias_name -> $profile_name"
    log_operation "ADD_ALIAS" "$alias_name" "-> $profile_name"
}

list_aliases() {
    local alias_file="$PROFILE_SETTINGS_DIR/.aliases"
    
    if [[ ! -f "$alias_file" ]]; then
        echo "No aliases defined"
        return
    fi
    
    echo "Defined aliases:"
    while IFS='=' read -r alias_name profile_name; do
        printf "  %-15s -> %s\n" "$alias_name" "$profile_name"
    done < "$alias_file"
}

remove_alias() {
    local alias_name="$1"
    
    if [[ -z "$alias_name" ]]; then
        echo "Error: Alias name required" >&2
        return 1
    fi
    
    # Validate alias name
    if ! validate_alias_name "$alias_name"; then
        return 1
    fi
    
    local alias_file="$PROFILE_SETTINGS_DIR/.aliases"
    
    if [[ ! -f "$alias_file" ]]; then
        echo "Error: No aliases file found" >&2
        return 1
    fi
    
    # Escape alias name for safe grep
    local escaped_alias
    escaped_alias=$(printf '%q' "$alias_name")
    
    if ! grep -q "^$escaped_alias=" "$alias_file"; then
        echo "Error: Alias '$alias_name' not found" >&2
        return 1
    fi
    
    # Use secure temp file for removal
    local temp_file
    temp_file=$(secure_temp_file "$alias_file") || return 1
    
    grep -v "^$escaped_alias=" "$alias_file" > "$temp_file" || {
        rm -f "$temp_file"
        echo "Error: Could not update alias file" >&2
        return 1
    }
    
    mv "$temp_file" "$alias_file" || {
        rm -f "$temp_file"
        echo "Error: Could not update alias file" >&2
        return 1
    }
    
    echo "Removed alias: $alias_name"
    log_operation "REMOVE_ALIAS" "$alias_name"
}

save_current_credentials() {
    local profile_name="$1"
    
    
    # Validate profile name
    if ! validate_profile_name "$profile_name"; then
        return 1
    fi
    
    # Resolve alias if needed
    profile_name=$(resolve_profile_alias "$profile_name")
    
    # Validate resolved profile name
    if ! validate_profile_name "$profile_name"; then
        return 1
    fi
    
    # Check if profile exists
    local profile_file
    profile_file=$(get_profile_file "$profile_name")
    if [[ ! -f "$profile_file" ]]; then
        echo "Error: Profile '$profile_name' not found" >&2
        return 1
    fi
    
    # Detect profile auth type
    local auth_type
    auth_type=$(detect_profile_auth_type "$profile_name")
    
    echo "Saving current credentials for profile '$profile_name'..."
    
    case "$auth_type" in
        "subscription")
            # Get live OAuth credentials from Claude Code's keychain
            local live_credentials
            live_credentials=$(keychain_get_password "${USER}" "Claude Code-credentials" 2>/dev/null)
            
            if [[ -z "$live_credentials" ]]; then
                echo "Error: No live subscription credentials found" >&2
                echo "Make sure Claude Code is authenticated with subscription" >&2
                return 1
            fi
            
            # Validate that it's proper OAuth JSON
            if ! echo "$live_credentials" | jq -e '.claudeAiOauth' >/dev/null 2>&1; then
                echo "Error: Live credentials are not valid OAuth format" >&2
                return 1
            fi
            
            # Save the live credentials to the profile backup
            if keychain_save_password "$profile_name" "$live_credentials"; then
                echo "✓ Updated profile '$profile_name' with current subscription credentials"
                
                # Show token health of the saved credentials
                local token_health
                token_health=$(check_token_health "$live_credentials")
                echo "  Saved token: $token_health"
                
                log_operation "AUTO_SAVE" "$profile_name"
                return 0
            else
                echo "Error: Failed to save credentials to profile '$profile_name'" >&2
                return 1
            fi
            ;;
        "console")
            # Get live API key from Claude Code's keychain
            local live_api_key
            live_api_key=$(keychain_get_password "${USER}" "Claude Code" 2>/dev/null)
            
            if [[ -z "$live_api_key" ]]; then
                echo "Error: No live console API key found" >&2
                echo "Make sure Claude Code is authenticated with console API" >&2
                return 1
            fi
            
            # Validate API key format
            if [[ ! "$live_api_key" =~ ^sk-ant-api01- ]]; then
                echo "Error: Live credential is not a valid console API key" >&2
                return 1
            fi
            
            # Save the live API key to the profile backup
            if keychain_save_password "$profile_name" "$live_api_key"; then
                echo "✓ Updated profile '$profile_name' with current console API key"
                log_operation "AUTO_SAVE" "$profile_name"
                return 0
            else
                echo "Error: Failed to save API key to profile '$profile_name'" >&2
                return 1
            fi
            ;;
        *)
            echo "Error: Unknown authentication type for profile '$profile_name'" >&2
            return 1
            ;;
    esac
}

