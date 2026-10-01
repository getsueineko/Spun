// Non-Apple implementation of MacosAccent. The Cocoa-backed class lives in
// macosaccent.mm and is only compiled when APPLE is set (see CMakeLists.txt).
// main.cpp constructs MacosAccent unconditionally, so other platforms need a
// link-time definition: it reports a fixed default colour and never emits
// colorChanged().
#include "macosaccent.h"

struct MacosAccent::Private {};

MacosAccent::MacosAccent(QObject *parent)
    : QObject(parent), d(new Private), m_color(QStringLiteral("#b8c4cf")) {}
MacosAccent::~MacosAccent() { delete d; }
void MacosAccent::refresh() {}
