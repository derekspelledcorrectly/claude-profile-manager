#!/bin/bash
#
# Linting & Formatting Script for Claude Profile Manager
# Runs shellcheck and shfmt on all shell scripts in the project
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Mode flags
MODE_FIX=false
MODE_LINT_ONLY=false
MODE_FORMAT_ONLY=false

print_header() {
	local mode_desc="Check"
	if [[ "$MODE_FIX" == true ]]; then
		mode_desc="Fix"
	elif [[ "$MODE_LINT_ONLY" == true ]]; then
		mode_desc="Lint Only"
	elif [[ "$MODE_FORMAT_ONLY" == true ]]; then
		mode_desc="Format Only"
	fi

	echo -e "${BLUE}============================================${NC}"
	echo -e "${BLUE}  Claude Profile Manager - $mode_desc${NC}"
	echo -e "${BLUE}============================================${NC}"
	echo
}

print_success() {
	echo -e "${GREEN}✓${NC} $1"
}

print_error() {
	echo -e "${RED}✗${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
	echo -e "${BLUE}ℹ${NC} $1"
}

print_format_info() {
	echo -e "${CYAN}ℹ${NC} $1"
}

show_usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
  --check        Check code quality (lint + format check) [default]
  --fix          Fix formatting issues automatically
  --format       Alias for --fix
  --lint-only    Run only shellcheck (no formatting)
  --format-only  Run only shfmt (no linting)
  -h, --help     Show this help message

EXAMPLES:
  $0                    # Check everything (default)
  $0 --fix              # Fix formatting issues
  $0 --lint-only        # Only run shellcheck
  $0 --format-only      # Only check formatting

EOF
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--check)
			# Default mode - no action needed
			;;
		--fix | --format)
			MODE_FIX=true
			;;
		--lint-only)
			MODE_LINT_ONLY=true
			;;
		--format-only)
			MODE_FORMAT_ONLY=true
			;;
		-h | --help)
			show_usage
			exit 0
			;;
		*)
			echo "Unknown option: $1"
			show_usage
			exit 1
			;;
		esac
		shift
	done
}

check_dependencies() {
	local missing_deps=()

	if [[ "$MODE_LINT_ONLY" != true && "$MODE_FORMAT_ONLY" == true ]]; then
		# Format-only mode, only need shfmt
		if ! command -v shfmt >/dev/null 2>&1; then
			missing_deps+=("shfmt")
		fi
	elif [[ "$MODE_FORMAT_ONLY" != true && "$MODE_LINT_ONLY" == true ]]; then
		# Lint-only mode, only need shellcheck
		if ! command -v shellcheck >/dev/null 2>&1; then
			missing_deps+=("shellcheck")
		fi
	else
		# Default mode or check mode, need both
		if ! command -v shellcheck >/dev/null 2>&1; then
			missing_deps+=("shellcheck")
		fi
		if ! command -v shfmt >/dev/null 2>&1; then
			missing_deps+=("shfmt")
		fi
	fi

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		print_error "Missing dependencies: ${missing_deps[*]}"
		echo "  Install with: brew install ${missing_deps[*]}"
		exit 1
	fi
}

get_shell_files() {
	local project_root="$1"

	# All shell scripts in the project
	local shell_files=(
		"$project_root/bin/claude-profile"
		"$project_root/lib/profile-core.sh"
		"$project_root/lib/keychain-utils.sh"
		"$project_root/scripts/lint.sh"
		"$project_root/scripts/release.sh"
		"$project_root/scripts/validate-dev-env.sh"
		"$project_root/tests/core-operations-test.sh"
		"$project_root/tests/error-handling-test.sh"
		"$project_root/tests/list-command-integration-test.sh"
		"$project_root/tests/run.sh"
		"$project_root/tests/smoke.sh"
		"$project_root/tests/ui-functionality-test.sh"
		"$project_root/tests/workflow-integration-test.sh"
	)

	# Return only files that exist
	for file in "${shell_files[@]}"; do
		if [[ -f "$file" ]]; then
			echo "$file"
		fi
	done
}

run_shellcheck() {
	local file="$1"
	local project_root="$2"
	local relative_path="${file#"$project_root"/}"

	echo -n "Linting $relative_path... "

	if shellcheck -e SC1091 -e SC2329 -x "$file" >/dev/null 2>&1; then
		echo -e "${GREEN}✓${NC}"
		return 0
	else
		echo -e "${RED}✗${NC}"
		echo -e "${YELLOW}Shellcheck issues in $relative_path:${NC}"
		shellcheck -e SC1091 -e SC2329 -x "$file" | sed 's/^/  /'
		echo
		return 1
	fi
}

run_shfmt_check() {
	local file="$1"
	local project_root="$2"
	local relative_path="${file#"$project_root"/}"

	echo -n "Format check $relative_path... "

	if shfmt -d "$file" >/dev/null 2>&1; then
		echo -e "${GREEN}✓${NC}"
		return 0
	else
		echo -e "${RED}✗${NC}"
		echo -e "${CYAN}Format issues in $relative_path:${NC}"
		shfmt -d "$file" | sed 's/^/  /'
		echo
		return 1
	fi
}

run_shfmt_fix() {
	local file="$1"
	local project_root="$2"
	local relative_path="${file#"$project_root"/}"

	echo -n "Formatting $relative_path... "

	if shfmt -w "$file"; then
		echo -e "${GREEN}✓${NC}"
		return 0
	else
		echo -e "${RED}✗${NC}"
		print_error "Failed to format $relative_path"
		return 1
	fi
}

main() {
	parse_args "$@"
	print_header

	local project_root
	project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

	check_dependencies

	# Get all shell files
	local shell_files=()
	while IFS= read -r file; do
		shell_files+=("$file")
	done < <(get_shell_files "$project_root")

	if [[ ${#shell_files[@]} -eq 0 ]]; then
		print_warning "No shell files found to process"
		exit 0
	fi

	local total_files=${#shell_files[@]}
	local lint_passed=0
	local lint_failed=0
	local format_passed=0
	local format_failed=0
	local format_fixed=0

	# Show what we're doing
	if [[ "$MODE_LINT_ONLY" == true ]]; then
		print_info "Running shellcheck on $total_files shell scripts..."
	elif [[ "$MODE_FORMAT_ONLY" == true ]]; then
		if [[ "$MODE_FIX" == true ]]; then
			print_format_info "Formatting $total_files shell scripts..."
		else
			print_format_info "Checking format of $total_files shell scripts..."
		fi
	else
		if [[ "$MODE_FIX" == true ]]; then
			print_info "Running shellcheck and formatting $total_files shell scripts..."
		else
			print_info "Running shellcheck and format check on $total_files shell scripts..."
		fi
	fi
	echo

	# Process each file
	for file in "${shell_files[@]}"; do
		# Run shellcheck (unless format-only mode)
		if [[ "$MODE_FORMAT_ONLY" != true ]]; then
			if ! run_shellcheck "$file" "$project_root"; then
				lint_failed=$((lint_failed + 1))
			else
				lint_passed=$((lint_passed + 1))
			fi
		fi

		# Run shfmt (unless lint-only mode)
		if [[ "$MODE_LINT_ONLY" != true ]]; then
			if [[ "$MODE_FIX" == true ]]; then
				if ! run_shfmt_fix "$file" "$project_root"; then
					format_failed=$((format_failed + 1))
				else
					format_fixed=$((format_fixed + 1))
				fi
			else
				if ! run_shfmt_check "$file" "$project_root"; then
					format_failed=$((format_failed + 1))
				else
					format_passed=$((format_passed + 1))
				fi
			fi
		fi
	done

	# Print summary
	echo
	echo "Summary:"
	echo "  Total files processed: $total_files"

	if [[ "$MODE_FORMAT_ONLY" != true ]]; then
		echo "  Shellcheck passed: $lint_passed"
		echo "  Shellcheck failed: $lint_failed"
	fi

	if [[ "$MODE_LINT_ONLY" != true ]]; then
		if [[ "$MODE_FIX" == true ]]; then
			echo "  Files formatted: $format_fixed"
			echo "  Format failures: $format_failed"
		else
			echo "  Format check passed: $format_passed"
			echo "  Format check failed: $format_failed"
		fi
	fi

	# Determine exit code and final message
	local exit_code=0
	local has_lint_issues=false
	local has_format_issues=false

	if [[ "$MODE_FORMAT_ONLY" != true && $lint_failed -gt 0 ]]; then
		has_lint_issues=true
		exit_code=1
	fi

	if [[ "$MODE_LINT_ONLY" != true && $format_failed -gt 0 ]]; then
		has_format_issues=true
		exit_code=$((exit_code == 1 ? 3 : 2))
	fi

	echo

	if [[ $exit_code -eq 0 ]]; then
		if [[ "$MODE_FIX" == true ]]; then
			print_success "All files processed successfully!"
		else
			print_success "All checks passed!"
		fi
	else
		if [[ $has_lint_issues == true && $has_format_issues == true ]]; then
			print_error "Found both linting and formatting issues"
		elif [[ $has_lint_issues == true ]]; then
			print_error "Found linting issues"
		else
			print_error "Found formatting issues"
		fi

		if [[ "$MODE_FIX" != true && $has_format_issues == true ]]; then
			echo
			print_format_info "Run '$0 --fix' to automatically fix formatting issues"
		fi
	fi

	exit $exit_code
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
