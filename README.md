# Claude Profile Manager

A robust Claude Code authentication profile management system for macOS that allows seamless switching between different Claude authentication methods without logging out and in. This can be used, for example, to quickly switch to console API billing when you've exhausted your Claude subscription tokens, and then switch back when they reset.

## Features

- **Profile Management**: Save, list, switch, and delete authentication profiles
- **Secure Storage**: Console API credentials stored in encrypted macOS keychain
- **Authentication Detection**: Automatically detects subscription vs console API methods
- **Settings Preservation**: Each profile maintains its own Claude settings
- **Command Aliases**: Short aliases for all commands (`s`, `ls`, `sw`, `cur`, `del`, `rm`)
- **Default Action**: Switch to profile by name without explicit `switch` command

## ⚠️ **IMPORTANT WARNING** ⚠️

**This tool directly modifies Claude's authentication data stored in your macOS keychain.**

- **Use at your own risk**: This tool manipulates sensitive authentication credentials
- **Potential consequences**: Could break your existing Claude Code authentication
- **Advanced users only**: Only use if you understand keychain management and authentication flows
- **No warranty**: Provided "as-is" with no guarantees (see LICENSE)
- **Backup recommended**: Consider backing up your keychain before use

## Installation

### Via Homebrew (Recommended)

```bash
brew tap derekspelledcorrectly/claude-tools
brew install claude-profile-manager
```

### Manual Installation

```bash
git clone https://github.com/derekspelledcorrectly/claude-profile-manager.git
cp claude-profile-manager/bin/claude-profile /usr/local/bin/
# Or copy to any directory in your PATH
```

**Note**: Manual installation requires `jq` to be installed: `brew install jq`

## Platform Requirements

- **macOS**: Required (uses keychain services)
- **Claude Code CLI**: Must be installed and configured
- **jq**: JSON parsing tool (auto-installed via Homebrew)

## Documentation

- **[Full Documentation](CLAUDE.md)**: Comprehensive usage guide and technical details
- **[Security Policy](SECURITY.md)**: Security considerations and reporting
- **[Development Guide](DEVELOPMENT.md)**: Development workflows and contribution guidelines

## Usage

### Save Current Authentication as Profile

```bash
# Save credentials for current profile (if you have one active)
claude-profile save

# Save current credentials as a named profile
claude-profile save work
claude-profile s personal

# When overwriting existing profile, you'll be prompted:
# Profile 'work' already exists. Overwrite existing credentials? [y/N]: y
```

### List All Profiles

```bash
claude-profile list
claude-profile ls
```

**Example Output:**
```
Available profiles:
     PROFILE             TYPE          CREATED  LAST USED  STATUS
     console (api)       console       Aug 26   Aug 27     ready
  ➤  subscription (sub)  subscription  Aug 27   Aug 27     expires in 0d 5h
```

The `➤` arrow indicates which profile is currently active. Status shows:
- **Console profiles**: `ready` (when API key available) or `missing`
- **Subscription profiles**: Token expiration details like `expires in 2d 4h` or `expired 3h ago`

### Switch to Profile

```bash
claude-profile switch work
claude-profile sw personal
claude-profile work          # Default action - switch to 'work' profile
```

### Show Current Profile

```bash
claude-profile current
claude-profile cur
```

### Delete Profile

```bash
claude-profile delete old-profile
claude-profile del old-profile
claude-profile rm old-profile
```

### Help

```bash
claude-profile help
claude-profile -h
claude-profile --help
```

## Authentication Methods Supported

- **Console API**: API keys stored securely in macOS keychain
- **Subscription**: OAuth tokens stored securely in macOS keychain

## Important Notes

- **Restart Required**: After switching profiles, restart Claude Code:
  1. Press Ctrl+D twice to exit
  2. Run: `claude -c`

- **Settings Preservation**: Each profile saves and restores Claude settings independently

- **Secure Storage**: Console API keys are stored in encrypted macOS keychain, not in plain text files

## Examples

```bash
# Save your work credentials
claude-profile save work

# Save personal credentials  
claude-profile s personal

# List all saved profiles
claude-profile list

# Switch between profiles
claude-profile work
claude-profile personal

# Check current profile
claude-profile current

# Clean up old profiles
claude-profile delete old-work
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
