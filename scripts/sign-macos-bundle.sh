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

# 1. Copy the QML scaffolding. macdeployqt's -qmldir scanner crashes on
#    Qt 6.11 with Spun's qml/ tree, so we work around it. The strategy:
#
#    a. Copy only the qmldir files (and plugins.qmltypes) from Homebrew's
#       share/qt/qml — they tell the QML engine which C++ plugin dylib
#       backs each module and which types it exports. We do NOT copy the
#       .qml files themselves because Qt 6.11 builds the modules into
#       its framework binaries via qt_add_qml_module and the in-binary
#       resources (qrc:/qt-project.org/imports/...) carry the actual
#       definitions of types like FileDialogImpl and TextEditingContextMenu.
#       Mixing disk and binary copies corrupts the module graph and the
#       QML engine aborts on the second line of Main.qml.
#
#    b. Drop the `prefer :/qt-project.org/imports/...` line from the qmldir
#       we copied — otherwise Qt looks at its in-binary qmldir (which is
#       missing private types like TextEditingContextMenu) instead of the
#       actual .qml files baked into QtQuickControls2.framework.
#
#    c. Copy the C++ plugin dylibs into PlugIns/quick/ so the QML engine
#       can dlopen them through the standard qmlimport path.
#
#    d. Copy the private frameworks the plugins link against
#       (QtQuickControls2Impl, QtQuickDialogs2Impl, the style frameworks
#       and QtQuickTemplates2). macdeployqt would normally do this via
#       -qmldir; we dropped that because of the scanner crash.
if [[ -n "$qml_root" && -d "$qml_root" ]]; then
    qml_dest="$bundle/Contents/Resources/qml"
    rm -rf "$qml_dest"
    mkdir -p "$qml_dest"

    # Copy qmldir / plugins.qmltypes for every Qt module so the QML engine
    # knows which plugin dylib backs each module. Then copy the .qml files
    # for the modules Spun actually imports: QtQuick, QtQuick.2, QtQml,
    # QtQuick.Controls (Basic + Fusion), QtQuick.Dialogs, QtQuick.Layouts,
    # QtQuick.Templates, QtQuick.Window, QtQml.Models, Qt.labs.*, QtQuick.3D.
    #
    # The Qt 6 framework binaries already ship their own private types
    # (FileDialogImpl, TextEditingContextMenu) compiled in, so the disk
    # copies only need the public surfaces. We pick the listed modules
    # explicitly so we don't drag in 100+ MB of unused style qml files.
    if command -v rsync >/dev/null 2>&1; then
        rsync -aL --include='qmldir' --include='plugins.qmltypes' \
            --include='*/' --exclude='*' \
            "$qml_root"/ "$qml_dest"/ 2>/dev/null || true
    fi
    if [[ ! -f "$qml_dest/QtQuick/qmldir" ]]; then
        while IFS= read -r src; do
            rel="${src#$qml_root/}"
            dest="$qml_dest/$rel"
            mkdir -p "$(dirname "$dest")"
            cp -RL "$src" "$dest" 2>/dev/null || true
        done < <(find "$qml_root" -type f \( -name 'qmldir' -o -name 'plugins.qmltypes' \) 2>/dev/null)
    fi

    # Copy the .qml files Spun needs. Limit the list to keep the bundle
    # small and avoid modules that ship private types compiled in
    # (e.g. QtQuick.VirtualKeyboard, QtWebEngine).
    for sub in QtQuick QtQuick.2 QtQml QtQml/Models \
               QtQuick/Controls QtQuick/Controls/Basic \
               QtQuick/Controls/Fusion \
               QtQuick/Dialogs QtQuick/Dialogs/quickimpl \
               QtQuick/Layouts QtQuick/Templates QtQuick/Window \
               Qt/labs Qt/labs/platform Qt/labs/qmlmodels \
               QtQuick/3D; do
        if [[ -d "$qml_root/$sub" ]]; then
            mkdir -p "$qml_dest/$(dirname "$sub")"
            if command -v rsync >/dev/null 2>&1; then
                rsync -aL "$qml_root/$sub"/ "$qml_dest/$sub/" 2>/dev/null || true
            else
                cp -RL "$qml_root/$sub"/. "$qml_dest/$sub"/ 2>/dev/null || true
            fi
        fi
    done

    # Drop the `prefer :/qt-project.org/imports/...` line from every qmldir
    # we copied. With it, the QML engine resolves modules to the copies
    # baked into the Qt frameworks and never reads the in-binary qmldir —
    # and the embedded Qt 6.11 copies do not include some private types
    # (e.g. QtQuick.Controls.Basic.impl.TextEditingContextMenu) that Spun
    # relies on. Removing the prefer line forces a fallback lookup.
    while IFS= read -r qmldir; do
        sed -i '' '/^prefer[ \t]*:[^ \t]/d' "$qmldir" 2>/dev/null || true
    done < <(find "$qml_dest" -name 'qmldir' -type f 2>/dev/null)

    # Quick 3D helper plugin lives in <prefix>/plugins/quick; place it under
    # PlugIns/quick/ so the QML engine finds it through the standard
    # qmlimport path.
    quick_plugin_src="$(dirname "$qml_root")/../plugins/quick"
    if [[ -d "$quick_plugin_src" ]]; then
        mkdir -p "$bundle/Contents/PlugIns/quick"
        if command -v rsync >/dev/null 2>&1; then
            rsync -aL "$quick_plugin_src"/ "$bundle/Contents/PlugIns/quick/"
        else
            cp -RL "$quick_plugin_src"/. "$bundle/Contents/PlugIns/quick/"
        fi
    fi

    # C++ QML plugin dylibs into PlugIns/quick so the QML engine can dlopen
    # them through the standard qmlimport path. We also copy each plugin
    # into its module's qml directory (Resources/qml/<Module>/) because
    # qmldir's "plugin <name>" directive resolves the dylib relative to
    # the qmldir's own folder, not via the standard QmlImportPath.
    mkdir -p "$bundle/Contents/PlugIns/quick"
    while IFS= read -r plugin; do
        cp -RL "$plugin" "$bundle/Contents/PlugIns/quick/" || true
        # Mirror to the qml folder so qmldir's "plugin" directive resolves.
        rel="${plugin#$qml_root/}"
        mirror="$qml_dest/$rel"
        if [[ -d "$(dirname "$mirror")" ]]; then
            cp -RL "$plugin" "$mirror" || true
        fi
    done < <(find "$qml_root" -name '*plugin*.dylib' 2>/dev/null)

    # Pull in any private framework the QML plugins link against
    # (QtQuickControls2Impl, QtQuickDialogs2Impl, QtLabsAnimation) plus
    # the style frameworks and QtQuickTemplates2.
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
