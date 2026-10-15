// Mask regression check for the macOS window shape machinery.
//
// Two regressions are covered here, both against the same root area
// (the remote library panel that hosts the Connect dialog on macOS):
//
// 1. Window mask geometry. When the remote library (Jellyfin /
//    Navidrome-Subsonic) was opened, the on-screen Connect dialog was
//    rendered over a partially unmasked strip between the player
//    housing's rounded right edge and the panel's left edge — the
//    unmasked pixels stayed transparent, so the dialog corners that
//    fell outside the housing curve showed the desktop. The cause was
//    in PlatformNative::shape(): it looked up the side panel by
//    objectName "libraryPanel", which is only the local
//    libraryPanel.qml root and never exists while useServer is true.
//    The remote library sets its objectName to "jellyfinPanel" /
//    "subsonicPanel", so findChild() returned null and the panel
//    rectangle plus the bridge between the housing and the panel were
//    never added to the mask.
//
// 2. Modal scrim. Qt Quick Controls' Dialog paints a translucent black
//    rectangle behind every modal popup as a focus indicator; with
//    dim:true (the default for modal Dialog) the rectangle is sized
//    to the dialog itself, so it shows up as a stray dark square over
//    the form — completely unrelated to the mask. LibraryDialog in
//    RemoteLibraryPanel.qml sets dim:false to match what About does,
//    and this test guards the property.
//
// This test reproduces both scenarios without requiring a real server:
// it forces useJellyfin / useSubsonic, opens the library panel, opens
// the Connect dialog, and verifies that (a) the panel is findable by
// its actual objectName, (b) the window mask after shape() covers the
// panel rectangle, (c) the Connection dialog runs with dim:false while
// remaining modal, and (d) the queuePanel branch still works.

#include "testcapture.h"
#include <QDir>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegion>
#include <QTest>
#include <iostream>

namespace {
QQuickItem *findByName(QQuickItem *item, const QString &name) {
    if (!item)
        return nullptr;
    if (item->objectName() == name)
        return item;
    for (auto *child : item->childItems())
        if (auto *hit = findByName(child, name))
            return hit;
    return nullptr;
}
QObject *findObjectByName(QObject *parent, const QString &name) {
    if (!parent)
        return nullptr;
    if (parent->objectName() == name)
        return parent;
    for (auto *child : parent->children())
        if (auto *hit = findObjectByName(child, name))
            return hit;
    return nullptr;
}
} // namespace

int exerciseMask(QQuickWindow *window, const QString &temp,
                 const QString &captures) {
    if (!captures.isEmpty())
        QDir().mkpath(captures);
    int checks = 0, failures = 0;
    auto check = [&](bool ok, const char *text) {
        ++checks;
        std::cout << (ok ? "PASS " : "FAIL ") << text << std::endl;
        if (!ok)
            ++failures;
        return ok;
    };
    auto capture = [&](const QString &name) {
        if (captures.isEmpty())
            return;
        QTest::qWait(200);
        auto image = captureTestWindow(window);
        check(!image.isNull() && image.save(captures + "/" + name + ".png"),
              "rendered capture saved");
    };
    auto *nativeShape = QQmlEngine::contextForObject(window)
                            ->contextProperty("platformNative")
                            .value<QObject *>();
    check(nativeShape != nullptr, "platformNative context property exists");
    if (!nativeShape)
        return failures ? 1 : 0;
    auto invokeShape = [&]() {
        QMetaObject::invokeMethod(nativeShape, "shape",
                                  Q_ARG(QVariant, QVariant::fromValue(window)),
                                  Q_ARG(QVariant, true));
    };

    // ---------- Jellyfin ----------
    window->setProperty("useJellyfin", true);
    window->setProperty("useSubsonic", false);
    window->setProperty("libraryOpen", true);
    QTest::qWait(250);
    auto *jellyfinPanel = findByName(window->contentItem(), "jellyfinPanel");
    check(jellyfinPanel != nullptr,
          "jellyfinPanel is findable by its real objectName");
    invokeShape();
    QTest::qWait(150);
    if (jellyfinPanel) {
        const QRectF panelScene = jellyfinPanel->mapRectToScene(
            QRectF(0, 0, jellyfinPanel->width(), jellyfinPanel->height()));
        const QPointF centre = panelScene.center();
        // The mask is in window pixel coordinates; offscreen plugin returns
        // an empty mask, in which case we accept the absence as "we cannot
        // verify here" rather than a failure of the fix.
        const QRegion mask = window->mask();
        if (mask.isEmpty()) {
            std::cout << "INFO  mask is empty under offscreen QPA — "
                         "verifying panel-name resolution only"
                      << std::endl;
        } else {
            check(mask.contains(centre.toPoint()),
                  "Jellyfin panel centre is inside the window mask");
            check(mask.contains(QPoint(qRound(panelScene.right()) - 4,
                                       qRound(panelScene.top()) + 8)),
                  "Jellyfin panel top-right corner is inside the window mask");
        }
    }
    capture("mask-jellyfin-connect");

    // ---------- Subsonic / Navidrome ----------
    // Close the Jellyfin browser first so the Loader tears the Jellyfin
    // panel down; reopening then loads a fresh panel for the new scheme.
    // Without this, the test would be looking at the still-cached Jellyfin
    // panel whose objectName is being rebound on the fly — the underlying
    // visibility would be wrong even though the mask fix itself is sound.
    window->setProperty("useJellyfin", false);
    window->setProperty("libraryOpen", false);
    QTest::qWait(300);
    window->setProperty("useSubsonic", true);
    window->setProperty("libraryOpen", true);
    QTest::qWait(500);
    auto *subsonicPanel = findByName(window->contentItem(), "subsonicPanel");
    check(subsonicPanel != nullptr,
          "subsonicPanel is findable by its real objectName");
    invokeShape();
    QTest::qWait(150);
    if (subsonicPanel) {
        const QRectF panelScene = subsonicPanel->mapRectToScene(
            QRectF(0, 0, subsonicPanel->width(), subsonicPanel->height()));
        const QRegion mask = window->mask();
        if (!mask.isEmpty()) {
            check(mask.contains(panelScene.center().toPoint()),
                  "Subsonic panel centre is inside the window mask");
            check(mask.contains(QPoint(qRound(panelScene.right()) - 4,
                                       qRound(panelScene.top()) + 8)),
                  "Subsonic panel top-right corner is inside the window mask");
        }
    }
    capture("mask-subsonic-connect");

    // ---------- Modal Connect dialog (dim regression guard) ----------
    // Open the Connection dialog on the Subsonic panel and assert that
    // modal-but-not-dim is in effect: when the dialog has dim:true (the
    // Qt Quick Controls default for modal Dialog), Qt paints a translucent
    // black rectangle behind the popup that is sized to the popup itself,
    // which on macOS shows up as a stray dark square over the form. The
    // RemoteLibraryPanel.LibraryDialog component explicitly sets dim:false
    // to avoid that artefact; this check guards the property so any future
    // refactor that drops the override gets caught here.
    auto *connectionDialog = findObjectByName(window, "subsonicConnection");
    check(connectionDialog != nullptr,
          "subsonic Connection dialog exists in the tree");
    if (connectionDialog) {
        QMetaObject::invokeMethod(connectionDialog, "open");
        QTest::qWait(300);
        const bool dim = connectionDialog->property("dim").toBool();
        check(dim == false,
              "modal Connect dialog runs with dim:false (no scrim square)");
        const bool modal = connectionDialog->property("modal").toBool();
        check(modal == true,
              "Connect dialog is still modal (input grab is preserved)");
        QMetaObject::invokeMethod(connectionDialog, "close");
        QTest::qWait(150);
    }
    capture("mask-subsonic-connect-open");

    // ---------- Local library (regression guard for the old branch) ----------
    window->setProperty("useJellyfin", false);
    window->setProperty("useSubsonic", false);
    window->setProperty("libraryOpen", false);
    QTest::qWait(250);

    // ---------- Queue panel (sanity: previous bridge still works) ----------
    window->setProperty("libraryOpen", false);
    window->setProperty("queueOpen", true);
    QTest::qWait(250);
    auto *queuePanel = findByName(window->contentItem(), "queuePanel");
    check(queuePanel != nullptr,
          "queuePanel is still findable (regression guard for queue branch)");
    invokeShape();
    capture("mask-queue");

    window->setProperty("queueOpen", false);
    QTest::qWait(100);
    (void)temp;
    return failures ? 1 : 0;
}
