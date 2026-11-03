#include "macoskeychain.h"

#include <QTest>
#include <QUuid>

class MacosKeychainTest : public QObject {
  Q_OBJECT
private slots:
  void roundTripUpdateAndForget() {
    const QString service = QStringLiteral("com.yappologistic.spun.tests");
    const QString account = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QByteArray first("fixture-secret-one");
    const QByteArray second("fixture-secret-two");
    QVERIFY(MacosKeychain::available());
    QVERIFY(MacosKeychain::write(service, account, first));
    QByteArray value;
    QVERIFY(MacosKeychain::read(service, account, &value));
    QCOMPARE(value, first);
    QVERIFY(MacosKeychain::write(service, account, second));
    QVERIFY(MacosKeychain::read(service, account, &value));
    QCOMPARE(value, second);
    QVERIFY(MacosKeychain::remove(service, account));
    QVERIFY(!MacosKeychain::read(service, account, &value));
  }
};

QTEST_GUILESS_MAIN(MacosKeychainTest)
#include "macoskeychaintest.moc"
