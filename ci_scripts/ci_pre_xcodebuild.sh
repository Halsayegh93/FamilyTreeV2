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
    "FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2App.swift"
    "FamilyTreeV2/FamilyTreeV2/Core/SupabaseConfig.swift"
    "FamilyTreeV2/FamilyTreeV2/Components/Shared/DesignSystem.swift"
    "FamilyTreeV2/FamilyTreeV2/ViewModels/Auth/AuthViewModel.swift"
    "FamilyTreeV2/FamilyTreeV2/Models/Tree/FamilyMember.swift"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    FULL_PATH="$CI_PRIMARY_REPOSITORY_PATH/$file"
    if [ -f "$FULL_PATH" ]; then
        echo "  OK: $file"
    else
        echo "  MISSING: $file"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -gt 0 ]; then
    echo "WARNING: $MISSING required file(s) missing"
else
    echo "All required files present."
fi

# --------------------------------------------------
# 2. Check for duplicate files (common issue)
# --------------------------------------------------
echo ""
echo "Checking for duplicate files..."
DUPES=$(find "$CI_PRIMARY_REPOSITORY_PATH/FamilyTreeV2" -name "* 2.*" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$DUPES" -gt 0 ]; then
    echo "WARNING: Found $DUPES duplicate files (with ' 2' suffix). These may cause build errors."
    find "$CI_PRIMARY_REPOSITORY_PATH/FamilyTreeV2" -name "* 2.*" -type f 2>/dev/null
else
    echo "No duplicate files found."
fi

# --------------------------------------------------
# 3. Disk space check
# --------------------------------------------------
echo ""
echo "Disk space available:"
df -h / | tail -1 | awk '{print "  " $4 " free"}'

echo ""
echo "Pre-build checks complete."
