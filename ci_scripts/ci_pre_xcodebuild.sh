#!/bin/sh

# ci_pre_xcodebuild.sh — Runs before xcodebuild (build, test, or archive).
#
# Environment variables available:
#   CI_WORKSPACE          — path to the cloned repo
#   CI_PRODUCT            — product name
#   CI_XCODEBUILD_ACTION  — build / test / archive
#   CI_BRANCH             — branch name
#   CI_TAG                — tag name (if triggered by tag)
#   CI_COMMIT             — commit SHA

set -e

echo "🔧 Pre-xcodebuild: action=${CI_XCODEBUILD_ACTION:-unknown}"

# Run SwiftLint if available (warnings only, don't fail the build)
if command -v swiftlint &>/dev/null; then
    echo "🔍 Running SwiftLint..."
    cd "$CI_WORKSPACE"
    swiftlint lint --quiet || true
fi

echo "✅ Pre-xcodebuild complete"
