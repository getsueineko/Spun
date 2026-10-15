#pragma once
#include <QColor>
#include <QObject>

class QTimer;

// macOS-only helper that exposes the system appearance to QML/C++. The mode
// matches Theme::Mode values (System = 0, Light = 1, Dark = 2) so QML can
// index straight into the Spun Preferences segmented control without
// string conversion. On non-macOS platforms the singleton still exists but
// never emits modeChanged and reports System so the rest of the wiring stays
// platform-neutral.
class MacosAppearance : public QObject {
    Q_OBJECT
    Q_PROPERTY(Mode mode READ mode NOTIFY modeChanged)
public:
    enum Mode { System = 0, Light = 1, Dark = 2 };
    Q_ENUM(Mode)

    explicit MacosAppearance(QObject *parent = nullptr);
    ~MacosAppearance() override;
    Mode mode() const { return m_mode; }

    // Re-read NSApp.effectiveAppearance and emit modeChanged() if the
    // resolved light/dark state flipped. Safe to call from any platform;
    // no-op where unsupported.
    void refresh();

signals:
    void modeChanged();

private:
    struct Private;
    Private *d;
    Mode m_mode = System;
};
