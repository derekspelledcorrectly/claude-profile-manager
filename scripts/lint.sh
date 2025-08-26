#!/bin/bash
#
# Linting Script for Claude Profile Manager
# Runs shellcheck on all shell scripts in the project
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Claude Profile Manager - Linting${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

main() {
    print_header
    
    local project_root
    project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Check if shellcheck is available
    if ! command -v shellcheck >/dev/null 2>&1; then
        print_error "shellcheck not found"
        echo "  Install with: brew install shellcheck"
        exit 1
    fi
    
    print_info "Running shellcheck on all shell scripts..."
    echo
    
    # Find all shell scripts to lint
    local shell_files=(
        "$project_root/bin/claude-profile"
        "$project_root/lib/profile-core.sh"
        "$project_root/lib/keychain-utils.sh"
        "$project_root/scripts/validate-dev-env.sh"
        "$project_root/scripts/lint.sh"
        "$project_root/tests/basic-test.sh"
    )
    
    local total_files=0
    local passed_files=0
    local failed_files=0
    
    for file in "${shell_files[@]}"; do
        if [[ -f "$file" ]]; then
            total_files=$((total_files + 1))
            local relative_path="${file#"$project_root"/}"
            
            echo -n "Checking $relative_path... "
            
            if shellcheck -e SC1091 -x "$file" >/dev/null 2>&1; then
                echo -e "${GREEN}✓${NC}"
                passed_files=$((passed_files + 1))
            else
                echo -e "${RED}✗${NC}"
                failed_files=$((failed_files + 1))
                
                # Show the actual shellcheck output
                echo -e "${YELLOW}Issues found in $relative_path:${NC}"
                shellcheck -e SC1091 -x "$file" | sed 's/^/  /'
                echo
            fi
        fi
    done
    
    echo
    echo "Summary:"
    echo "  Total files checked: $total_files"
    echo "  Passed: $passed_files"
    echo "  Failed: $failed_files"
    
    if [[ $failed_files -eq 0 ]]; then
        print_success "All shell scripts passed linting!"
        exit 0
    else
        print_error "$failed_files file(s) failed linting"
        exit 1
    fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi