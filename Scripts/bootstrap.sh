#!/usr/bin/env bash
# mq-dir dev bootstrap — one-shot setup for first-time contributors.
# Idempotent: safe to re-run.

set -euo pipefail

step() {
    printf '\n\033[1;34m==>\033[0m %s\n' "$*"
}

err() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

# 1. Homebrew
step "Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
    err 'Homebrew is required. Install from https://brew.sh and re-run this script.'
fi
echo "brew: $(brew --version | head -n1)"

# 2. XcodeGen
step "Ensuring XcodeGen is installed"
if ! command -v xcodegen >/dev/null 2>&1; then
    brew install xcodegen
else
    echo "xcodegen: $(xcodegen --version)"
fi

# 3. xcodes (Xcode version manager)
step "Ensuring xcodes CLI is installed"
if ! command -v xcodes >/dev/null 2>&1; then
    brew install xcodesorg/made/xcodes
else
    echo "xcodes: $(xcodes version 2>/dev/null || echo 'present')"
fi

# 4. Generate Xcode project from project.yml
step "Generating mq-dir.xcodeproj from project.yml"
cd "$(dirname "$0")/.."
xcodegen generate

step "Done."
cat <<'EOM'

Bootstrap complete.

Next steps:
  • Open mq-dir.xcodeproj in Xcode 16+ and Run.
  • Or run `swift test` for the headless core library tests.

For first-launch on an unsigned local build:
  xattr -d com.apple.quarantine /Applications/mq-dir.app

EOM
