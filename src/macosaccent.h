#pragma once
#include <QColor>
#include <QObject>

class QTimer;

// macOS-only helper that surfaces the system's accent colour to QML/C++.
// On non-macOS platforms the singleton still exists but reports a default
// colour and never emits colorChanged, so callers can wire it up
// unconditionally.
class MacosAccent : public QObject {
    Q_OBJECT
public:
    explicit MacosAccent(QObject *parent = nullptr);
    ~MacosAccent() override;
    QColor color() const { return m_color; }

    // Re-read the system accent and emit colorChanged() if it differs from the
    // previous value. Safe to call from any platform; no-op where unsupported.
    void refresh();

signals:
    void colorChanged();

private:
    struct Private;
    Private *d;
    QColor m_color;
};

