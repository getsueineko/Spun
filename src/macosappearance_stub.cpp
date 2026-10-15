// Non-Apple implementation of MacosAppearance. The Cocoa-backed class lives
// in macosappearance.mm and is only compiled when APPLE is set (see
// CMakeLists.txt). main.cpp constructs MacosAppearance unconditionally, so
// other platforms need a link-time definition: it always reports System and
// never emits modeChanged.
#include "macosappearance.h"

struct MacosAppearance::Private {};

MacosAppearance::MacosAppearance(QObject *parent)
    : QObject(parent), d(new Private) {}
MacosAppearance::~MacosAppearance() { delete d; }
void MacosAppearance::refresh() {}
