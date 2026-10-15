#pragma once
#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QSettings>
#include <QTimer>
#include <QVariantMap>

// Read Noctalia's exported semantic colours; never modify the shell's theme.
//
// On top of the file-driven palette, Theme exposes a Mode that lets the user
// pin the application appearance to the OS setting, to a forced light palette
// or to a forced dark palette. Light/Dark mode is implemented as an internal
// override layered on top of whatever the CSS / TOML files export: System
// mode keeps using the live file (Noctalia on Linux, the macOS appearance
// observer wired up by main.cpp), while Light/Dark always render from the
// baked-in light/dark palette so the choice survives restarts and ignores
// file changes. The QSettings key lives in the same player.ini the rest of
// the application uses.
class Theme : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantMap colors READ colors NOTIFY changed)
  Q_PROPERTY(QString fontFamily READ fontFamily NOTIFY changed)
  Q_PROPERTY(qreal radius READ radius NOTIFY changed)
  Q_PROPERTY(qreal motionScale READ motionScale NOTIFY changed)
  // System = follow the OS / Noctalia export. Light / Dark force a baked-in
  // palette regardless of what the live source reports.
  Q_PROPERTY(Mode mode READ mode WRITE setMode NOTIFY modeChanged)
public:
  // Keep the values stable: they round-trip through QSettings as integers so
  // reordering would silently flip the user choice on existing installs.
  enum Mode { System = 0, Light = 1, Dark = 2 };
  Q_ENUM(Mode)

  Theme(const QString &configRoot, const QString &stateRoot,
        const QString &settingsPath, QObject *parent = nullptr);
  QVariantMap colors() const { return m_colors; }
  QString fontFamily() const { return m_font; }
  qreal radius() const { return m_radius; }
  qreal motionScale() const { return m_motion; }
  Mode mode() const { return m_mode; }
  void setMode(Mode mode);
  void reload();

  // Override the "accent" entry without re-reading the TOML. Used by the
  // macOS port to surface the system accent colour; recomputes "muted" and
  // "onAccent" so dependent bindings (foreground text on accent backgrounds,
  // selection tints) stay readable, refreshes QPalette, and emits changed()
  // when something actually moved.
  void overrideAccent(const QColor &accent);

  // Feed in the OS-resolved light/dark state when running in System mode.
  // main.cpp wires MacosAppearance to this on macOS so the application
  // reacts to AppleInterfaceThemeChangedNotification without coupling Theme
  // to Objective-C++.
  void setSystemResolvedDark(bool dark);

signals:
  void changed();
  void modeChanged();

private:
  void watch();
  void applyOverrideAccent(const QColor &accent, bool emitSignal);
  void applyPalette(const QVariantMap &colors, bool emitSignal);
  // Compute a fresh palette from the current Mode: System resolves against
  // the last CSS-driven m_baseColors; Light / Dark return the baked-in sets.
  QVariantMap resolveModeColors() const;
  static QVariantMap bakedLightColors();
  static QVariantMap bakedDarkColors();

  QString m_config, m_state, m_font = "Adwaita Sans";
  QSettings m_settings;
  Mode m_mode = System;
  // The last palette loaded from the CSS / TOML source. Kept around so that
  // switching back to System does not require re-reading the file and so
  // System-mode updates from the OS observer can be layered on top without
  // throwing away the user's accent override.
  QVariantMap m_baseColors;
  QVariantMap m_colors;
  // Last accent set via overrideAccent(). Stored separately from m_colors so
  // a later reload() (triggered by a TOML/CSS change) can re-apply it
  // instead of clobbering it with whatever Noctalia exports.
  QColor m_accentOverride;
  // In System mode, whether the OS currently reports a dark appearance. The
  // Light/Dark forced palettes ignore this; it only affects which of two
  // baked choices System mode resolves to.
  bool m_systemResolvedDark = true;
  qreal m_radius = 1, m_motion = 1;
  QFileSystemWatcher m_watcher;
  QTimer m_debounce;
};
