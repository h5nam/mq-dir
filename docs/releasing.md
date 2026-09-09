# Releasing mq-dir

The local script prepares and pushes a release commit and tag. The release workflow checks out that exact tag, runs release-tool/core/app-service tests, and verifies the built bundle before signing or publishing. No local notarization setup is used by this workflow.

## Preparing a release

Start on a clean `main` that matches `origin/main`. Commit new files as well as tracked edits. Versions use SemVer without a leading `v` or `+build` suffix; the version must advance past both the source and published appcast.

```sh
Scripts/release.sh --dry-run 0.3.0
Scripts/release.sh 0.3.0
```

The dry run reads local refs only and does not edit, fetch, commit, tag or push. A real run fetches `origin/main` and tags first, increments the build above the source/appcast maximum, regenerates the project, creates a DCO-signed commit and annotated tag, then pushes both refs atomically. If the remote changes meanwhile, the atomic push fails rather than publishing only one ref. After inspecting such a failure, push the existing prepared refs together; do not create another tag for the same version.

`project.yml` owns `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Both Info.plist version fields reference those settings. The shipped 0.2.0 bundle/appcast used build 7; the previously unused build-setting value 8 was aligned to 7 without changing the shipped build. The next release gets a new monotonic build number.

## Dependency resolution

`Config/Package.resolved` contains the reviewed app package versions and commit revisions, including transitive dependencies. Generate with:

```sh
Scripts/generate-project.sh
```

This restores the lock into the generated Xcode project. CI, nightly and release builds pass `-onlyUsePackageVersionsFromResolvedFile`. Raw `xcodegen generate` alone does not restore the tracked lock. `Package.swift` remains the independent core-only test manifest.

To deliberately update dependencies, generate the project, resolve the intended versions in Xcode, review the resulting package/version/revision changes, then copy the generated lock back to `Config/Package.resolved` and run both core and app-service tests. Do not casually regenerate the tracked lock on each build. The existing Sparkle signing CLI stays fixed at 2.6.4; it is separate from the app's locked Sparkle framework and is not upgraded by this change.

## CI credentials

Repository secrets used only in the publishing job:

| Secret | Purpose |
|---|---|
| `DEVELOPMENT_TEAM` | Developer ID team |
| `APPLE_CERTIFICATE_BASE64` | Base64 Developer ID PKCS#12 certificate and private key |
| `APPLE_CERTIFICATE_PASSWORD` | PKCS#12 password |
| `APPLE_KEYCHAIN_PASSWORD` | Ephemeral runner keychain password |
| `APPLE_API_KEY_BASE64` | Base64 App Store Connect API key |
| `APPLE_API_KEY_ID` | API key identifier |
| `APPLE_API_ISSUER_ID` | API issuer |
| `SPARKLE_ED_PRIVATE_KEY` | Base64 exported Sparkle EdDSA key matching the app's public key |
| `HOMEBREW_TAP_TOKEN` | Optional token for the separate tap; missing token skips mirroring |

The verification job has read-only repository permission and receives no signing secrets. Certificate and notarization files are removed by an always-run cleanup step. GitHub's token needs repository contents write permission for publishing and the appcast/cask commit. Branch protection may require adapting that final commit to the repository's authorized merge process.

## Published assets and retries

Each new release is created as a draft, receives the DMG, ZIP, `release.json`, and `SHA256SUMS`, then becomes public only after every upload succeeds. The manifest records version, build, exact tag commit, artifact hashes/sizes, and the DMG's Sparkle signature. Bundle metadata is checked after both the test build and signed export. Hash verification checks that downloaded bytes agree with the manifest; it is not a substitute for macOS code-signing or Sparkle's cryptographic verification.

All release workflows share a concurrency group because they update the same appcast and cask. A release older than the current channel is rejected before publication. Existing appcast version/build collisions or differing signatures are errors; identical retries do not add another item. Retrying an already listed older release does not roll back the newer cask.

If publication succeeded but the primary appcast/cask push failed, rerun the workflow with the same existing version. The workflow downloads and verifies the published files, skips rebuilding/signing/uploading, and retries the metadata work. API failures stop the job rather than being interpreted as "release not found".

The separate Homebrew tap is an optional mirror. Missing, expired or under-scoped `HOMEBREW_TAP_TOKEN` credentials emit a workflow warning without invalidating an already signed, notarized and published release. Repair the token and rerun the same version to retry the mirror; inspect the warning rather than assuming the tap was updated.

An incomplete draft stops recovery for inspection; the workflow never blindly overwrites it. A legacy release without `release.json` cannot use automatic recovery. Inspect and repair that historical release separately or issue a new version. Do not replace a published version's assets to recover a failed build. The workflow's refusal to overwrite is independent of whether server-side immutable releases are enabled.

## Local verification

```sh
python3 -m unittest discover -s Tests/release -v
python3 Scripts/release_tools.py source
swift test
Scripts/generate-project.sh
xcodebuild -project mq-dir.xcodeproj -scheme mq-dir -configuration Debug \
  -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO test
```

Release tests use standard Python, Bash, Git and macOS's Ruby/YAML parser. They run the release script against a temporary local bare repository and execute workflow shell steps with a fake `gh`; they never contact or publish to GitHub. Signed archive, notarization, upload, protected-branch push and actual Sparkle update installation still require a credentialed release run to validate end to end.
