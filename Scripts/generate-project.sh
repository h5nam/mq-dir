#!/usr/bin/env bash
# Generate the app project and restore the reviewed dependency resolution.
set -euo pipefail
cd "$(dirname "$0")/.."
test -s Config/Package.resolved
xcodegen generate
LOCK_DIR="mq-dir.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$LOCK_DIR"
cp Config/Package.resolved "$LOCK_DIR/Package.resolved"
