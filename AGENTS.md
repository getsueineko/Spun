# Repository Guide

## Project

Spun is a Qt 6 desktop music player for Linux and macOS. The application uses
C++20 for playback, library, service integrations and platform code, with QML
for its interface and optional 3D player models. CMake is the build system.
Qt 6.8 or newer and TagLib 2.0 or newer are required; Qt Quick 3D is optional.

## Working in this repository

- Follow the user's requested branch and scope. Do not switch branches or
  create another branch unless asked.
- Read the relevant implementation and its callers before changing shared
  behavior. Keep the patch focused and follow nearby patterns.
- Preserve Linux builds when changing macOS code. Apple-specific Objective-C++
  implementations use `.mm` files; non-Apple builds use the corresponding
  `*_stub.cpp` implementations selected in `CMakeLists.txt`.
- Keep UI behavior, keyboard access, accessibility, and existing QML
  `objectName` values used by diagnostics intact unless the task requires a
  change.
- Do not commit, push, retag, or publish unless the user requests it.
- Do not add credentials, user data, generated build output, or temporary
  handoff documents to the repository.

## Repository layout

- `src/` — C++ application, playback and service code, platform adapters, and
  diagnostic test implementations.
- `qml/` — application interface and the CD, vinyl, cassette, recorder, and
  mixer player views.
- `resources/` — macOS bundle metadata, icon, and signing entitlements.
- `scripts/` — Linux/macOS build and packaging helpers, runtime setup, and
  development utilities.
- `helper/` — optional Python helper used for YouTube integration.
- `tests/` — helper tests and focused regression-test documentation.
- `assets/` and `licenses/` — shipped artwork, demo audio, icons, and notices.
- `.github/workflows/` — GitHub Actions release automation.

## Build and test

Use the commands and platform dependencies documented in `README.md`.

Linux build and full registered test suite:

```sh
./scripts/build.sh -DBUILD_TESTING=ON
ctest --test-dir build --output-on-failure
```

macOS Apple Silicon build and test suite:

```sh
./scripts/build-macos.sh -DBUILD_TESTING=ON
ctest --test-dir build --output-on-failure -E 'spun-desktop-media'
```

The desktop-media test depends on D-Bus and is not run on macOS. Some playback
checks also need an available audio output device. For focused regression
coverage, use `ctest --test-dir build -L regression --output-on-failure -j1`;
see `tests/REGRESSION.md` for the covered scenarios. The YouTube helper tests
can be run with `python3 tests/test_youtube.py`.

Quick 3D coverage is available through `./scripts/test-3d.sh`; it requires the
rendering dependencies described in `README.md`. Disable optional 3D at CMake
configure time with `-DSPUN_ENABLE_3D=OFF` when Qt Quick 3D is unavailable.

## macOS packaging and releases

Use `scripts/build-macos.sh` for macOS builds and `scripts/sign-macos-bundle.sh`
and `scripts/package-macos-dmg.sh` for the app and disk-image pipeline. Release
build requirements, signing behavior, Gatekeeper limitations, and optional
notarization settings are documented in `README.md` and `CMakeLists.txt`.

The macOS release workflow is `.github/workflows/macos-release.yml`. Keep its
release tag validation and permissions aligned with the build and upload steps.
Do not make Developer ID signing, Hardened Runtime, or notarization mandatory
without an explicit product decision.

## Documentation

Keep `README.md` as the user-facing source of truth for installation, supported
platforms, known limitations, and release packaging. Keep `AGENTS.md` focused
on durable contributor instructions; do not recreate temporary stage handoffs
or session-resume notes.
