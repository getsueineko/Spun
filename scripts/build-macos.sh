#!/usr/bin/env bash
set -euo pipefail

spun_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required to locate Qt6 and TagLib." >&2
    exit 1
fi

qt_prefix="$(brew --prefix qt 2>/dev/null || true)"
if [[ -z "$qt_prefix" || ! -d "$qt_prefix" ]]; then
    echo "Qt6 not found via Homebrew. Install with: brew install qt" >&2
    exit 1
fi

taglib_prefix="$(brew --prefix taglib 2>/dev/null || true)"
if [[ -z "$taglib_prefix" || ! -d "$taglib_prefix" ]]; then
    echo "TagLib not found via Homebrew. Install with: brew install taglib" >&2
    exit 1
fi

export CMAKE_PREFIX_PATH="${qt_prefix}:${taglib_prefix}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export PKG_CONFIG_PATH="${taglib_prefix}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="${qt_prefix}/bin:$PATH"

build_type="${BUILD_TYPE:-Release}"
extra_args=()
has_testing=0
if [[ $# -gt 0 ]]; then
    extra_args=("$@")
    for arg in "${extra_args[@]}"; do
        if [[ "$arg" == *BUILD_TESTING=* ]]; then has_testing=1; fi
    done
fi
if [[ $has_testing -eq 0 ]]; then
    extra_args=("-DBUILD_TESTING=OFF" "${extra_args[@]+"${extra_args[@]}"}")
fi

cmake -S "$spun_root" -B "$spun_root/build" -G Ninja \
    -DCMAKE_BUILD_TYPE="$build_type" \
    -DSPUN_ENABLE_3D=ON \
    "${extra_args[@]}"

cmake --build "$spun_root/build" --parallel "$(sysctl -n hw.ncpu)"

echo
echo "Build complete. Binary at: $spun_root/build/spun.app/Contents/MacOS/spun"
echo "Run with: open $spun_root/build/spun.app"
