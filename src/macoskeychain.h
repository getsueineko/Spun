#pragma once

#include <QByteArray>
#include <QString>

namespace MacosKeychain {
bool available();
bool read(const QString &service, const QString &account, QByteArray *value);
bool write(const QString &service, const QString &account,
           const QByteArray &value);
bool remove(const QString &service, const QString &account);
} // namespace MacosKeychain
