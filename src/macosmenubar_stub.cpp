// Non-Apple implementation of MacosMenuBar. The real, Cocoa-backed class lives
// in macosmenubar.mm and is only compiled when APPLE is set (see CMakeLists.txt).
// main.cpp wires MacosMenuBar into QML unconditionally, so every other platform
// needs a link-time definition too. Every method is a deliberate no-op; the
// signals declared in macosmenubar.h are simply never emitted.
#include "macosmenubar.h"

struct MacosMenuBar::Private {};

MacosMenuBar::MacosMenuBar(QObject *parent) : QObject(parent), d(new Private) {}
MacosMenuBar::~MacosMenuBar() { delete d; }

void MacosMenuBar::attachToWindow(QWindow *) {}
void MacosMenuBar::setPlaybackPlaying(bool) {}
void MacosMenuBar::setShuffleChecked(bool) {}
void MacosMenuBar::setRepeatChecked(bool) {}
void MacosMenuBar::setRepeatMode(int) {}
void MacosMenuBar::setSidebarVisible(bool) {}
void MacosMenuBar::setQueueVisible(bool) {}
void MacosMenuBar::setMediumActive(const QString &) {}
void MacosMenuBar::setTextEditing(bool) {}
void MacosMenuBar::setOverlayOpen(bool) {}
