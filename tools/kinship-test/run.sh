#!/bin/bash
# اختبار حساب صلة القرابة خارج التطبيق: يترجم ملف المشروع نفسه مع بدائل بسيطة ويشغّل الحالات.
# التشغيل: bash tools/kinship-test/run.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)/kinship_test
swiftc -swift-version 5 -default-isolation MainActor \
  Stubs.swift ../../FamilyTreeV2/FamilyTreeV2/Core/KinshipCalculator.swift main.swift -o "$OUT"
"$OUT"
