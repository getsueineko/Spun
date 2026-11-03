#include "macoskeychain.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <QDebug>

namespace {
NSDictionary *query(const QString &service, const QString &account) {
  NSString *serviceString = [NSString stringWithUTF8String:service.toUtf8().constData()];
  NSString *accountString = [NSString stringWithUTF8String:account.toUtf8().constData()];
  return @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: serviceString,
    (__bridge id)kSecAttrAccount: accountString,
  };
}
} // namespace

namespace MacosKeychain {
bool available() { return true; }

bool read(const QString &service, const QString &account, QByteArray *value) {
  if (!value) return false;
  NSMutableDictionary *attributes = [query(service, account) mutableCopy];
  attributes[(__bridge id)kSecReturnData] = @YES;
  attributes[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
  CFTypeRef result = nullptr;
  const OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)attributes, &result);
  if (status != errSecSuccess || !result) return false;
  NSData *data = CFBridgingRelease(result);
  *value = QByteArray(static_cast<const char *>(data.bytes), static_cast<qsizetype>(data.length));
  return true;
}

bool write(const QString &service, const QString &account, const QByteArray &value) {
  NSMutableDictionary *attributes = [query(service, account) mutableCopy];
  NSData *data = [NSData dataWithBytes:value.constData() length:static_cast<NSUInteger>(value.size())];
  attributes[(__bridge id)kSecValueData] = data;
  const OSStatus added = SecItemAdd((__bridge CFDictionaryRef)attributes, nullptr);
  if (added == errSecSuccess) return true;
  if (added != errSecDuplicateItem) {
    qWarning() << "Keychain add failed with OSStatus" << added;
    return false;
  }
  NSDictionary *updates = @{(__bridge id)kSecValueData: data};
  const OSStatus updated = SecItemUpdate((__bridge CFDictionaryRef)query(service, account),
                                         (__bridge CFDictionaryRef)updates);
  if (updated != errSecSuccess)
    qWarning() << "Keychain update failed with OSStatus" << updated;
  return updated == errSecSuccess;
}

bool remove(const QString &service, const QString &account) {
  const OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query(service, account));
  return status == errSecSuccess || status == errSecItemNotFound;
}
} // namespace MacosKeychain
