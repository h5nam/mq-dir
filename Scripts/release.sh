#!/usr/bin/env bash
# Prepare a release commit and atomically push main + its tag. CI publishes it.
# --dry-run validates local state without editing, fetching, committing or pushing.
set -euo pipefail
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi
VERSION="${1:?Usage: Scripts/release.sh [--dry-run] <version>}"
[[ $# -eq 1 ]] || { echo "Unexpected release arguments" >&2; exit 1; }
cd "$(dirname "$0")/.."
fail() { echo "release: $*" >&2; exit 1; }
python3 Scripts/release_tools.py version --version "$VERSION" >/dev/null
[[ "$(git branch --show-current)" == "main" ]] || fail "Release from main, not another branch or detached HEAD."
[[ -z "$(git status --porcelain)" ]] || fail "Commit all tracked and untracked changes before releasing."
if ! $DRY_RUN; then
    command -v xcodegen >/dev/null || fail "XcodeGen is required."
    git fetch origin main --tags
fi
git show-ref --verify --quiet refs/remotes/origin/main || fail "origin/main is missing; fetch it first."
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main must match origin/main before the release bump."
if git show-ref --verify --quiet "refs/tags/v${VERSION}"; then
    fail "Tag v${VERSION} already exists; do not reuse a release version."
fi
# Validate the bump without mutating project.yml on dry runs or invalid input.
python3 Scripts/release_tools.py plan --version "$VERSION"
if $DRY_RUN; then
    echo "Dry run complete; no files, refs or remote state changed."
    exit 0
fi
python3 Scripts/release_tools.py bump --version "$VERSION"
Scripts/generate-project.sh
python3 Scripts/release_tools.py source --version "$VERSION"
git add project.yml Sources/mq-dir/Info.plist
git commit -s -m "Release v${VERSION}"
git tag -a "v${VERSION}" -m "v${VERSION}"
git push --atomic origin HEAD:refs/heads/main "refs/tags/v${VERSION}"
echo "Release tag pushed. CI will verify, sign and publish v${VERSION}."
