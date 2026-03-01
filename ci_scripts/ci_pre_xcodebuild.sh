#!/bin/bash
# =============================================================================
# ci_pre_xcodebuild.sh — Xcode Cloud: runs before xcodebuild
# FamilyTreeV2 — Al-Mohammad Ali Family Tree App
# =============================================================================

set -e

echo "========================================"
echo "FamilyTreeV2 — Pre-Build"
echo "========================================"
echo "Xcode Version: $(xcodebuild -version | head -1)"
echo "Swift Version: $(swift --version 2>&1 | head -1)"
echo "========================================"

# --------------------------------------------------
# 1. Verify required files exist
# --------------------------------------------------
echo "Verifying project structure..."

REQUIRED_FILES=(
    "FamilyTreeV2.xcodeproj/project.pbxproj"
    "FamilyTreeV2/FamilyTreeV2/FamilyTreeV2App.swift"
    "Core/SupabaseConfig.swift"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$CI_PRIMARY_REPOSITORY_PATH/$file" ]; then
        echo "WARNING: Missing file — $file"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -gt 0 ]; then
    echo "WARNING: $MISSING required file(s) missing"
else
    echo "All required files present."
fi

echo "Pre-build checks complete."
