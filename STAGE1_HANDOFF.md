# Stage 1 implementation handoff

## Objective and guardrails

- Implement Stage 1 of the macOS release-readiness audit.
- Work on the already-active branch `feature/macos-port`. The requested short name `macos-port` is not the branch name present in this checkout; do not switch branches.
- Do not commit or push unless the user explicitly asks.
- Keep this file updated with completed work, verification, blockers, and the exact next action so another local agent can continue after context/token exhaustion.

## Starting point

- Starting commit: `6c6ec97` (`macOS: add System / Light / Dark theme selector in Settings`).
- Initial working tree was clean.
- Audit found that the distributed app refers to `SPUN_SOURCE_DIR` for YouTube helper/setup and demo audio; those files are not in the CMake resource list.
- Jellyfin/Subsonic credential storage invokes Linux `secret-tool`; macOS integration is absent.
- Cider token is written as owner-only plaintext JSON. Consider migrating it to Keychain while retaining a safe migration path.
- CMake configured bundle version from latest reachable git tag (`1.3.2`), despite three commits after that tag.

## Progress

- [x] Embed YouTube helper, requirements/setup resources and demo audio. The installed app extracts helper files and runtime under `QStandardPaths::AppDataLocation`; demo audio falls back to its embedded resource.
- [x] Add macOS Keychain storage for Jellyfin and Subsonic; preserve Linux `secret-tool` behavior.
- [x] Move production Cider token storage to Keychain. Migrate the old private JSON file and remove it only after Keychain succeeds; remove a stale legacy file when a Keychain token already exists.
- [x] Add `SPUN_RELEASE_VERSION`; development bundle versions append commit distance, and the short version stays numeric.
- [x] Update README and add Keychain migration/security regression tests.
- [x] Reconfigure Release build and compile the new Keychain backend/tests plus `.app` resources. Final app build completed with exit code 0; a subsequent `cmake --build build --target spun --parallel 8` reported `ninja: no work to do` and exit code 0.
- [x] Run Keychain/provider CTest cases outside the sandbox: `spun-macos-keychain`, `spun-cider-keychain`, `spun-jellyfin-protocol`, and `spun-subsonic-protocol` all passed.
- [x] Verify the app bundle signature with `codesign --verify --deep --strict --verbose=2 build/Spun.app`; it is valid on disk and satisfies its designated requirement.
- [x] Inspect `build/Spun.app/Contents/Info.plist`: `CFBundleShortVersionString=1.3.2`, `CFBundleVersion=1.3.2.3`. Generated qrc for target `spun` maps `:/spun/helper/youtube.py`, `:/spun/helper/requirements.txt`, `:/spun/scripts/setup-youtube.sh`, and `:/spun/assets/First-Light.flac`; both qrc translation units were built and linked into the app.
- [x] Confirm explicit release-version override using a separate configure in `/private/tmp/spun-version-check` with `-DSPUN_RELEASE_VERSION=1.3.3`; both short and bundle versions configure to `1.3.3`.
- [x] Re-run `python3 tests/test_youtube.py` (5 passed) and CTest subset `spun-3d-geometry`, `spun-folder-import`, `spun-window-mask`, `spun-appearance` (4/4 passed).

## Verification log

- Historical pre-implementation audit: 3D geometry, folder import, window mask, appearance, and YouTube helper tests passed; `spun-remote-library` timed out at 120 s with audio-position assertions failing; YouTube diagnostics had 10/106 failures in audio playback/clock checks in offscreen mode. Those audio/offscreen issues were not introduced or resolved by this Stage 1 implementation.
- Historical pre-implementation macOS provider tests failed in `keyringSaveRestoreAndForget` because `secret-tool` is unavailable on macOS. After adding native Keychain support, current Jellyfin/Subsonic provider tests pass using Keychain.
- Full app build was incomplete during the initial audit, but is now complete and the final app passes codesign verification.
- Shell syntax checks passed for `scripts/build-macos.sh`, `scripts/sign-macos-bundle.sh`, and `scripts/setup-youtube.sh`.
- Native Keychain tests require macOS Keychain access; they initially failed inside the sandbox, then passed outside it. Provider tests also need loopback access and passed outside the sandbox.
- Latest `git diff --check` passes. No commit or push has been made.

## Continue from here

The Stage 1 implementation and listed verifications are complete. Before taking on any Stage 2 work, review `git diff` and the audit attachment. Useful continuation commands:

```sh
git status --short --branch
git diff -- CMakeLists.txt src README.md resources/Info.plist.in .gitignore
ctest --test-dir build --output-on-failure -R 'spun-macos-keychain|spun-cider-keychain|spun-jellyfin-protocol|spun-subsonic-protocol'
```

The Keychain/provider tests need to run outside the sandbox on macOS (they access native Keychain and loopback HTTP). Continue only on the current checkout branch `feature/macos-port`; do not switch branches, commit, or push.
