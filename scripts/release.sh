#!/bin/bash
#
# Release Automation Script for Claude Profile Manager
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.2.0
#
# This script:
# 1. Updates version in CLAUDE.md
# 2. Creates git tag and GitHub release
# 3. Updates homebrew formula with new URL/SHA256
# 4. Tests the installation
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
	echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
	echo -e "${RED}✗ $1${NC}"
}

print_info() {
	echo -e "${YELLOW}→ $1${NC}"
}

# Check arguments
if [[ $# -ne 1 ]]; then
	echo "Usage: $0 <version>"
	echo "Example: $0 1.2.0"
	exit 1
fi

VERSION="$1"

# Enhanced input sanitization
VERSION=$(printf '%s' "$VERSION" | tr -cd '0-9.')
if [[ ${#VERSION} -gt 10 ]]; then
	print_error "Version string too long"
	exit 1
fi

# Validate version format (basic check)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	print_error "Version must be in format X.Y.Z (e.g., 1.2.0)"
	exit 1
fi

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOMEBREW_TAP_ROOT="$PROJECT_ROOT/../homebrew-claude-tools"

# Verify we're in the right directories
if [[ ! -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
	print_error "Cannot find CLAUDE.md - are we in the right directory?"
	exit 1
fi

if [[ ! -f "$HOMEBREW_TAP_ROOT/Formula/claude-profile-manager.rb" ]]; then
	print_error "Cannot find homebrew tap at $HOMEBREW_TAP_ROOT"
	exit 1
fi

print_info "Starting release process for version $VERSION"

# Step 1: Update version in CLAUDE.md
print_info "Updating version in CLAUDE.md"
sed -i '' -E "s/\*\*Current Version\*\*: [0-9]+\.[0-9]+\.[0-9]+ - .*/\*\*Current Version\*\*: $VERSION - Enhanced Release ✅/" "$PROJECT_ROOT/CLAUDE.md"
print_success "Version updated in CLAUDE.md"

# Step 2: Commit version change and create tag
print_info "Creating git tag and GitHub release"
cd "$PROJECT_ROOT"
git add CLAUDE.md
git commit -m "Bump version to $VERSION for release"

# Create tag
git tag "v$VERSION"

print_info "Pushing changes and tag (you'll need to confirm this)"
echo "Please run: git push origin main && git push origin v$VERSION"
echo "Press Enter when done..."
read -r

# Step 3: Create GitHub release
print_info "Creating GitHub release"

# GitHub authentication validation
if ! gh auth status >/dev/null 2>&1; then
	print_error "GitHub CLI not authenticated. Run: gh auth login"
	exit 1
fi

gh release create "v$VERSION" --title "v$VERSION" --notes "## Changes

Release $VERSION with latest improvements and features.

See commit history for detailed changes."

print_success "GitHub release created"

# Step 4: Calculate SHA256 for new release
print_info "Calculating SHA256 for GitHub release tarball"
GITHUB_URL="https://github.com/derekspelledcorrectly/claude-profile-manager/archive/refs/tags/v$VERSION.tar.gz"
SHA256=$(curl -sL "$GITHUB_URL" | shasum -a 256 | cut -d' ' -f1)

# SHA256 format validation
if ! [[ "$SHA256" =~ ^[a-f0-9]{64}$ ]]; then
	print_error "Invalid SHA256 format: $SHA256"
	exit 1
fi

print_success "SHA256 calculated: $SHA256"

# Step 5: Update homebrew formula
print_info "Updating homebrew formula"
cd "$HOMEBREW_TAP_ROOT"

# Update the formula
sed -i '' "s|url \".*\"|url \"$GITHUB_URL\"|" Formula/claude-profile-manager.rb
sed -i '' "s/version \"[^\"]*\"/version \"$VERSION\"/" Formula/claude-profile-manager.rb
sed -i '' "s/sha256 \"[^\"]*\"/sha256 \"$SHA256\"/" Formula/claude-profile-manager.rb

# Commit formula changes
git add Formula/claude-profile-manager.rb
git commit -m "Update claude-profile-manager to v$VERSION

- Update version to $VERSION
- Update GitHub release URL and SHA256"

print_info "Pushing homebrew formula changes (you'll need to confirm this)"
echo "Please run: cd $HOMEBREW_TAP_ROOT && git push origin main"
echo "Press Enter when done..."
read -r

# Step 6: Test installation
print_info "Testing new installation"
cd "$PROJECT_ROOT"

# Refresh tap and reinstall
brew untap derekspelledcorrectly/claude-tools 2>/dev/null || true
brew tap derekspelledcorrectly/claude-tools
brew uninstall claude-profile-manager 2>/dev/null || true
brew install derekspelledcorrectly/claude-tools/claude-profile-manager

# Verify installation
if claude-profile --help >/dev/null 2>&1; then
	print_success "Installation verified"
else
	print_error "Installation verification failed"
	exit 1
fi

# Run tests
print_info "Running test suite"
if ./tests/run.sh >/dev/null 2>&1; then
	print_success "All tests passed"
else
	print_error "Some tests failed"
	exit 1
fi

print_success "Release $VERSION completed successfully!"
print_info "Users can now install with: brew install derekspelledcorrectly/claude-tools/claude-profile-manager"
