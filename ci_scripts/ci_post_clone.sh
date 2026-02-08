#!/bin/sh

# ci_post_clone.sh — Runs after Xcode Cloud clones the repository.
#
# Use this to install dependencies, configure environment, etc.
# Xcode Cloud provides: git, xcodebuild, swift, ruby, python3, node (via nvm)
#
# Environment variables available:
#   CI_WORKSPACE          — path to the cloned repo
#   CI_PRODUCT            — product name (lsom)
#   CI_XCODEBUILD_ACTION  — build / test / archive
#   CI_BRANCH             — branch name
#   CI_TAG                — tag name (if triggered by tag)
#   CI_COMMIT             — commit SHA

set -e

echo "═══════════════════════════════════════════"
echo "  lsom — Post-Clone Setup"
echo "═══════════════════════════════════════════"
echo "  Branch:  ${CI_BRANCH:-n/a}"
echo "  Tag:     ${CI_TAG:-n/a}"
echo "  Commit:  ${CI_COMMIT:-n/a}"
echo "  Action:  ${CI_XCODEBUILD_ACTION:-n/a}"
echo "═══════════════════════════════════════════"

# Install SwiftLint if available via Homebrew (optional, non-blocking)
if command -v brew &>/dev/null; then
    if ! command -v swiftlint &>/dev/null; then
        echo "📦 Installing SwiftLint..."
        brew install swiftlint 2>/dev/null || echo "⚠️  SwiftLint install skipped"
    fi
fi

echo "✅ Post-clone setup complete"
