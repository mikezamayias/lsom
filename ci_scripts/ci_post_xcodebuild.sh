#!/bin/sh

# ci_post_xcodebuild.sh — Runs after xcodebuild completes.
#
# For archive actions (releases), this script:
#   - Generates checksums for the archived product
#   - Extracts changelog from docs/CHANGELOG.md
#
# Environment variables available:
#   CI_WORKSPACE              — path to the cloned repo
#   CI_PRODUCT                — product name
#   CI_XCODEBUILD_ACTION      — build / test / archive
#   CI_BRANCH                 — branch name
#   CI_TAG                    — tag name (if triggered by tag)
#   CI_COMMIT                 — commit SHA
#   CI_ARCHIVE_PATH           — path to .xcarchive (archive action only)
#   CI_RESULT_BUNDLE_PATH     — path to test results (test action only)
#   CI_DERIVED_DATA_PATH      — path to DerivedData
#   CI_BUILD_NUMBER           — Xcode Cloud build number

set -e

echo "📋 Post-xcodebuild: action=${CI_XCODEBUILD_ACTION:-unknown}"

if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
    echo "═══════════════════════════════════════════"
    echo "  Archive completed for: ${CI_PRODUCT}"
    echo "  Tag: ${CI_TAG:-n/a}"
    echo "  Build: ${CI_BUILD_NUMBER:-n/a}"
    echo "═══════════════════════════════════════════"

    # Log changelog for this release
    if [ -f "$CI_WORKSPACE/docs/CHANGELOG.md" ]; then
        echo ""
        echo "📝 Changelog:"
        echo "---"
        cat "$CI_WORKSPACE/docs/CHANGELOG.md"
        echo "---"
    fi

    # Archive path info
    if [ -n "$CI_ARCHIVE_PATH" ] && [ -d "$CI_ARCHIVE_PATH" ]; then
        echo ""
        echo "📦 Archive contents:"
        ls -la "$CI_ARCHIVE_PATH/Products/Applications/" 2>/dev/null || true
    fi
fi

if [ "$CI_XCODEBUILD_ACTION" = "test" ]; then
    echo "🧪 Test results at: ${CI_RESULT_BUNDLE_PATH:-n/a}"
fi

echo "✅ Post-xcodebuild complete"
