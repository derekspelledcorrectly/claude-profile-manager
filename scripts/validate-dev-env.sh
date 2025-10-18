#!/bin/bash
#
# Development Environment Validation Script
# Validates that all required dependencies and tools are available for development
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global validation status
VALIDATION_FAILED=0

print_header() {
	echo -e "${BLUE}============================================${NC}"
	echo -e "${BLUE}  Claude Profile Manager - Dev Environment${NC}"
	echo -e "${BLUE}  Validation Script                        ${NC}"
	echo -e "${BLUE}============================================${NC}"
	echo
}

print_success() {
	echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
	echo -e "${RED}✗${NC} $1"
	VALIDATION_FAILED=1
}

print_info() {
	echo -e "${BLUE}ℹ${NC} $1"
}

check_command() {
	local cmd="$1"
	local description="$2"
	local install_hint="${3:-}"

	if command -v "$cmd" >/dev/null 2>&1; then
		local version=""
		case "$cmd" in
		"jq")
			version=$(jq --version 2>/dev/null | head -1)
			;;
		"security")
			version="(macOS system tool)"
			;;
		"bash")
			version=$(bash --version | head -1 | cut -d' ' -f4)
			;;
		"claude")
			version=$(claude --version 2>/dev/null | head -1 || echo "installed")
			;;
		"shellcheck")
			version=$(shellcheck --version | grep "version:" | cut -d' ' -f2 2>/dev/null || echo "installed")
			;;
		"shfmt")
			version=$(shfmt --version 2>/dev/null || echo "installed")
			;;
		esac
		print_success "$description - $version"
		return 0
	else
		print_error "$description not found"
		if [[ -n "$install_hint" ]]; then
			echo "  Install with: $install_hint"
		fi
		return 1
	fi
}

check_bash_version() {
	local bash_version
	bash_version=$(bash --version | head -1 | sed 's/.*version \([0-9]*\)\.\([0-9]*\).*/\1\2/')

	if [[ "$bash_version" -ge 40 ]]; then
		print_success "Bash version is 4.0+ (required)"
		return 0
	else
		print_error "Bash version is below 4.0 (required)"
		echo "  Current: $(bash --version | head -1)"
		echo "  Install newer Bash with: brew install bash"
		return 1
	fi
}

check_macos_keychain() {
	if ! security list-keychains >/dev/null 2>&1; then
		print_error "macOS keychain services not accessible"
		return 1
	fi

	if ! security list-keychains | grep -q "login.keychain"; then
		print_error "Login keychain not found"
		return 1
	fi

	print_success "macOS keychain services accessible"
	return 0
}

check_claude_code_installation() {
	if ! command -v claude >/dev/null 2>&1; then
		print_error "Claude Code CLI not installed"
		echo "  Install from: https://claude.ai/code"
		return 1
	fi

	# Check if Claude Code can be executed
	if ! claude --version >/dev/null 2>&1; then
		print_warning "Claude Code installed but may not be properly configured"
		echo "  Try running: claude --help"
		return 0
	fi

	print_success "Claude Code CLI properly installed"
	return 0
}

check_project_structure() {
	local project_root
	project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

	# Check for required files
	local required_files=(
		"bin/claude-profile"
		"lib/profile-core.sh"
		"lib/keychain-utils.sh"
	)

	for file in "${required_files[@]}"; do
		if [[ -f "$project_root/$file" ]]; then
			print_success "Found required file: $file"
		else
			print_error "Missing required file: $file"
		fi
	done

	# Check if main script is executable
	if [[ -x "$project_root/bin/claude-profile" ]]; then
		print_success "Main script is executable"
	else
		print_warning "Main script may not be executable"
		echo "  Fix with: chmod +x $project_root/bin/claude-profile"
	fi
}

check_development_tools() {
	echo
	echo -e "${BLUE}Checking Development Tools...${NC}"

	check_command "shellcheck" "ShellCheck (bash linting)" "brew install shellcheck"
	check_command "shfmt" "shfmt (shell formatter)" "brew install shfmt"
	check_command "git" "Git version control" "already installed on macOS"

}

check_claude_authentication() {
	echo
	echo -e "${BLUE}Checking Claude Authentication...${NC}"

	local username
	username=$(whoami)

	# Check for console API key
	if security find-generic-password -a "$username" -s "Claude Code" >/dev/null 2>&1; then
		print_success "Console API authentication configured"
	else
		print_info "Console API authentication not found (optional)"
	fi

	# Check for subscription credentials
	if security find-generic-password -a "$username" -s "Claude Code-credentials" >/dev/null 2>&1; then
		print_success "Subscription authentication configured"
	else
		print_info "Subscription authentication not found (optional)"
	fi

	if ! security find-generic-password -a "$username" -s "Claude Code" >/dev/null 2>&1 &&
		! security find-generic-password -a "$username" -s "Claude Code-credentials" >/dev/null 2>&1; then
		print_warning "No Claude authentication configured"
		echo "  Authenticate with Claude Code first: claude -c"
	fi
}

run_smoke_test() {
	echo
	echo -e "${BLUE}Running Smoke Test...${NC}"

	local project_root
	project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

	# Test basic script execution
	if "$project_root/bin/claude-profile" --help >/dev/null 2>&1; then
		print_success "Main script executes without errors"
	else
		print_error "Main script failed smoke test"
		echo "  Try running: $project_root/bin/claude-profile --help"
	fi

	# Test validation functions by sourcing the library
	if bash -c "source '$project_root/lib/profile-core.sh'; validate_profile_name 'test-name'" >/dev/null 2>&1; then
		print_success "Core validation functions working"
	else
		print_error "Core validation functions failed"
	fi
}

check_homebrew_formula_setup() {
	echo
	echo -e "${BLUE}Checking Homebrew Formula Setup...${NC}"

	local project_root
	project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

	if [[ -d "$project_root/Formula" ]] && [[ -z "$(ls -A "$project_root/Formula" 2>/dev/null)" ]]; then
		print_warning "Formula directory exists but is empty"
		echo "  Either populate it or remove it to avoid confusion"
	fi

	# Check if user has the tap installed
	if brew tap | grep -q "derekspelledcorrectly/claude-tools"; then
		print_success "Homebrew tap is installed"

		# Check if the formula is available
		if brew list claude-profile-manager >/dev/null 2>&1; then
			print_info "Formula is installed via Homebrew"
			local installed_version
			installed_version=$(brew list --versions claude-profile-manager | head -1)
			echo "  $installed_version"
		else
			print_info "Tap installed but formula not installed"
		fi
	else
		print_info "Homebrew tap not installed (expected for development)"
		echo "  Production install: brew tap derekspelledcorrectly/claude-tools && brew install claude-profile-manager"
	fi
}

main() {
	print_header

	echo -e "${BLUE}Checking Core Dependencies...${NC}"
	check_bash_version
	check_command "jq" "jq (JSON processor)" "brew install jq"
	check_command "security" "macOS security command" "built into macOS"
	check_macos_keychain
	check_claude_code_installation

	echo
	echo -e "${BLUE}Checking Project Structure...${NC}"
	check_project_structure

	check_development_tools
	check_claude_authentication
	check_homebrew_formula_setup
	run_smoke_test

	echo
	echo -e "${BLUE}============================================${NC}"
	if [[ $VALIDATION_FAILED -eq 0 ]]; then
		echo -e "${GREEN}✓ Development environment validation PASSED${NC}"
		echo -e "${GREEN}  All required dependencies are available${NC}"
		echo -e "${GREEN}  Ready for development!${NC}"
	else
		echo -e "${RED}✗ Development environment validation FAILED${NC}"
		echo -e "${RED}  Please fix the issues above before proceeding${NC}"
		echo
		echo "Common fixes:"
		echo "  • Install missing tools with Homebrew: brew install <tool>"
		echo "  • Set up Claude authentication: claude -c"
		echo "  • Check file permissions: chmod +x bin/claude-profile"
	fi
	echo -e "${BLUE}============================================${NC}"

	exit $VALIDATION_FAILED
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
