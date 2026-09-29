#!/usr/bin/env bash
# Finalize Spun.app after macdeployqt: copy QML plugins, rewrite rpaths and
# ad-hoc sign the bundle so it runs standalone on macOS 14+.
#
# macdeployqt leaves every Qt framework with an @loader_path/../../../ rpath
# that resolves to /opt/homebrew/lib on developer machines. macOS then loads
# both the bundled QtCore and the Homebrew one and crashes on launch with
# "Class X is implemented in both ..." duplicate-class errors. Stripping
# those rpaths and adding @executable_path/../Frameworks in their place makes
# dyld resolve every dependency to the bundle.
#
# Codesigning the inner frameworks with the same identifier as the bundle is
# required by macOS 14 Gatekeeper — otherwise LaunchServices rejects the
# app with "mapping process and mapped file have different Team IDs".
set -euo pipefail

bundle="${1:?usage: $0 Spun.app id entitlements qml-root}"
id="${2:?missing bundle identifier}"
entitlements="${3:-}"
qml_root="${4:-}"

install_name_tool=/usr/bin/install_name_tool
codesign=/usr/bin/codesign

# Restore execute permission on every framework and plugin binary. macdeployqt
# copies them without the +x bit and Qt later refuses to dlopen them, which
# surfaces as "plugin not found" at runtime.
find "$bundle/Contents/Frameworks" -type f -name 'Qt*' -exec chmod +x {} \; 2>/dev/null || true
find "$bundle/Contents/PlugIns" -type f \( -name '*.dylib' -o -name 'libq*' \) -exec chmod +x {} \; 2>/dev/null || true
find "$bundle/Contents/Resources" -type f -name '*.dylib' -exec chmod +x {} \; 2>/dev/null || true

# 1. Copy the QML runtime plugins. macdeployqt's -qmldir scanner crashes on
#    Qt 6.11 with Spun's qml/ tree, so we copy the directory by hand. The
#    whole QtQuick tree is included because it is small and Styles/ subdirs
#    live next to Controls/. Without qtquickcontrols2plugin the QML engine
#    aborts on the second line of Main.qml with "plugin not found".
#
#    Homebrew ships qmldir / plugins.qmltypes / libqtquickcontrols2plugin.dylib
#    as symlinks into the qtdeclarative Cellar; we must dereference them with
#    -L or `rsync --copy-links`, otherwise the bundle ends up with broken
#    qmldir pointers that the QML engine can't read and rejects with
#    "plugin not found".
#
#    The Qt 6 QML engine loads C++ modules from two locations:
#      - <app>/Contents/Resources/qml/<Module>/  (used for qmldir-based modules)
#      - <app>/Contents/PlugIns/quick/          (used for the bundled plugins)
#    We populate both.
if [[ -n "$qml_root" && -d "$qml_root" ]]; then
    qml_dest="$bundle/Contents/Resources/qml"
    rm -rf "$qml_dest"
    mkdir -p "$qml_dest"
    if command -v rsync >/dev/null 2>&1; then
        rsync -aL --exclude='__pycache__' --exclude='.cache' \
            "$qml_root"/ "$qml_dest"/
    else
        cp -RL "$qml_root"/. "$qml_dest"/
    fi
    # Quick 3D helper plugin lives in <prefix>/plugins/quick; place it under
    # PlugIns/quick/ so the QML engine finds it through the standard qmlimport
    # path.
    quick_plugin_src="$(dirname "$qml_root")/../plugins/quick"
    if [[ -d "$quick_plugin_src" ]]; then
        mkdir -p "$bundle/Contents/PlugIns/quick"
        if command -v rsync >/dev/null 2>&1; then
            rsync -aL "$quick_plugin_src"/ "$bundle/Contents/PlugIns/quick/"
        else
            cp -RL "$quick_plugin_src"/. "$bundle/Contents/PlugIns/quick/"
        fi
    fi
    # The C++ QML plugins under <qml_root>/QtQuick/Controls (and other dirs)
    # also need to live under PlugIns/quick so the QML engine can dlopen
    # them. The qmldir in Resources/qml references the plugin name only; the
    # actual .dylib lookup goes through PlugIns.
    mkdir -p "$bundle/Contents/PlugIns/quick"
    while IFS= read -r plugin; do
        cp -RL "$plugin" "$bundle/Contents/PlugIns/quick/" || true
    done < <(find "$qml_root" -name '*plugin*.dylib' 2>/dev/null)

    # Some QML plugins link to private frameworks (QtQuickControls2Impl,
    # QtQuickDialogs2Impl, QtLabsAnimation) that macdeployqt would normally
    # copy via -qmldir. We dropped -qmldir because the Qt 6.11
    # qmlimportscanner crashes on Spun's qml/ tree, so we look them up
    # ourselves next to the main Qt frameworks and copy what is missing.
    # QtPdf is intentionally NOT bundled: it embeds private Apple APIs and
    # triggers codesign "bundle format is ambiguous" errors on macOS 14.
    if command -v brew >/dev/null 2>&1; then
        qtdecl_prefix="$(brew --prefix qtdeclarative 2>/dev/null || true)"
    fi
    for entry in \
        "QtQuickControls2Impl:${qtdecl_prefix:-}" \
        "QtQuickDialogs2Impl:${qtdecl_prefix:-}" \
        "QtLabsAnimation:${qtdecl_prefix:-}"; do
        fw="${entry%%:*}"
        prefix="${entry##*:}"
        [[ -z "$prefix" || -z "$fw" ]] && continue
        if [[ -d "$bundle/Contents/Frameworks/$fw.framework" ]]; then
            continue
        fi
        if [[ -d "$prefix/lib/$fw.framework" ]]; then
            if command -v rsync >/dev/null 2>&1; then
                rsync -a "$prefix/lib/$fw.framework" "$bundle/Contents/Frameworks/"
            else
                cp -R "$prefix/lib/$fw.framework" "$bundle/Contents/Frameworks/"
            fi
        fi
    done
    # Pull in any QtQuickControls2* style framework and QtQuickDialogs2* that's
    # referenced by a QML plugin but missing from the bundle. We don't know
    # which style Spun will pick at runtime, so a wildcard is simpler than a
    # hand-rolled list.
    if [[ -n "$qtdecl_prefix" && -d "$qtdecl_prefix/lib" ]]; then
        for fw_dir in "$qtdecl_prefix/lib"/QtQuickControls2*.framework \
                      "$qtdecl_prefix/lib"/QtQuickDialogs2*.framework \
                      "$qtdecl_prefix/lib"/QtQuickTemplates2.framework; do
            [[ -d "$fw_dir" ]] || continue
            fw_name="$(basename "$fw_dir")"
            if [[ ! -d "$bundle/Contents/Frameworks/$fw_name" ]]; then
                if command -v rsync >/dev/null 2>&1; then
                    rsync -a "$fw_dir" "$bundle/Contents/Frameworks/"
                else
                    cp -R "$fw_dir" "$bundle/Contents/Frameworks/"
                fi
            fi
        done
    fi
fi

# 2. Strip absolute Homebrew rpath from the main executable.
if otool -l "$bundle/Contents/MacOS/Spun" | grep -q '/opt/homebrew'; then
    "$install_name_tool" -delete_rpath /opt/homebrew/lib "$bundle/Contents/MacOS/Spun" || true
fi

# 3. Rewrite every framework and plugin rpath, and rewrite any absolute
#    LC_LOAD_DYLIB load commands that still point into /opt/homebrew.
process_bin() {
    local bin="$1"
    if otool -l "$bin" 2>/dev/null | grep -q '@loader_path/../../../'; then
        "$install_name_tool" -delete_rpath '@loader_path/../../../' "$bin" 2>/dev/null || true
    fi
    if otool -L "$bin" 2>/dev/null | grep -q '@rpath/'; then
        "$install_name_tool" -add_rpath '@executable_path/../Frameworks' "$bin" 2>/dev/null || true
    fi
    while read -r rp; do
        [[ -z "$rp" ]] && continue
        "$install_name_tool" -delete_rpath "$rp" "$bin" 2>/dev/null || true
    done < <(otool -l "$bin" 2>/dev/null | awk '/LC_RPATH/{getline; getline; print $2}' | grep '^/opt/' || true)
    # Rewrite absolute /opt/homebrew LC_LOAD_DYLIB references to the bundle.
    # The mapping is "QtFoo.framework" -> "QtFoo" framework binary inside
    # Contents/Frameworks, so we keep just the framework name and rebase the
    # path to @executable_path/../Frameworks/<framework>. The matching
    # @rpath/... entry is what dyld will actually resolve against, so the
    # rewrite is mostly cosmetic — but macOS still refuses to load a binary
    # whose load command names a missing file, hence the rewrite.
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        # dep looks like /opt/homebrew/opt/qtbase/lib/Foo.framework/Versions/A/Foo
        local fw_name
        fw_name="$(basename "$(dirname "$(dirname "$(dirname "$dep")")")")"
        if [[ "$fw_name" == *.framework ]]; then
            "$install_name_tool" -change "$dep" \
                "@executable_path/../Frameworks/${fw_name}/Versions/A/${fw_name%.framework}" \
                "$bin" 2>/dev/null || true
        fi
    done < <(otool -L "$bin" 2>/dev/null | awk '/^\t\/opt\/homebrew/{print $1}' || true)
}

while read -r bin; do process_bin "$bin"; done < <(find "$bundle/Contents/Frameworks" -type f -perm +111)
while read -r bin; do process_bin "$bin"; done < <(find "$bundle/Contents/PlugIns" -type f -perm +111)
# QML plugins copied into Resources/qml/ carry absolute /opt/homebrew
# LC_LOAD_DYLIB paths because Homebrew links them that way; they would also
# refuse to load if dyld reached back to /opt/homebrew instead of the bundle.
while read -r bin; do process_bin "$bin"; done < <(find "$bundle/Contents/Resources" -type f -perm +111)

# Re-scan for any framework that the QML-plugin copy step just dropped in:
# they also carry the Homebrew @loader_path/../../../ rpath and need the same
# rewrite before macOS tries to dlopen them.
while read -r bin; do process_bin "$bin"; done < <(find "$bundle/Contents/Frameworks" -type f -perm +111)

# 4. Re-sign every framework and plugin with the same identifier so Gatekeeper
#    treats them as part of one team. The main MacOS/Spun binary is left alone
#    — its linker-adhoc stamp is what `--deep` reads when sealing the bundle,
#    and re-signing it directly would clobber the LC_LINKEDIT pages.
while read -r bin; do
    case "$bin" in
        */MacOS/*) ;;  # skip the main executable
        *)
            "$codesign" --force --sign - --identifier "$id" "$bin" >/dev/null 2>&1 || true
            ;;
    esac
done < <(find "$bundle/Contents" -type f \( -name '*.dylib' -o -perm +111 \))

# 5. Ad-hoc sign the bundle itself, attaching the entitlements so macOS lets
#    it load the unsigned third-party libraries we copied in.
entitlements_args=()
if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    entitlements_args=(--entitlements "$entitlements")
fi
"$codesign" --force --deep --sign - --identifier "$id" \
    "${entitlements_args[@]}" "$bundle" >/dev/null
