#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc FamilyTreeV2/FamilyTreeV2/Core/CacheManager.swift tests/security/cache-tests.swift -o "$work/cache-tests"
"$work/cache-tests"
