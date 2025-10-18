# Development Guide

## Development Workflow

### Local Development Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/derekspelledcorrectly/claude-profile-manager.git
   cd claude-profile-manager
   ```

2. Install development dependencies:
   ```bash
   just install-deps
   ```

3. Validate your development environment:
   ```bash
   just validate-env
   ```

4. Test the local version:
   ```bash
   ./bin/claude-profile help
   ./bin/claude-profile list
   ```

5. Make changes to code in `lib/` or `bin/` directories

6. Run comprehensive tests:
   ```bash
   just test        # Run all tests
   just smoke       # Run smoke tests (quick validation)
   ```

7. Check code quality:
   ```bash
   just lint        # Check linting and formatting
   just format      # Fix formatting issues automatically
   ```

8. Test changes thoroughly with existing profiles

## Justfile Development Commands

This project uses [just](https://github.com/casey/just) for development task automation. Here are the available commands:

### Development Setup
```bash
just install-deps    # Install development dependencies (shellcheck, shfmt, jq)
just validate-env     # Validate development environment setup
```

### Code Quality
```bash
just lint            # Run linting and format checking (default)
just lint-check      # Explicit check-only mode
just lint-fix        # Fix formatting issues automatically
just format          # Alias for lint-fix
just shellcheck      # Run only shellcheck (no formatting)
just shfmt-check     # Run only shfmt format checking
just shfmt-fix       # Run only shfmt format fixing
```

### Testing
```bash
just test            # Run all tests
just smoke           # Run smoke tests (quick validation)
```

### Development Workflows
```bash
just dev             # Quick development cycle: fix formatting, run tests
just qa              # Full quality check: lint, format, test everything
just pre-commit      # Run pre-commit checks (lint + test)
just ci              # Run CI-style checks (lint-check + test)
just fix-all         # Fix all issues and run tests
just quick-fix       # Emergency fix: format code and run smoke tests only
```

### Project Information
```bash
just version         # Show project version
just lint-help       # Show lint script help
just help            # List all available commands (alias: just --list)
```

### Release & Maintenance
```bash
just release         # Create a new release
just clean           # Clean up temporary files and caches
```

## Code Style and Standards

### Shell Script Best Practices
- Use `#!/bin/bash` shebang
- Enable strict error handling where appropriate
- Use `local` for function variables
- Validate all inputs
- Use meaningful function and variable names
- Add comments for complex logic

### Linting and Formatting Infrastructure

The project uses an integrated linting and formatting system:

- **shellcheck**: Static analysis for shell scripts
- **shfmt**: Shell script formatting tool
- **Integrated workflow**: `scripts/lint.sh` provides unified interface
- **Multiple modes**: Check-only, fix mode, individual tool selection
- **CI integration**: Automated checks on all code changes

**Usage via justfile:**
```bash
just lint         # Check everything (shellcheck + shfmt)
just lint-fix     # Fix formatting issues automatically
just shellcheck   # Run only shellcheck
just shfmt-check  # Run only formatting checks
just shfmt-fix    # Run only formatting fixes
```

### Security Guidelines
- Never log or echo sensitive credentials
- Validate all user inputs
- Use secure file permissions

### Documentation Standards
- Keep README.md focused and scannable
- Put detailed technical info in CLAUDE.md
- Document all new features and commands
- Include examples for complex operations
- Update help text in CLI when adding commands

## Testing

### Automated Test Suite

The project includes a comprehensive test suite with the following components:

- **`tests/run.sh`**: Main test runner that executes all test suites
- **`tests/smoke.sh`**: Quick smoke tests for basic functionality validation
- **`tests/core-operations-test.sh`**: Tests core profile operations (save, switch, delete)
- **`tests/error-handling-test.sh`**: Tests error conditions and edge cases
- **`tests/list-command-integration-test.sh`**: Tests list command functionality and output
- **`tests/ui-functionality-test.sh`**: Tests user interface and interaction features
- **`tests/workflow-integration-test.sh`**: Tests complete workflow scenarios

### Running Tests

```bash
# Run all tests
just test
# or
cd tests && ./run.sh

# Run quick smoke tests only
just smoke
# or
cd tests && ./smoke.sh
```

### Manual Testing Checklist
- [ ] `claude-profile save <name>` works with current credentials
- [ ] `claude-profile list` shows correct information with current profile indicator (➤) and appropriate status messages  
- [ ] `claude-profile switch <name>` switches profiles correctly
- [ ] `claude-profile current` shows active profile
- [ ] `claude-profile delete <name>` removes profiles
- [ ] Alias commands work (`ls`, `sw`, `cur`, etc.)
- [ ] Token health detection works for subscription profiles
- [ ] Current profile indicator (➤ arrow) appears next to active profile
- [ ] Console profiles show "ready" status when API key exists
- [ ] Subscription profiles show proper token expiration information
- [ ] Auto-save prompts appear when switching away from subscription profiles
- [ ] Error handling works gracefully
- [ ] Help text is accurate and complete

### Edge Cases to Test
- Switching between same profile (should be silent)
- Invalid profile names
- Missing keychain entries
- Corrupted profile files  
- Permission issues with profile directory

## Project Architecture

### Code Organization

The project follows a modular architecture with clear separation of concerns:

```
claude-profile-manager/
├── bin/
│   └── claude-profile              # Main CLI entry point
├── lib/
│   ├── profile-core.sh            # Core profile management logic
│   └── keychain-utils.sh          # Secure keychain operations
├── scripts/
│   └── validate-dev-env.sh        # Development environment validation
└── tests/
    └── basic-test.sh               # Basic functionality tests
```

#### Component Responsibilities

**`bin/claude-profile`**: Main CLI entry point
- Argument parsing and command routing
- User interface and help text  
- Delegates all business logic to library functions

**`lib/profile-core.sh`**: Core profile management logic
- Profile validation and creation
- Authentication method detection
- Profile switching and deletion
- Alias management
- OAuth token health analysis

**`lib/keychain-utils.sh`**: Secure keychain operations  
- Cross-platform keychain abstraction
- Secure credential storage and retrieval
- Claude-specific keychain service integration
- Timing attack prevention measures

### Data Storage Architecture

#### Profile Storage Structure
```
~/.claude/profiles/
├── .current                       # Current active profile name
├── .aliases                       # Profile aliases (alias=profile format)
├── .audit.log                     # Audit log (if CLAUDE_PROFILE_LOG=true)
├── work.json                      # Profile metadata (JSON)
└── personal.json                  # Profile metadata (JSON)
```

#### Profile Metadata Format
```json
{
  "created": "2024-01-01T00:00:00Z",
  "auth_method": "subscription|console",
  "last_used": "2024-01-01T12:00:00Z"
}
```

#### Keychain Integration  
- **Console API**: Service "Claude Code", Account `${USER}`
- **Subscription**: Service "Claude Code-credentials", Account `${USER}`  
- **Profile Backups**: Service "Claude Profile Manager", Account `<profile-name>`



### OAuth Token Architecture

#### Claude OAuth Token Structure
Claude subscription tokens are proprietary JSON objects (not JWTs):
```json
{
  "claudeAiOauth": {
    "accessToken": {
      "token": "...",
      "expiresAt": 1704067200000
    },
    "refreshToken": "...",
    "tokenType": "Bearer"
  }
}
```

#### Token Health Monitoring
- **Expiration Detection**: Parses `expiresAt` millisecond timestamps
- **Health Status**: "expires in 2d 4h", "expires soon (30m)", "expired 3h ago"
- **Graceful Degradation**: Falls back to "valid" for unparseable tokens
- **Multiple Field Support**: Searches various expiration field names

### Alias System Architecture

#### Alias Resolution Chain
1. **Direct Match**: Check if input is exact profile name
2. **Alias Lookup**: Search `.aliases` file for matching alias
3. **Validation**: Validate resolved profile name
4. **Return**: Original input if no alias found

#### Alias File Format
```
api=console
sub=subscription  
w=work
p=personal
```



## Troubleshooting Development Issues

### Common Problems

**Script won't execute**: Check permissions with `chmod +x bin/claude-profile`

**"jq: command not found"**: Install with `brew install jq`

**Keychain access denied**: Make sure you're running on macOS and have keychain access

**Profile validation fails**: Check the `validate_profile_name()` function in `lib/profile-core.sh` for allowed characters

**Tests fail**: Run `./scripts/validate-dev-env.sh` to check your setup

### Debug Mode
Enable debug output:
```bash
CLAUDE_PROFILE_DEBUG=true ./bin/claude-profile <command>
```