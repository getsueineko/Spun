#include "macosappearance.h"

#include <QTimer>

#ifdef Q_OS_MACOS
#import <Cocoa/Cocoa.h>

namespace {
// macOS expresses the effective UI scheme through NSAppearanceNameAqua and
// NSAppearanceNameDarkAqua. Anything else (HighContrast, increased
// contrast accessibility profiles) is treated as Light by default so the
// UI does not collapse when the user enables an accessibility mode that
// the rest of Spun does not explicitly support.
MacosAppearance::Mode resolveMode() {
    NSAppearanceName name = [[NSApp effectiveAppearance] name];
    if (name == NSAppearanceNameDarkAqua)
        return MacosAppearance::Dark;
    return MacosAppearance::Light;
}
}
#endif

struct MacosAppearance::Private {
#ifdef Q_OS_MACOS
    id observerToken = nil; // NSDistributedNotificationCenter observer token.
    QTimer *poller = nullptr; // Fallback poll: see macosaccent.mm for rationale.
#endif
};

MacosAppearance::MacosAppearance(QObject *parent)
    : QObject(parent), d(new Private) {
#ifdef Q_OS_MACOS
    m_mode = resolveMode();
    // AppleInterfaceThemeChangedNotification fires when the user toggles
    // Light/Dark in System Settings while Spun is running. The same
    // distributed-notification caveat as accent applies: some builds drop
    // the notification, so a low-frequency poll catches the missed case
    // without paying the cost of a KVO observer.
    MacosAppearance *weakSelf = this;
    d->observerToken =
        [[NSDistributedNotificationCenter defaultCenter]
            addObserverForName:@"AppleInterfaceThemeChangedNotification"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        (void)note;
                        weakSelf->refresh();
                    }];
    d->poller = new QTimer(this);
    d->poller->setInterval(5000);
    d->poller->setTimerType(Qt::VeryCoarseTimer);
    QObject::connect(d->poller, &QTimer::timeout, this, &MacosAppearance::refresh);
    d->poller->start();
#endif
}

MacosAppearance::~MacosAppearance() {
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

void MacosAppearance::refresh() {
#ifdef Q_OS_MACOS
    const Mode next = resolveMode();
    if (next == m_mode) return;
    m_mode = next;
    emit modeChanged();
#endif
}
