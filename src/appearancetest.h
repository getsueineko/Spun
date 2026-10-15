#pragma once

#include <QQuickWindow>
#include <QString>

// Exercise the System / Light / Dark theme selector end-to-end:
//   - default mode for a fresh settings file is System
//   - mode persists across reload (simulated by re-reading QSettings)
//   - invalid / missing stored values fall back to System
//   - Light / Dark produce visibly different palettes (surface + text contrast)
//   - System mode reacts to a setSystemResolvedDark override
//   - the QML preferences selector reflects the stored choice on load
int exerciseAppearance(QQuickWindow *window, const QString &temp,
                       const QString &captures);
