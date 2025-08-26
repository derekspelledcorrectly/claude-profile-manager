# Security Policy

## Reporting Security Issues

If you find a security issue, please email the maintainer rather than creating a public GitHub issue.

## Security Overview

This tool directly modifies Claude's authentication data in your macOS keychain. Here's what you should know:

### What this tool does
- Reads and writes credentials in your macOS keychain
- Creates profile backups of your Claude authentication
- Switches between different Claude authentication methods

### Security measures implemented
- All credentials stored in encrypted macOS keychain (not files)
- Input validation prevents path traversal and injection attacks  
- Secure temporary file operations
- No credentials visible in process lists

### Limitations
- Inherits macOS keychain security model
- Requires trust in this tool's keychain access
- Only as secure as your macOS user account
- Dependent on Claude Code CLI's security practices

### Best practices
- Only install from trusted sources (Homebrew recommended)
- Keep your macOS system updated
- Use on systems you control and trust
- Review what profiles you create and delete unused ones

### If something goes wrong
If you suspect credential compromise:
1. Revoke your Claude credentials and re-authenticate
2. Delete affected profiles with `claude-profile delete <name>`
3. Report the issue if it's tool-related