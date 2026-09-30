#pragma once
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

// Read Noctalia's exported semantic colours; never modify the shell's theme.
class Theme : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantMap colors READ colors NOTIFY changed)
  Q_PROPERTY(QString fontFamily READ fontFamily NOTIFY changed)
  Q_PROPERTY(qreal radius READ radius NOTIFY changed)
  Q_PROPERTY(qreal motionScale READ motionScale NOTIFY changed)
public:
  Theme(const QString &configRoot, const QString &stateRoot,
        QObject *parent = nullptr);
  QVariantMap colors() const { return m_colors; }
  QString fontFamily() const { return m_font; }
  qreal radius() const { return m_radius; }
  qreal motionScale() const { return m_motion; }
  void reload();

  // Override the "accent" entry without re-reading the TOML. Used by the
  // macOS port to surface the system accent colour; recomputes "muted" and
  // "onAccent" so dependent bindings (foreground text on accent backgrounds,
  // selection tints) stay readable, refreshes QPalette, and emits changed()
  // when something actually moved.
  void overrideAccent(const QColor &accent);

signals:
  void changed();

private:
  void watch();
  QString m_config, m_state, m_font = "Adwaita Sans";
  QVariantMap m_colors;
  qreal m_radius = 1, m_motion = 1;
  QFileSystemWatcher m_watcher;
  QTimer m_debounce;
};
