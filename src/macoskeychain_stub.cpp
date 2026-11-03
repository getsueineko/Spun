#include "macoskeychain.h"

namespace MacosKeychain {
bool available() { return false; }
bool read(const QString &, const QString &, QByteArray *) { return false; }
bool write(const QString &, const QString &, const QByteArray &) { return false; }
bool remove(const QString &, const QString &) { return false; }
} // namespace MacosKeychain
