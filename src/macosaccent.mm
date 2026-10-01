#include "macosaccent.h"

#include <QTimer>

#ifdef Q_OS_MACOS
#import <Cocoa/Cocoa.h>

namespace {
QColor readSystemAccent() {
    // macOS exposes the user-chosen accent colour as +controlAccentColor
    // since 10.14. (iOS uses systemAccentColor; the names differ.)
    NSColor *color = [[NSColor controlAccentColor] colorUsingColorSpace:
                      [NSColorSpace sRGBColorSpace]];
    if (!color) return QColor("#b8c4cf");
    const CGFloat r = [color redComponent];
    const CGFloat g = [color greenComponent];
    const CGFloat b = [color blueComponent];
    const CGFloat a = [color alphaComponent];
    QColor qc = QColor::fromRgbF(qBound(0., double(r), 1.),
                                 qBound(0., double(g), 1.),
                                 qBound(0., double(b), 1.));
    if (a < 1.) qc.setAlphaF(qBound(0., double(a), 1.));
    return qc;
}
}
#endif

struct MacosAccent::Private {
#ifdef Q_OS_MACOS
    id observerToken = nil; // Opaque observer token returned by NSDistributedNotificationCenter.
    QTimer *poller = nullptr; // Fallback poll in case the distributed
                              // notification does not arrive (some macOS
                              // builds or signed bundles drop it).
#endif
};

MacosAccent::MacosAccent(QObject *parent)
    : QObject(parent), d(new Private) {
#ifdef Q_OS_MACOS
    m_color = readSystemAccent();
    // NSDistributedNotificationCenter does not deliver to sandboxed apps
    // targeting the App Store, but for an ad-hoc-signed desktop build the
    // notification arrives and lets us react to accent changes in System
    // Settings while Spun is running. MacosAccent is a QObject (C++) so the
    // observer block holds a raw pointer; the destructor always calls
    // removeObserver: on the same thread before deleting the object, so the
    // block cannot outlive `this` in practice.
    MacosAccent *weakSelf = this;
    d->observerToken =
        [[NSDistributedNotificationCenter defaultCenter]
            addObserverForName:@"AppleColorPreferencesChangedNotification"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        (void)note;
                        weakSelf->refresh();
                    }];
    // Some macOS configurations do not deliver
    // AppleColorPreferencesChangedNotification (notably when the user
    // changes the accent without focus leaving System Settings). A 5 s poll
    // is cheap (one +controlAccentColor + QColor comparison) and covers the
    // gap; refresh() is a no-op when the value did not change, so bindings
    // are not re-evaluated spuriously.
    d->poller = new QTimer(this);
    d->poller->setInterval(5000);
    d->poller->setTimerType(Qt::VeryCoarseTimer);
    QObject::connect(d->poller, &QTimer::timeout, this, &MacosAccent::refresh);
    d->poller->start();
#endif
}

MacosAccent::~MacosAccent() {
#ifdef Q_OS_MACOS
    if (d->observerToken) {
        [[NSDistributedNotificationCenter defaultCenter]
            removeObserver:d->observerToken];
        d->observerToken = nil;
    }
    if (d->poller) {
        d->poller->stop();
        d->poller = nullptr;
    }
#endif
    delete d;
}

void MacosAccent::refresh() {
#ifdef Q_OS_MACOS
    const QColor next = readSystemAccent();
    if (next == m_color) return;
    m_color = next;
    emit colorChanged();
#endif
}
