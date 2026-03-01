#!/bin/bash
# =============================================================================
# ci_post_clone.sh — Xcode Cloud: runs after repository clone
# FamilyTreeV2 — Al-Mohammad Ali Family Tree App
# =============================================================================

set -e

echo "========================================"
echo "FamilyTreeV2 — Post Clone Setup"
echo "========================================"
echo "Build Number: ${CI_BUILD_NUMBER:-local}"
echo "Branch: ${CI_BRANCH:-unknown}"
echo "Commit: ${CI_COMMIT:-unknown}"
echo "Workflow: ${CI_WORKFLOW:-unknown}"
echo "========================================"

# --------------------------------------------------
# 1. Resolve Swift Package Manager dependencies
# --------------------------------------------------
echo "Resolving Swift packages..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodebuild -resolvePackageDependencies \
    -project FamilyTreeV2.xcodeproj \
    -scheme FamilyTreeV2 \
    -clonedSourcePackagesDirPath "$CI_DERIVED_DATA_PATH/SourcePackages"
echo "Swift packages resolved."

# --------------------------------------------------
# 2. Set build number from Xcode Cloud build number
# --------------------------------------------------
if [ -n "$CI_BUILD_NUMBER" ]; then
    echo "Setting build number to $CI_BUILD_NUMBER..."

    PLIST_PATH="$CI_PRIMARY_REPOSITORY_PATH/FamilyTreeV2/FamilyTreeV2/Info.plist"

    if [ -f "$PLIST_PATH" ]; then
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $CI_BUILD_NUMBER" "$PLIST_PATH" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CI_BUILD_NUMBER" "$PLIST_PATH"
        echo "Build number set to $CI_BUILD_NUMBER"
    else
        echo "Info.plist not found at $PLIST_PATH — skipping build number update"
    fi
fi

echo "Post-clone setup complete."
