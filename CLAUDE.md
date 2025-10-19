# Claude Profile Manager

## Project Overview
A robust authentication profile management system for Claude Code CLI that allows seamless switching between different Claude authentication methods.

**Current Version**: 1.2.0 - Enhanced Release ✅

## Key Features
- **Profile Management Commands**: save, list, switch, delete, current, alias management
- **Secure Storage**: All credentials stored in encrypted macOS keychain services  
- **Authentication Detection**: Automatically detects subscription vs console API methods
- **OAuth Token Analysis**: Real-time expiration detection and health monitoring
- **Enhanced Display**: Token expiration times, aliases, and formatted timestamps
- **Alias Support**: Create aliases for profiles (e.g., `api` for `console`)
- **Auto-Save Functionality**: Automatically saves current credentials when switching profiles
- **Security Hardened**: jq-based JSON parsing, input validation, secure file permissions

## Installation

This tool is distributed via Homebrew:

```bash
brew tap derekspelledcorrectly/claude-tools
brew install claude-profile-manager
```

## Authentication Methods Supported

- **Console API**: Static API keys stored in keychain service "Claude Code" 
- **Subscription**: OAuth tokens stored in keychain service "Claude Code-credentials"

## Core Commands

### Profile Management
```bash
# Save current credentials as a profile
claude-profile save                    # Save to current profile (with confirmation if exists)
claude-profile save work               # Save current credentials as 'work' profile  
claude-profile s personal              # Short form

# List all profiles with status
claude-profile list
claude-profile ls

# Switch to a profile  
claude-profile switch work
claude-profile sw personal
claude-profile work          # Direct switching

# Show current active profile
claude-profile current
claude-profile cur

# Delete a profile
claude-profile delete old-profile
claude-profile del old-profile
claude-profile rm old-profile
```

### Alias Management
```bash
# Create an alias for a profile
claude-profile alias api console

# List all aliases
claude-profile aliases

# Remove an alias
claude-profile unalias api
```

## Auto-Save Functionality

When switching away from a subscription profile, the tool automatically saves current live credentials to prevent loss of fresh tokens that Claude Code may have refreshed in the background.

**Behavior:**
- Automatically saves subscription credentials when switching to different profile
- Silent operation - no confirmation prompts (changed in v1.1.0)
- Only updates credentials if they have actually changed
- Console API profiles don't need auto-save (static keys)

## Technical Implementation Details

### Profile Storage Structure
```
~/.claude/profiles/
├── .current                    # Current active profile
├── .aliases                    # Alias mappings
├── .audit.log                  # Optional audit log
├── console.json                # Profile metadata only
└── subscription.json           # Profile metadata only
```

### Claude OAuth Token Format
- **Structure**: JSON object `{"claudeAiOauth": {...}}`
- **Expiration Field**: `expiresAt` contains millisecond timestamp (13 digits)
- **Parsing Method**: Uses `jq` for secure JSON parsing (no text manipulation)
- **Security Note**: Tokens are not JWTs, they are proprietary JSON objects
- **Detection**: Regex pattern `^\{.*claudeAiOauth.*\}$`

### List Command Enhancements
- **Current Profile Indicator**: The `➤` arrow shows which profile is currently active
- **Unified Status Column**: Single STATUS column instead of separate STATUS/TOKEN STATUS
- **Authentication-Specific Status**: 
  - Console profiles: `ready` or `missing` 
  - Subscription profiles: Token expiration details (`expires in 2d 4h`, `expires soon (30m)`, `expired 3h ago`)
- **Real-time expiration checking**: Compares `expiresAt` with current time
- **Graceful handling**: Falls back to "valid" for unparseable tokens

**Example List Output:**
```
Available profiles:
     PROFILE             TYPE          CREATED  LAST USED  STATUS
     console (api)       console       Aug 26   Aug 27     ready
  ➤  subscription (sub)  subscription  Aug 27   Aug 27     expires in 0d 5h
```

### OAuth Token Refresh (Not Currently Implemented)

This tool does not currently refresh OAuth tokens automatically. Instead, it uses an auto-save approach to capture fresh tokens from Claude Code's live authentication.

However, OAuth token refresh could be implemented using Claude's refresh endpoint:

- **Endpoint**: `https://console.anthropic.com/v1/oauth/token`
- **Method**: POST with `Content-Type: application/json`
- **Client ID**: `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (official Claude Code client)
- **Payload**: `{"grant_type":"refresh_token","refresh_token":"sk-ant-ort01-...","client_id":"..."}`

The current auto-save approach was chosen because it's simpler and avoids issues with credential synchronization between this tool and Claude Code's own token management.

## Security Features

- **Encrypted Storage**: All credentials stored in macOS keychain services
- **Input Validation**: Profile names validated, path traversal prevention
- **Secure Operations**: Temporary files created with 600 permissions
- **Command Injection Prevention**: Proper shell escaping throughout
- **No Process Exposure**: No credentials visible in process lists (`ps aux`)
- **Audit Logging**: Optional logging with `CLAUDE_PROFILE_LOG=true`

## Dependencies

- **Required**: `jq` (JSON parsing and security)
- **System**: macOS keychain services
- **Runtime**: Bash 4.0+, standard Unix utilities
- **Installation**: Auto-installed via Homebrew formula
- **Development**: `just` (task runner), `shellcheck`, `shfmt` (optional, for development)

## Development Tools

This project includes comprehensive development automation via [just](https://github.com/casey/just):

### Quick Development Commands
```bash
just install-deps    # Install all development dependencies
just lint            # Check code quality (shellcheck + shfmt)
just format          # Fix formatting issues automatically
just test            # Run comprehensive test suite
just dev             # Quick cycle: format + test
```

### Available Development Tasks
- **Code Quality**: `lint`, `lint-fix`, `format`, `shellcheck`, `shfmt-check`
- **Testing**: `test`, `smoke` (quick validation)
- **Workflows**: `dev`, `qa`, `pre-commit`, `ci`, `fix-all`
- **Maintenance**: `clean`, `release`, `validate-env`

See the [Development Guide](DEVELOPMENT.md) for complete details.

## Platform Requirements

- **macOS**: Required for keychain services integration
- **Claude Code CLI**: Must be installed and configured
- **User Account**: Standard user account (not root)

## Important Notes

- **Restart Required**: After switching profiles, restart Claude Code with Ctrl+D twice, then `claude -c`
- **Credential Sync**: Tool automatically saves live credentials to prevent staleness
- **Profile Isolation**: Each profile maintains separate keychain entries
- **Security Model**: Inherits macOS keychain security protections

## Usage Examples

### Basic Workflow
```bash
# Save your current work credentials
claude-profile save work

# Save personal credentials (after switching Claude to personal account)  
claude-profile save personal

# Enhanced workflow: Update current profile with fresh credentials
claude-profile switch work
# ... do some work, Claude may refresh tokens in background ...
claude-profile save    # Updates 'work' profile with current credentials (silent if no changes)

# List all profiles with current status
claude-profile list

# Switch between work and personal
claude-profile work
claude-profile personal

# Create convenient aliases
claude-profile alias w work
claude-profile alias p personal

# Use aliases
claude-profile w
claude-profile p
```

### Profile Management
```bash
# Check current profile
claude-profile current

# See all profiles with current indicator and status
claude-profile list

# Clean up old profiles
claude-profile delete old-work
claude-profile rm temp-profile
```

## Troubleshooting

### Common Issues
- **"No token found"**: Profile may not have been saved correctly
- **"Authentication error"**: Token may have expired, try saving fresh credentials
- **"Profile not found"**: Check profile name spelling or use `claude-profile list`

### Debug Mode
Enable debug output with:
```bash
CLAUDE_PROFILE_DEBUG=true claude-profile <command>
```

### Audit Logging
Enable audit logging with:
```bash
CLAUDE_PROFILE_LOG=true claude-profile <command>
```

## Additional Documentation

- **[Development Guide](DEVELOPMENT.md)**: Development workflows and contribution guidelines
- **[Security Policy](SECURITY.md)**: Security considerations and reporting
- **[README](README.md)**: Quick start and installation guide