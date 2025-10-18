# Claude Profile Manager - Development Tasks
# Provides convenient access to linting, formatting, testing, and other development operations

# Default recipe - runs linting and format checking
default: lint

# Show available recipes
help:
    @just --list

# ==============================================================================
# Linting & Formatting
# ==============================================================================

# Run both linting and format checking (most common operation)
lint:
    @echo "🔍 Running lint and format checks..."
    ./scripts/lint.sh

# Explicitly run check-only mode (same as lint, but more explicit)
lint-check:
    @echo "🔍 Running explicit check-only mode..."
    ./scripts/lint.sh --check

# Fix formatting issues automatically
lint-fix:
    @echo "🔧 Fixing formatting issues..."
    ./scripts/lint.sh --fix

# Alias for lint-fix (alternative name)
format: lint-fix

# Run only shellcheck (no formatting checks)
shellcheck:
    @echo "🐚 Running shellcheck only..."
    ./scripts/lint.sh --lint-only

# Run only shfmt format checking (no linting)
shfmt-check:
    @echo "📝 Running shfmt format checking only..."
    ./scripts/lint.sh --format-only

# Run only shfmt format fixing (no linting)
shfmt-fix:
    @echo "📝 Running shfmt format fixing only..."
    ./scripts/lint.sh --format-only --fix

# ==============================================================================
# Testing
# ==============================================================================

# Run all tests
test:
    @echo "🧪 Running all tests..."
    cd tests && ./run.sh

# Run smoke tests (quick validation)
smoke:
    @echo "💨 Running smoke tests..."
    cd tests && ./smoke.sh

# ==============================================================================
# Development Environment
# ==============================================================================

# Validate development environment setup
validate-env:
    @echo "🔍 Validating development environment..."
    ./scripts/validate-dev-env.sh

# Install development dependencies (macOS with Homebrew)
install-deps:
    @echo "📦 Installing development dependencies..."
    @command -v brew >/dev/null 2>&1 || { echo "❌ Homebrew not found. Please install Homebrew first."; exit 1; }
    brew install shellcheck shfmt jq
    @echo "✅ Development dependencies installed"

# ==============================================================================
# Release & Maintenance
# ==============================================================================

# Create a new release (run the release script)
release:
    @echo "🚀 Creating new release..."
    ./scripts/release.sh

# Clean up temporary files and caches
clean:
    @echo "🧹 Cleaning up..."
    find . -name "*.tmp" -type f -delete 2>/dev/null || true
    find . -name ".DS_Store" -type f -delete 2>/dev/null || true
    @echo "✅ Cleanup complete"

# ==============================================================================
# Git & CI Integration
# ==============================================================================

# Run pre-commit checks (lint + test)
pre-commit: lint test
    @echo "✅ Pre-commit checks passed"

# Run CI-style checks (for continuous integration)
ci: lint-check test
    @echo "✅ CI checks passed"

# Fix all issues and run tests (comprehensive cleanup)
fix-all: lint-fix test
    @echo "✅ All issues fixed and tests passed"

# ==============================================================================
# Project Information
# ==============================================================================

# Show project version
version:
    @echo "📋 Claude Profile Manager"
    @grep "Current Version" CLAUDE.md | cut -d':' -f2 | xargs

# Show lint script help
lint-help:
    @echo "📚 Lint script usage:"
    ./scripts/lint.sh --help

# ==============================================================================
# Quick Development Workflows
# ==============================================================================

# Quick development cycle: fix formatting, run tests
dev: lint-fix test

# Full quality check: lint, format, test everything
qa: lint test

# Emergency fix: format code and run smoke tests only
quick-fix: lint-fix smoke