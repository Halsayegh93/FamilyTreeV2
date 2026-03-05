#!/bin/bash
# =============================================================================
# ci_post_xcodebuild.sh — Xcode Cloud: runs after xcodebuild
# FamilyTreeV2 — Al-Mohammad Ali Family Tree App
# =============================================================================

echo "========================================"
echo "FamilyTreeV2 — Post-Build Summary"
echo "========================================"
echo "Build Number: ${CI_BUILD_NUMBER:-local}"
echo "Build Result: ${CI_XCODEBUILD_EXIT_CODE:-unknown}"
echo "Archive Path: ${CI_ARCHIVE_PATH:-none}"
echo "========================================"

# --------------------------------------------------
# 1. Report build result
# --------------------------------------------------
if [ "${CI_XCODEBUILD_EXIT_CODE}" = "0" ]; then
    echo "BUILD SUCCEEDED"
else
    echo "BUILD FAILED (exit code: ${CI_XCODEBUILD_EXIT_CODE})"
fi

# --------------------------------------------------
# 2. Show archive details if available
# --------------------------------------------------
if [ -n "$CI_ARCHIVE_PATH" ] && [ -d "$CI_ARCHIVE_PATH" ]; then
    echo ""
    echo "Archive details:"
    APP_PATH=$(find "$CI_ARCHIVE_PATH" -name "*.app" -maxdepth 3 2>/dev/null | head -1)
    if [ -n "$APP_PATH" ]; then
        APP_SIZE=$(du -sh "$APP_PATH" 2>/dev/null | cut -f1)
        echo "  App: $(basename "$APP_PATH")"
        echo "  Size: $APP_SIZE"
    fi
fi

# --------------------------------------------------
# 3. Count Swift source files
# --------------------------------------------------
echo ""
SWIFT_COUNT=$(find "$CI_PRIMARY_REPOSITORY_PATH/FamilyTreeV2" -name "*.swift" -not -name "* 2*" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "Swift source files: $SWIFT_COUNT"

# --------------------------------------------------
# 4. Build duration note
# --------------------------------------------------
echo ""
echo "Branch: ${CI_BRANCH:-unknown}"
echo "Commit: ${CI_COMMIT:-unknown}"
echo ""
echo "Post-build complete."
