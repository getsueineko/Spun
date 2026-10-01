#!/usr/bin/env bash
# Build Spun on macOS. By default it expects Qt 6 from Homebrew at
# $(brew --prefix qt); set SPUN_QT_PREFIX to point at any other Qt 6
# installation (e.g. the official Qt installer under ~/Qt/6.x.y/macos).
set -euo pipefail

spun_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve the Qt prefix. SPUN_QT_PREFIX wins so this script works
# identically on Homebrew, the official Qt online installer, and any
# hand-managed SDK tree. Falling back to brew is opt-in, not required.
qt_prefix="${SPUN_QT_PREFIX:-}"
if [[ -z "$qt_prefix" ]]; then
    if command -v brew >/dev/null 2>&1; then
        qt_prefix="$(brew --prefix qt 2>/dev/null || true)"
    fi
fi
if [[ -z "$qt_prefix" || ! -d "$qt_prefix" ]]; then
    echo "Qt6 not found. Install Qt 6.8+ via Homebrew ('brew install qt') or" >&2
    echo "the official Qt online installer, then re-run with" >&2
    echo "    SPUN_QT_PREFIX=/path/to/Qt/6.x.y/macos $0" >&2
    exit 1
fi

# Sanity-check the Qt version against what Spun was built against. The
# build is known to work on 6.11; other majors/m minors may need a fresh
# qmlimportscanner run because Qt 6.11 ships a partial-rebuild of the QML
# import graph that earlier versions cannot replay correctly.
if command -v "${qt_prefix}/bin/qmake" >/dev/null 2>&1; then
    qt_version="$("${qt_prefix}/bin/qmake" -query QT_VERSION 2>/dev/null || true)"
    if [[ -n "$qt_version" ]]; then
        qt_major="${qt_version%%.*}"
        qt_minor="$(echo "$qt_version" | cut -d. -f2)"
        if [[ "$qt_major" != "6" || "$qt_minor" != "11" ]]; then
            echo "WARNING: Spun is built and tested against Qt 6.11; detected ${qt_version}." >&2
            echo "         Build may succeed but runtime / qmlimportscanner behaviour" >&2
            echo "         is untested on other minors." >&2
        fi
    fi
fi

# TagLib is required by the player metadata reader. We allow SPUN_TAGLIB_PREFIX
# to override the brew lookup so cross-compiling against a vendored TagLib is
# possible without modifying the script.
taglib_prefix="${SPUN_TAGLIB_PREFIX:-}"
if [[ -z "$taglib_prefix" ]]; then
    if command -v brew >/dev/null 2>&1; then
        taglib_prefix="$(brew --prefix taglib 2>/dev/null || true)"
    fi
fi
if [[ -z "$taglib_prefix" || ! -d "$taglib_prefix" ]]; then
    echo "TagLib not found. Install with 'brew install taglib' or set" >&2
    echo "SPUN_TAGLIB_PREFIX to a directory containing lib/pkgconfig/taglib.pc." >&2
    exit 1
fi

export CMAKE_PREFIX_PATH="${qt_prefix}:${taglib_prefix}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export PKG_CONFIG_PATH="${taglib_prefix}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="${qt_prefix}/bin:$PATH"

build_type="${BUILD_TYPE:-Release}"
extra_args=("$@")
has_testing=0
for arg in "${extra_args[@]}"; do
    if [[ "$arg" == *BUILD_TESTING=* ]]; then has_testing=1; fi
done
if [[ $has_testing -eq 0 ]]; then
    extra_args=("-DBUILD_TESTING=OFF" "${extra_args[@]+"${extra_args[@]}"}")
fi

cmake -S "$spun_root" -B "$spun_root/build" -G Ninja \
    -DCMAKE_BUILD_TYPE="$build_type" \
    -DSPUN_ENABLE_3D=ON \
    "${extra_args[@]}"

cmake --build "$spun_root/build" --parallel "$(sysctl -n hw.ncpu)"

echo
echo "Build complete. Binary at: $spun_root/build/Spun.app/Contents/MacOS/Spun"
echo "Run with: open $spun_root/build/Spun.app"
