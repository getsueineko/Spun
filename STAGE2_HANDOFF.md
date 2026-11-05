# Stage 2 macOS packaging handoff

## Scope and guardrails

- Build a GitHub Releases-ready standalone `.app` and compressed `.dmg` on macOS.
- Release configuration must fail when packaging tools are missing.
- Default signing is ad-hoc and must work without an Apple Developer account.
- Developer ID, Hardened Runtime and notarization remain opt-in.
- Gatekeeper behavior must be documented accurately for a non-notarized download.
- Continue only on the already-active `feature/macos-port` branch. Do not switch branches.
- Do not commit or push unless explicitly requested for this Stage 2 work.

## Stage 1 base

- Stage 1 commit: `a616558` (`macOS: bundle release assets and use Keychain`).
- Stage 1 implementation, tests and prior release app verification are documented in `STAGE1_HANDOFF.md`.
- The current checkout is clean at Stage 2 start.

## Stage 2 implementation status

- [x] Require `macdeployqt`, `codesign`, `install_name_tool`, `otool`, `hdiutil` and `ditto` when a Release configuration is present.
- [x] Keep ad-hoc signing as the default and create a `.dmg` with an Applications shortcut.
- [x] Add optional Developer ID identity, Hardened Runtime and notarytool submission/stapling without making them Release prerequisites.
- [x] Document Gatekeeper's one-time manual approval for ad-hoc, non-notarized downloads.
- [x] Build a clean Release app and DMG, verify the signature and inspect image contents.
- [x] Record command results and remaining work.

## Verification log

- `bash -n scripts/build-macos.sh scripts/sign-macos-bundle.sh scripts/package-macos-dmg.sh` passed.
- Release CMake configure found `macdeployqt`, `codesign`, `install_name_tool`, `otool`, `hdiutil` and `ditto`. Default cache settings are ad-hoc identity `-`, Hardened Runtime `OFF`, notarization `OFF`.
- Clean Release configure with `SPUN_RELEASE_VERSION=1.3.3`, `BUILD_TESTING=OFF`, and 3D enabled succeeded in `/private/tmp/spun-stage2-clean`.
- `cmake --build /private/tmp/spun-stage2-clean --target spun-dmg --parallel 8` completed with exit code 0 and generated `/private/tmp/spun-stage2-clean/dist/Spun-1.3.3-macos-arm64.dmg` (102 MB).
- Clean app and DMG use `CFBundleShortVersionString=1.3.3` and `CFBundleVersion=1.3.3`. `codesign --verify --deep --strict` passed for the `.app` in the mounted image; signature metadata reports `Signature=adhoc`, `TeamIdentifier=not set`, and `flags=0x2(adhoc)`.
- `hdiutil verify` reported a valid checksum. Read-only mounting confirmed the image contains `Spun.app` and an `Applications -> /Applications` shortcut. The DMG format is UDZO.
- A build in the workspace also generated `build/Spun.app` and `build/dist/Spun-1.3.2.4-macos-arm64.dmg`; its `Info.plist` versions are short `1.3.2`, bundle `1.3.2.4`.
- On this macOS 27 host, `hdiutil` still creates, verifies, mounts and ejects the images, but prints deprecation warnings recommending `diskutil image`. The command remains available and the current script retains it for macOS 14+ compatibility.
- The clean deploy log included `macdeployqt` “Cannot resolve @rpath” messages for QtPdf / QtVirtualKeyboard. The final signer copied the referenced frameworks, its unresolved install-name scan passed, and `codesign --verify --deep --strict` passed. Preserve this note for Stage 3 startup validation.
- Ad-hoc Gatekeeper approval is documented, but the interactive first-launch flow has not been exercised on a separate clean macOS account/device. Stage 3 should verify that user path.
- `git diff --check` passed. Stage 2 changes remain uncommitted and unpushed.

## Intended release outputs

- App bundle: `build/Spun.app`
- Disk image: `build/dist/Spun-<CFBundleVersion>-macos-arm64.dmg` (e.g. development builds include the commit distance; set `SPUN_RELEASE_VERSION` for a three-part release version)
- Gatekeeper approval: after attempting launch, use **System Settings → Privacy & Security → Open Anyway**. The ad-hoc signature does not identify a developer or bypass Gatekeeper.

## Continue here

Stage 2 packaging implementation is complete. Stage 3 should run the app installed from the DMG on a clean macOS user/system, exercise the Gatekeeper **Open Anyway** flow, and validate runtime imports/playback. Package generation is part of the Release build on the single-config macOS/Ninja path; `spun-dmg` is an explicit target for other generators. Keep Developer ID and notarization disabled unless requested. Continue on `feature/macos-port`; do not switch branches.
