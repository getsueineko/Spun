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
# surfaces as "plugin not found" at runtime. chmod succeeds on the regular
# files we care about; if it ever fails, abort — a missing +x bit on a
# framework binary means the app won't launch, so we want to know now.
find "$bundle/Contents/Frameworks" -type f -name 'Qt*' -exec chmod +x {} +
find "$bundle/Contents/PlugIns" -type f \( -name '*.dylib' -o -name 'libq*' \) -exec chmod +x {} +
find "$bundle/Contents/Resources" -type f -name '*.dylib' -exec chmod +x {} +

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
    #
    # Tolerated: rsync/cp of a single missing module would otherwise abort
    # the whole script with `set -e`. Skip-on-missing is acceptable because
    # macdeployqt has already verified that the rest of the bundle is fine.
    if command -v rsync >/dev/null 2>&1; then
        rsync -aL --include='qmldir' --include='plugins.qmltypes' \
            --include='*/' --exclude='*' \
            "$qml_root"/ "$qml_dest"/ || true
    fi
    if [[ ! -f "$qml_dest/QtQuick/qmldir" ]]; then
        while IFS= read -r src; do
            rel="${src#$qml_root/}"
            dest="$qml_dest/$rel"
            mkdir -p "$(dirname "$dest")"
            cp -RL "$src" "$dest" || true
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
                rsync -aL "$qml_root/$sub"/ "$qml_dest/$sub"/ || true
            else
                cp -RL "$qml_root/$sub"/. "$qml_dest/$sub"/ || true
            fi
        fi
    done

    # Drop the `prefer :/qt-project.org/imports/...` line from every qmldir
    # we copied. With it, the QML engine resolves modules to the copies
    # baked into the Qt frameworks and never reads the in-binary qmldir —
    # and the embedded Qt 6.11 copies do not include some private types
    # (e.g. QtQuick.Controls.Basic.impl.TextEditingContextMenu) that Spun
    # relies on. Removing the prefer line forces a fallback lookup.
    #
    # Tolerated: BSD sed's -i '' exits non-zero when the input has no
    # matching line. The next iteration's qmldir is unaffected.
    while IFS= read -r qmldir; do
        sed -i '' '/^prefer[ \t]*:[^ \t]/d' "$qmldir" || true
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
    qtdecl_prefix=""
    if command -v brew >/dev/null 2>&1; then
        qtdecl_prefix="$(brew --prefix qtdeclarative 2>/dev/null || true)"
    fi
    for entry in \
        "QtQuickControls2Impl:${qtdecl_prefix:-}" \
        "QtQuickDialogs2Impl:${qtdecl_prefix:-}" \
        "QtLabsAnimation:${qtdecl_prefix:-}" \
        "QtQuickLayouts:${qtdecl_prefix:-}"; do
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
                      "$qtdecl_prefix/lib"/QtQuickLayouts.framework \
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
    # macdeployqt and our private-framework copy both drop binaries into
    # Frameworks/ without the executable bit, and Qt refuses to dlopen a
    # non-executable framework. Set +x on every framework binary and every
    # *.dylib; skip Headers/, Resources/, *.prl, *.h siblings that codesign
    # needs to overwrite during re-sign.
    find "$bundle/Contents/Frameworks" "$bundle/Contents/PlugIns" \
        -mindepth 4 -maxdepth 5 -path '*/Versions/A/*' -type f ! -name '*.*' \
        -exec chmod +x {} +
    find "$bundle/Contents/Frameworks" "$bundle/Contents/PlugIns" \
        -type f -name '*.dylib' \
        -exec chmod +x {} +
fi

# 2. Strip absolute Homebrew rpath from the main executable. A missing rpath
#    (no /opt/homebrew) leaves the binary as-is; install_name_tool exits
#    non-zero only when the rpath really wasn't there, which we tolerate.
if otool -l "$bundle/Contents/MacOS/Spun" | grep -q '/opt/homebrew'; then
    "$install_name_tool" -delete_rpath /opt/homebrew/lib "$bundle/Contents/MacOS/Spun"
fi

# 3. Rewrite every framework and plugin rpath, and rewrite any absolute
#    LC_LOAD_DYLIB load commands that still point into /opt/homebrew.
process_bin() {
    local bin="$1"
    # Match rpath paths that have the canonical Homebrew pattern. The grep
    # here is loose on purpose: we are stripping every LC_RPATH entry whose
    # text mentions /opt/homebrew (the path column is what `awk` extracts
    # below); install_name_tool exits non-zero if the rpath is missing,
    # so we have to enumerate the real values rather than guess.
    if otool -l "$bin" 2>/dev/null | grep -q 'path /opt/homebrew'; then
        while read -r rp; do
            [[ -z "$rp" ]] && continue
            "$install_name_tool" -delete_rpath "$rp" "$bin"
        done < <(otool -l "$bin" 2>/dev/null | awk '/LC_RPATH/{getline; getline; sub(/^[[:space:]]*path /,""); sub(/[[:space:]].*$/, ""); print}' | grep '^/opt/' || true)
    fi
    if otool -l "$bin" 2>/dev/null | grep -q '@loader_path/'; then
        while read -r rp; do
            [[ -z "$rp" ]] && continue
            "$install_name_tool" -delete_rpath "$rp" "$bin" || true
        done < <(otool -l "$bin" 2>/dev/null | awk '/LC_RPATH/{getline; getline; sub(/^[[:space:]]*path /,""); sub(/[[:space:]].*$/, ""); print}' | grep '@loader_path' || true)
    fi
    if otool -L "$bin" 2>/dev/null | grep -q '@rpath/'; then
        if ! otool -l "$bin" 2>/dev/null | grep -q "path @executable_path/../Frameworks"; then
            "$install_name_tool" -add_rpath '@executable_path/../Frameworks' "$bin" || true
        fi
    fi
    # Rewrite absolute /opt/homebrew LC_LOAD_DYLIB references to the bundle.
    # The mapping is "Foo.framework/Versions/A/Foo" or "libbar.dylib" ->
    # @executable_path/../Frameworks/<basename>. Using the absolute
    # @executable_path form (not @rpath) means the rewrite works for plugin
    # dylibs that do not carry the @executable_path/../Frameworks LC_RPATH
    # entry — QML plugins copied into Resources/qml/<Module>/ in particular
    # only have a Homebrew-style @loader_path/../../../../../lib rpath, so
    # @rpath would fail to resolve.
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        local new_name=""
        if [[ "$dep" == *.framework/Versions/A/* ]]; then
            local fw_name
            fw_name="$(basename "$(dirname "$(dirname "$(dirname "$dep")")")")"
            new_name="@executable_path/../Frameworks/${fw_name}/Versions/A/${fw_name%.framework}"
        elif [[ "$dep" == *.dylib ]]; then
            # Strip any path prefix and version suffix. We rely on the file
            # being present in Contents/Frameworks/ with the same basename;
            # macdeployqt copies each .dylib flat there. Suffixes like -1.2.3
            # and versionless plain .dylib are both handled.
            local lib_name
            lib_name="$(basename "$dep")"
            new_name="@executable_path/../Frameworks/${lib_name}"
        fi
        if [[ -n "$new_name" ]]; then
            "$install_name_tool" -change "$dep" "$new_name" "$bin"
        fi
    done < <(otool -L "$bin" 2>/dev/null | awk '/^\t\/opt\/homebrew/{print $1}' || true)
    # Also rewrite LC_ID_DYLIB (the framework's own install name) so it
    # matches what dependents look for via @rpath. Without this the entry
    # stays at /opt/homebrew/... and dyld's record of the framework does
    # not match the path used by other modules when resolving @rpath.
    # Plain *.dylib files get the same treatment so otool -L does not show
    # the absolute /opt/homebrew install name (dyld would also reach back
    # to the brew path on lookup, which is exactly the bug we are fixing).
    local id_name
    id_name="$(otool -D "$bin" 2>/dev/null | sed -n '2p')"
    if [[ "$id_name" == /opt/homebrew/* ]]; then
        local new_id=""
        if [[ "$id_name" == *.framework/Versions/A/* ]]; then
            local id_fw
            id_fw="$(basename "$(dirname "$(dirname "$(dirname "$id_name")")")")"
            new_id="@rpath/${id_fw}/Versions/A/${id_fw%.framework}"
        elif [[ "$id_name" == *.dylib ]]; then
            local id_lib
            id_lib="$(basename "$id_name")"
            new_id="@executable_path/../Frameworks/${id_lib}"
        fi
        if [[ -n "$new_id" ]]; then
            "$install_name_tool" -id "$new_id" "$bin"
        fi
    fi
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

# 4. Sign every binary inside-out, deepest first. macOS Gatekeeper refuses a
#    bundle whose contents disagree about Team ID, so each framework and
#    plugin must carry the same identifier as the bundle itself. We sign in
#    leaf-to-root order: first the helper plugins in Contents/Resources/qml/
#    and Contents/PlugIns/, then the Qt frameworks they link against, and
#    finally the main executable. The entitlements file is applied only to
#    the bundle root (which is what LaunchServices reads); per-binary
#    entitlements on inner dylibs are unnecessary and slow signing down.
#
#    `com.apple.security.cs.disable-library-validation` in
#    resources/spun.entitlements is a no-op without hardened runtime
#    (`--options runtime`), which we deliberately do not enable: the bundle
#    is intended for direct execution on the user's machine, not for
#    distribution outside the Mac App Store, so hardened-runtime would only
#    complicate third-party plugin loading. The entitlement is kept as a
#    forward-compatibility marker so flipping hardened runtime on later
#    does not require a parallel edit.
sign_bin() {
    local bin="$1"
    # Re-signing needs write permission on the file; if a previous run put
    # the framework into a read-only state we have to drop that here.
    [[ -w "$bin" ]] || chmod u+w "$bin"
    "$codesign" --force --sign - --identifier "$id" "$bin"
}
while read -r bin; do
    [[ -f "$bin" ]] || continue
    case "$bin" in
        */MacOS/*) ;;  # sign the main executable last so its hash is stable
        *) sign_bin "$bin" ;;
    esac
done < <(find "$bundle/Contents/Resources/qml" -type f -name '*.dylib' 2>/dev/null)
while read -r bin; do
    [[ -f "$bin" ]] || continue
    case "$bin" in
        */MacOS/*) ;;
        *) sign_bin "$bin" ;;
    esac
done < <(find "$bundle/Contents/PlugIns" -type f \( -name '*.dylib' -o -perm +111 \) 2>/dev/null)
while read -r bin; do
    [[ -f "$bin" ]] || continue
    case "$bin" in
        */MacOS/*) ;;
        *) sign_bin "$bin" ;;
    esac
done < <(find "$bundle/Contents/Frameworks" -type f \( -name '*.dylib' -o -perm +111 \) 2>/dev/null)
sign_bin "$bundle/Contents/MacOS/Spun"

# 5. Ad-hoc sign the bundle itself, attaching the entitlements so macOS lets
#    it load the unsigned third-party libraries we copied in.
entitlements_args=()
if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    entitlements_args=(--entitlements "$entitlements")
fi
"$codesign" --force --sign - --identifier "$id" \
    "${entitlements_args[@]}" "$bundle"

# 6. Verify the bundle. `--strict` fails on any signing inconsistency;
#    --verbose=2 prints the chain of trust for spot checks. A non-zero exit
#    here means macOS will reject the bundle at launch, so propagate it.
"$codesign" --verify --strict --verbose=2 "$bundle"

# 7. Re-scan every binary in the bundle for stray /opt/homebrew references.
#    A surviving LC_LOAD_DYLIB or LC_RPATH to /opt/homebrew would either
#    fail at load time or pull Homebrew's Qt into the process and re-trigger
#    the "Class X is implemented in both" duplicate-class crash. Fail loud
#    so the developer sees the offending binary instead of a confusing
#    runtime symptom.
stale_refs=()
while read -r bin; do
    [[ -f "$bin" ]] || continue
    if otool -l "$bin" 2>/dev/null | grep -q '^.*/opt/homebrew'; then
        stale_refs+=("$bin")
    fi
done < <(find "$bundle/Contents" -type f -perm +111 2>/dev/null)
if (( ${#stale_refs[@]} > 0 )); then
    echo "ERROR: bundle still references /opt/homebrew after signing:" >&2
    for bin in "${stale_refs[@]}"; do
        echo "  $bin" >&2
        otool -L "$bin" | grep '/opt/homebrew' >&2 || true
    done
    exit 1
fi

# 6. Verify that the QML modules Spun actually imports are present in the
#    bundle. macdeployqt crashes on Spun's qml/ tree and we work around it,
#    so without this check a silent failure of the workaround would manifest
#    only at runtime as "module QtQuick.Dialogs is not installed".
for module in QtQuick QtQuick/Controls QtQuick/Dialogs QtQuick/Layouts QtQuick/Window; do
    if [[ ! -f "$bundle/Contents/Resources/qml/$module/qmldir" ]]; then
        echo "ERROR: required QML module $module is missing from the bundle." >&2
        echo "       (expected $bundle/Contents/Resources/qml/$module/qmldir)" >&2
        echo "       This usually means qml_root (\"$qml_root\") did not contain" >&2
        echo "       Qt 6 modules, or the cp/rsync copy failed." >&2
        exit 1
    fi
done
# Quick3D is only required when SPUN_ENABLE_3D was set at build time. We
# detect it by the presence of the QtQuick3D private plugin dylib in the
# bundle; if it's there, the qmldir should be too.
if [[ -f "$bundle/Contents/PlugIns/quick/libqtquick3dquickplugin.dylib" \
   || -f "$bundle/Contents/Resources/qml/QtQuick3D/qmldir" ]]; then
    if [[ ! -f "$bundle/Contents/Resources/qml/QtQuick3D/qmldir" ]]; then
        echo "ERROR: QtQuick3D plugin is present but its qmldir is missing." >&2
        exit 1
    fi
fi

# 7. Resolve every non-system LC_LOAD_DYLIB inside the bundle to an existing
#    file. A dangling @executable_path/... or @rpath/... reference would
#    only surface at runtime as "image not found", and macOS dialogs do not
#    tell the developer which Mach-O owned the broken reference. Walk each
#    binary once, resolve each install name against the bundle root, and
#    fail with the full list if any reference is missing.
unresolved=()
while read -r bin; do
    [[ -f "$bin" ]] || continue
    # @executable_path is defined as the directory of the main executable
    # (Contents/MacOS/), regardless of which Mach-O carries the load
    # command; @loader_path is the directory of the binary that owns the
    # command.
    exec_root="$bundle/Contents/MacOS"
    loader_root="$(dirname "$bin")"
    while read -r dep; do
        case "$dep" in
            /usr/lib/*|/System/Library/*) continue ;;
        esac
        resolved=""
        case "$dep" in
            @executable_path/*)
                tail="${dep#@executable_path/}"
                resolved="$exec_root/$tail"
                ;;
            @loader_path/*)
                tail="${dep#@loader_path/}"
                resolved="$loader_root/$tail"
                ;;
        esac
        # @rpath is resolved via LC_RPATH, which we already vetted in step 5
        # (delete_rpath kept only @executable_path/../Frameworks, so @rpath
        # lookups land in the bundle's Frameworks/). We do not re-check them
        # here because the resolution depends on the rpath table, not the
        # install name alone.
        if [[ -n "$resolved" && ! -e "$resolved" ]]; then
            unresolved+=("$bin -> $dep")
        fi
    done < <(otool -L "$bin" 2>/dev/null | awk '/^\t/ && $1 !~ /^\/usr\/lib/ && $1 !~ /^\/System\/Library/ {print $1}')
done < <(find "$bundle/Contents" -type f -perm +111 2>/dev/null)
if (( ${#unresolved[@]} > 0 )); then
    echo "ERROR: bundle has unresolved install names after signing:" >&2
    for ref in "${unresolved[@]}"; do
        echo "  $ref" >&2
    done
    exit 1
fi

# 6. Verify that the QML modules Spun actually imports are present in the
#    bundle. macdeployqt crashes on Spun's qml/ tree and we work around it,
#    so without this check a silent failure of the workaround would manifest
#    only at runtime as "module QtQuick.Dialogs is not installed".
for module in QtQuick QtQuick/Controls QtQuick/Dialogs QtQuick/Layouts QtQuick/Window; do
    if [[ ! -f "$bundle/Contents/Resources/qml/$module/qmldir" ]]; then
        echo "ERROR: required QML module $module is missing from the bundle." >&2
        echo "       (expected $bundle/Contents/Resources/qml/$module/qmldir)" >&2
        echo "       This usually means qml_root (\"$qml_root\") did not contain" >&2
        echo "       Qt 6 modules, or the cp/rsync copy failed." >&2
        exit 1
    fi
done
# Quick3D is only required when SPUN_ENABLE_3D was set at build time. We
# detect it by the presence of the QtQuick3D private plugin dylib in the
# bundle; if it's there, the qmldir should be too.
if [[ -f "$bundle/Contents/PlugIns/quick/libqtquick3dquickplugin.dylib" \
   || -f "$bundle/Contents/Resources/qml/QtQuick3D/qmldir" ]]; then
    if [[ ! -f "$bundle/Contents/Resources/qml/QtQuick3D/qmldir" ]]; then
        echo "ERROR: QtQuick3D plugin is present but its qmldir is missing." >&2
        exit 1
    fi
fi
