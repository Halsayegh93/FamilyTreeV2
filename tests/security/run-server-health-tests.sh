#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc FamilyTreeV2/FamilyTreeV2/Core/ServerHealthModels.swift tests/security/server-health-tests.swift -o "$work/server-health-tests"
"$work/server-health-tests"
