#include "cider.h"
#include "macoskeychain.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QUuid>
#include <QTest>

class CiderMacosKeychainTest : public QObject {
  Q_OBJECT
private slots:
  void migratesLegacyTokenFile() {
    QTemporaryDir temporary;
    QVERIFY(temporary.isValid());
    const QString account = QStringLiteral("stage1-") +
        QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QString service = QStringLiteral("com.yappologistic.spun");
    const auto clear = qScopeGuard([&] { MacosKeychain::remove(service, account); });
    MacosKeychain::remove(service, account);

    const QString legacyPath = temporary.filePath("cider-connection.json");
    QFile legacy(legacyPath);
    QVERIFY(legacy.open(QIODevice::WriteOnly));
    const QByteArray token("fixture-cider-token");
    QVERIFY(legacy.write(QJsonDocument(QJsonObject{{"token", QString::fromUtf8(token)}})
                             .toJson(QJsonDocument::Compact)) > 0);
    QVERIFY(legacy.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner));
    legacy.close();

    Cider cider(false, legacyPath, QUrl("http://127.0.0.1:1"), nullptr,
                true, account);
    QByteArray stored;
    QVERIFY(MacosKeychain::read(service, account, &stored));
    QCOMPARE(stored, token);
    QVERIFY(!QFile::exists(legacyPath));
  }
};

QTEST_GUILESS_MAIN(CiderMacosKeychainTest)
#include "cidermacoskeychaintest.moc"
