cmake_minimum_required(VERSION 3.22)
project(Spun VERSION 0.1.0 LANGUAGES CXX)
# Bundle identifier is upstream's com.yappologistic.spun; keep it as a single
# CMake variable so Info.plist, MACOSX_BUNDLE_GUI_IDENTIFIER and the
# single-instance server all see the same string.
set(SPUN_BUNDLE_ID "com.yappologistic.spun" CACHE STRING "Reverse-DNS bundle identifier used for the macOS app")
# Capture a stable build description once at configure time so the About
# dialog can show "tag-N-gabcdef" and CFBundleVersion / ShortVersionString
# stay in sync with the commit the binary was produced from. The fallback
# "unknown" keeps out-of-tree builds from looking like a tagged release.
find_package(Git QUIET)
set(SPUN_BUILD_DESC "unknown")
set(SPUN_GIT_TAG "0.1.0")
if(GIT_FOUND)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" describe --tags --always --dirty
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        OUTPUT_VARIABLE SPUN_BUILD_DESC_RAW
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE SPUN_BUILD_DESC_RESULT
    )
    if(SPUN_BUILD_DESC_RESULT EQUAL 0 AND NOT SPUN_BUILD_DESC_RAW STREQUAL "")
        set(SPUN_BUILD_DESC "${SPUN_BUILD_DESC_RAW}")
    endif()
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" describe --tags --abbrev=0
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        OUTPUT_VARIABLE SPUN_GIT_TAG_RAW
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE SPUN_GIT_TAG_RESULT
    )
    if(SPUN_GIT_TAG_RESULT EQUAL 0 AND NOT SPUN_GIT_TAG_RAW STREQUAL "")
        # Strip any leading path-like prefix (e.g. macos-port-v1.2.1 -> 1.2.1)
        # so CFBundleVersion stays numeric-only as required by macOS.
        string(REGEX REPLACE "^.*-v" "" SPUN_GIT_TAG "${SPUN_GIT_TAG_RAW}")
        string(REGEX REPLACE "^v" "" SPUN_GIT_TAG "${SPUN_GIT_TAG}")
    endif()
endif()
message(STATUS "Spun build description: ${SPUN_BUILD_DESC} (tag ${SPUN_GIT_TAG})")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
include(CTest)
include(CheckIPOSupported)
include(CheckCXXSourceCompiles)
include(CheckLinkerFlag)
include(CheckCXXCompilerFlag)
set(SPUN_SIZE_OPTIMIZATION -Os)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    check_cxx_compiler_flag(-Oz SPUN_OZ_SUPPORTED)
    if(SPUN_OZ_SUPPORTED)
        set(SPUN_SIZE_OPTIMIZATION -Oz)
    endif()
endif()
check_ipo_supported(RESULT SPUN_IPO_SUPPORTED OUTPUT SPUN_IPO_ERROR)
if(SPUN_IPO_SUPPORTED)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    # Packed relative relocations require a compatible loader. Older target
    # libc/toolchains keep the normal ELF tables when building from source.
    check_cxx_source_compiles("#include <features.h>
        #if !defined(__GLIBC_PREREQ)
        #error Unsupported loader
        #elif !__GLIBC_PREREQ(2,36)
        #error Older loader
        #endif
        int main() { return 0; }" SPUN_RELR_RUNTIME)
    if(SPUN_RELR_RUNTIME)
        check_linker_flag(CXX "LINKER:-z,pack-relative-relocs" SPUN_RELR_SUPPORTED)
    endif()
endif()
find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Quick Qml QuickControls2 Multimedia Concurrent DBus Network Svg)
option(SPUN_ENABLE_3D "Build optional Qt Quick 3D player view" ON)
if(SPUN_ENABLE_3D)
    find_package(Qt6 6.8 QUIET COMPONENTS Quick3D)
endif()
qt_policy(SET QTP0004 NEW)
find_package(PkgConfig REQUIRED)
pkg_check_modules(TAGLIB REQUIRED IMPORTED_TARGET taglib>=2.0)
qt_add_library(spun_core STATIC
    src/symbol.cpp src/symbol.h src/typography.cpp src/typography.h
    src/listening.cpp src/listening.h src/tapesound.cpp src/tapesound.h src/vinylnoise.cpp src/vinylnoise.h
    src/musicactions.cpp src/musicactions.h
    src/library.cpp src/library.h src/lyrics.cpp src/lyrics.h src/artwork.cpp src/artwork.h
    src/tx6.cpp src/tx6.h src/youtube.cpp src/youtube.h src/jellyfinapi.cpp src/jellyfinapi.h src/remotemusicapi.h src/remotelibrary.cpp src/remotelibrary.h src/jellyfin.h src/subsonicapi.cpp src/subsonicapi.h
    src/player.cpp src/player.h src/disc.cpp src/disc.h src/recorder.cpp src/recorder.h src/playerbody.cpp src/playerbody.h src/mpris.cpp src/mpris.h
    src/theme.cpp src/theme.h src/cider.cpp src/cider.h src/ciderevents.cpp src/ciderevents.h)
if(APPLE)
    target_sources(spun_core PRIVATE src/macosaccent.mm src/macosaccent.h
                                     src/macosmenubar.mm src/macosmenubar.h)
    target_link_libraries(spun_core PRIVATE "-framework Cocoa" "-framework AppKit")
    # Compile the Objective-C++ sources with ARC so Cocoa allocations stay in
    # step with the Obj-C reference counts and we do not have to balance every
    # alloc/release pair manually. The .mm files use `assign` on a raw C++
    # pointer for the MacosMenuBar back-reference, which ARC treats like MRC.
    set_source_files_properties(src/macosaccent.mm src/macosmenubar.mm
        PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
endif()
target_link_libraries(spun_core PUBLIC Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::QuickControls2
    Qt6::Svg Qt6::Multimedia Qt6::Concurrent Qt6::DBus Qt6::Network PkgConfig::TAGLIB)
if(TARGET Qt6::Quick3D AND SPUN_ENABLE_3D)
    target_sources(spun_core PRIVATE src/deckgeometry.cpp src/deckgeometry.h src/cablegeometry.cpp src/cablegeometry.h src/mediageometry.cpp src/mediageometry.h)
    target_link_libraries(spun_core PUBLIC Qt6::Quick3D)
    target_compile_definitions(spun_core PUBLIC SPUN_WITH_3D=1)
    set(SPUN_3D_QML qml/Player3D.qml qml/Recorder3D.qml qml/Tx6_3D.qml qml/Tx6Cable3D.qml qml/Vinyl3D.qml qml/Cassette3D.qml qml/Cd3D.qml)
endif()
set(SPUN_DEMO_FILE "${CMAKE_CURRENT_SOURCE_DIR}/assets/First-Light.flac" CACHE FILEPATH "Installed or source demo audio file")
target_compile_definitions(spun_core PUBLIC SPUN_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}" SPUN_DEMO_FILE="${SPUN_DEMO_FILE}")
target_compile_options(spun_core PRIVATE -Wall -Wextra -Wpedantic)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    # Keep Release code compact without changing floating-point semantics or
    # disabling exceptions. The animated geometry retains full speed optimization.
    target_compile_options(spun_core PRIVATE "$<$<CONFIG:Release>:${SPUN_SIZE_OPTIMIZATION};-ffunction-sections;-fdata-sections>")
    set_source_files_properties(src/disc.cpp src/mediageometry.cpp src/deckgeometry.cpp src/cablegeometry.cpp PROPERTIES COMPILE_OPTIONS "$<$<CONFIG:Release>:-O3>")
endif()
file(GLOB SPUN_SYMBOLS CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons/*.svg")
set_source_files_properties(qml/SpunStyle.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
# The font picker is prepared asynchronously on opening Preferences. Its source
# remains bundled; there is no need to carry another copy as startup bytecode.
set_source_files_properties(qml/FontPicker.qml PROPERTIES QT_QML_SKIP_CACHEGEN TRUE)
function(spun_application target)
    qt_add_executable(${target} src/main.cpp)
    target_link_libraries(${target} PRIVATE spun_core)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
    set_target_properties(${target} PROPERTIES QT_QMLCACHEGEN_ARGUMENTS "--only-bytecode")
    # Compile QML at build time, preserving existing resource URLs and the UI.
    qt_add_qml_module(${target} URI SpunUi VERSION 1.0 NO_PLUGIN
        NO_RESOURCE_TARGET_PATH RESOURCE_PREFIX "/" OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${target}-qml"
        QML_FILES qml/RemoteLibraryPanel.qml qml/SpunChoiceButton.qml qml/SpunLoading.qml qml/YoutubePanel.qml ${SPUN_3D_QML} qml/Recorder.qml qml/RecorderDisplay.qml qml/Tx6Controls.qml qml/Tx6Labels.qml qml/Tx6Display.qml qml/CassetteControls.qml qml/CdControls.qml qml/CdDisplay.qml qml/SpunButton.qml qml/SpunSlider.qml qml/SeekSlider.qml qml/QuickJump.qml qml/NextTrackTip.qml qml/SavedQueuePicker.qml qml/Tonearm.qml qml/CassetteReels.qml qml/SpunText.qml qml/FontPicker.qml qml/SpunStateLayer.qml qml/SpunSpring.qml qml/SpunPopupEnter.qml qml/SpunStyle.qml qml/TrackContent.qml qml/SpunSearchField.qml qml/MenuEntry.qml qml/PreferenceSwitch.qml qml/TrackMenu.qml qml/Main.qml qml/LibraryPanel.qml qml/SpunToolTip.qml qml/IconButton.qml qml/Glyph.qml)
    # Preserve the exact SVGs and URLs; Qt's default threshold leaves many of
    # these small resources uncompressed. Parsed symbols are already cached.
    if(QT_FEATURE_zstd)
        set(asset_compression --compress-algo zstd --compress 19 --threshold 0)
    else()
        set(asset_compression --compress-algo zlib --compress 9 --threshold 0)
    endif()
    qt_add_resources(${target} "${target}_assets" PREFIX "/"
        FILES ${SPUN_SYMBOLS} assets/spun-window.png licenses/MaterialSymbols-LICENSE.txt
        OPTIONS ${asset_compression})
    target_compile_definitions(${target} PRIVATE
        SPUN_BUILD_DESC="${SPUN_BUILD_DESC}")
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(${target} PRIVATE "$<$<CONFIG:Release>:${SPUN_SIZE_OPTIMIZATION};-ffunction-sections;-fdata-sections>")
        if(NOT APPLE)
            target_link_options(${target} PRIVATE "$<$<CONFIG:Release>:-Wl,--gc-sections>")
        else()
            target_link_options(${target} PRIVATE "$<$<CONFIG:Release>:LINKER:-dead_strip>")
        endif()
        if(SPUN_RELR_RUNTIME AND SPUN_RELR_SUPPORTED)
            target_link_options(${target} PRIVATE "$<$<CONFIG:Release>:LINKER:-z,pack-relative-relocs>")
        endif()
    endif()
endfunction()
spun_application(spun)
if(APPLE)
    # Qt's MACOSX_BUNDLE_INFO_PLIST handler copies the template into
    # Contents/Info.plist during the link step and substitutes
    # @SPUN_BUNDLE_ID@ / @PROJECT_VERSION@ (defined below) before doing so.
    # We hand it the source template directly rather than a configure_file
    # output, because the auto-copy only triggers for paths that live in
    # the source tree.
    set(SPUN_VERSION "${SPUN_GIT_TAG}")
    set_target_properties(spun PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/resources/Info.plist.in"
        MACOSX_BUNDLE_BUNDLE_NAME "Spun"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${SPUN_BUNDLE_ID}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${SPUN_GIT_TAG}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${SPUN_GIT_TAG}"
        MACOSX_BUNDLE_COPYRIGHT "Copyright (c) 2026 Spun contributors"
        OUTPUT_NAME "Spun"
    )
    # Bundle the icon into Resources/ of the app
    if(EXISTS "${CMAKE_SOURCE_DIR}/resources/spun-icon.icns")
        set_source_files_properties("${CMAKE_SOURCE_DIR}/resources/spun-icon.icns"
            PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
        target_sources(spun PRIVATE "${CMAKE_SOURCE_DIR}/resources/spun-icon.icns")
    endif()

    # macOS deployment pipeline:
    #   1. macdeployqt bundles Qt frameworks + plugins into the .app
    #   2. We strip absolute Homebrew rpaths from the deployed frameworks so
    #      macOS stops also loading /opt/homebrew's Qt and crashing with
    #      "Class X is implemented in both" duplicate-class errors
    #   3. Add @executable_path/../Frameworks as rpath on every framework that
    #      references @rpath/* so dependencies resolve to the bundle
    #   4. Ad-hoc codesign the whole bundle with a single shared identifier so
    #      Gatekeeper accepts the inner frameworks as belonging to the app
    # Without step 4, macOS 14+ LaunchServices rejects the bundle with
    # "different Team IDs" and the app crashes before reaching main().
    find_program(MACDEPLOYQT_EXECUTABLE macdeployqt HINTS "${Qt6_DIR}/../../../bin")
    if(MACDEPLOYQT_EXECUTABLE)
        # Omit -qmldir: the Qt 6.11 qmlimportscanner crashes on Spun's qml/
        # tree. The static QML cache already in the binary carries everything
        # Main.qml actually uses.
        add_custom_command(TARGET spun POST_BUILD
            COMMAND "${MACDEPLOYQT_EXECUTABLE}"
                "$<TARGET_BUNDLE_DIR:spun>"
                -no-codesign
                -no-strip
            COMMENT "Deploying Qt frameworks into Spun.app via macdeployqt"
            VERBATIM
        )
        # The QML plugins, rpath rewriting and ad-hoc signing are all done
        # by scripts/sign-macos-bundle.sh in a single deterministic order.
        # file(COPY ...) cannot be sequenced against add_custom_command(POST_BUILD)
        # reliably on multi-job Ninja builds, so we run everything in shell.
        find_program(INSTALL_NAME_TOOL_EXECUTABLE install_name_tool)
        find_program(CODESIGN_EXECUTABLE codesign)
        if(INSTALL_NAME_TOOL_EXECUTABLE AND CODESIGN_EXECUTABLE)
            set(_bundle "$<TARGET_BUNDLE_DIR:spun>")
            # Resolve the QML root in this order: explicit SPUN_QML_ROOT env
            # var → user-supplied cache value → the conventional Homebrew path
            # derived from Qt6_DIR. SPUN_QML_ROOT lets people point at a Qt
            # installed via the official installer (where the share path is
            # <prefix>/macos/share/qt/qml rather than /opt/homebrew/share/qt/qml).
            if(NOT SPUN_QML_ROOT AND NOT DEFINED SPUN_QML_ROOT_CACHE)
                set(SPUN_QML_ROOT_CACHE "${Qt6_DIR}/../../../share/qt/qml" CACHE PATH "Qt QML root used by sign-macos-bundle.sh")
            endif()
            if(DEFINED ENV{SPUN_QML_ROOT})
                set(_qml_root "$ENV{SPUN_QML_ROOT}")
            else()
                set(_qml_root "${SPUN_QML_ROOT_CACHE}")
            endif()
            set(_entitlements "${CMAKE_SOURCE_DIR}/resources/spun.entitlements")
            add_custom_command(TARGET spun POST_BUILD
                COMMAND "${CMAKE_SOURCE_DIR}/scripts/sign-macos-bundle.sh"
                    "${_bundle}"
                    "${SPUN_BUNDLE_ID}"
                    "${_entitlements}"
                    "${_qml_root}"
                COMMENT "Deploying QML plugins, rewriting rpaths and ad-hoc signing Spun.app"
                VERBATIM
            )
        endif()
    endif()
endif()
if(CMAKE_STRIP AND CMAKE_BUILD_TYPE STREQUAL "Release")
    # Debug/RelWithDebInfo builds retain symbols; strip only the shipped Release app.
    # On Apple the strip step is skipped: macdeployqt (run below) rewrites the
    # binary into the bundle and re-signs ad-hoc, so doing the strip here would
    # either invalidate the codesign stamp or be wasted work.
    if(NOT APPLE)
        add_custom_command(TARGET spun POST_BUILD COMMAND ${CMAKE_STRIP} --strip-unneeded $<TARGET_FILE:spun>)
    endif()
endif()
if(BUILD_TESTING)
    find_package(Qt6 REQUIRED COMPONENTS Test)
    spun_application(spun-diagnostics)
    target_sources(spun-diagnostics PRIVATE src/subsonictest.cpp src/jellyfintest.cpp src/youtubetest.cpp src/librarytest.cpp src/librarytest.h src/eventstest.cpp src/mediauitest.cpp src/threedtest.cpp src/artworktest.cpp src/recordertest.cpp src/turntabletest.cpp src/cassettedecktest.cpp src/cddecktest.cpp src/tx6test.cpp)
    target_sources(spun-diagnostics PRIVATE src/performancetest.cpp src/performancetest.h)
    target_compile_definitions(spun-diagnostics PRIVATE SPUN_DIAGNOSTICS)
    target_link_libraries(spun-diagnostics PRIVATE Qt6::Test)
    if(TARGET Qt6::Quick3D AND SPUN_ENABLE_3D)
        qt_add_executable(spun-geometry-test src/geometrytest.cpp)
        target_link_libraries(spun-geometry-test PRIVATE spun_core Qt6::Test)
        add_test(NAME spun-3d-geometry COMMAND spun-geometry-test)
        set_tests_properties(spun-3d-geometry PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=")
    endif()
    qt_add_executable(spun-media-test src/mediatest.cpp)
    target_link_libraries(spun-media-test PRIVATE spun_core Qt6::Test)
    find_program(SPUN_DBUS_RUN_SESSION dbus-run-session)
    if(SPUN_DBUS_RUN_SESSION)
        add_test(NAME spun-desktop-media COMMAND ${SPUN_DBUS_RUN_SESSION} -- $<TARGET_FILE:spun-media-test>)
        set_tests_properties(spun-desktop-media PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=")
    endif()
    qt_add_executable(spun-import-test src/importtest.cpp)
    target_link_libraries(spun-import-test PRIVATE spun_core Qt6::Test)
    add_test(NAME spun-folder-import COMMAND spun-import-test)
    set_tests_properties(spun-folder-import PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=")
    add_test(NAME spun-refresh-independent-motion COMMAND spun-diagnostics --test-performance)
    set_tests_properties(spun-refresh-independent-motion PROPERTIES ENVIRONMENT "SPUN_PERF_TIMING_ONLY=1;QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QSG_RENDER_LOOP=basic;QT_QPA_PLATFORMTHEME=")
    add_test(NAME spun-youtube COMMAND spun-diagnostics --test-youtube)
    set_tests_properties(spun-youtube PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QSG_RENDER_LOOP=basic;QT_QPA_PLATFORMTHEME=")
    add_test(NAME spun-playback-and-ui COMMAND spun-diagnostics --self-test)
    set_tests_properties(spun-playback-and-ui PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QSG_RENDER_LOOP=basic;QT_QPA_PLATFORMTHEME=")
endif()

if(BUILD_TESTING)
    qt_add_executable(spun-jellyfin-protocol-test src/jellyfinprotocoltest.cpp)
    target_link_libraries(spun-jellyfin-protocol-test PRIVATE spun_core Qt6::Test)
    add_test(NAME spun-jellyfin-protocol COMMAND spun-jellyfin-protocol-test)
    set_tests_properties(spun-jellyfin-protocol PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=")
endif()

if(BUILD_TESTING)
    qt_add_executable(spun-subsonic-protocol-test src/subsonicprotocoltest.cpp)
    target_link_libraries(spun-subsonic-protocol-test PRIVATE spun_core Qt6::Test)
    add_test(NAME spun-subsonic-protocol COMMAND spun-subsonic-protocol-test)
    set_tests_properties(spun-subsonic-protocol PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=")
endif()

if(BUILD_TESTING)
    qt_add_executable(spun-remote-library-test src/remotelibrarytest.cpp)
    target_link_libraries(spun-remote-library-test PRIVATE spun_core Qt6::Test)
    add_test(NAME spun-remote-library COMMAND spun-remote-library-test)
    set_tests_properties(spun-remote-library PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=")
    add_test(NAME spun-immersive-media-ui COMMAND spun-diagnostics --test-media-ui)
    set_tests_properties(spun-remote-library PROPERTIES TIMEOUT 120 LABELS "remote;regression")
    set_tests_properties(spun-immersive-media-ui PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QSG_RENDER_LOOP=basic;QT_QPA_PLATFORMTHEME="
        TIMEOUT 180 LABELS "ui;regression")
endif()
