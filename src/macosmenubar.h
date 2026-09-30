#pragma once
#include <QObject>
#include <QString>

class QWindow;

// Builds and installs the native macOS application menu bar (Spun, File,
// View, Playback, Window, Help) and re-emits each menu choice as a
// QObject signal so the QML side can drive the action through the same
// public UI methods a user click would.
//
// On non-macOS platforms the class is a no-op stub so callers can wire
// it up unconditionally.
class MacosMenuBar : public QObject {
    Q_OBJECT
public:
    explicit MacosMenuBar(QObject *parent = nullptr);
    ~MacosMenuBar() override;

    // Wire a target NSWindow so Close Window / Minimize / Zoom target the
    // correct window. Must be called once the QQuickWindow is alive.
    void attachToWindow(QWindow *window);

    // Update dynamic labels / checked state for items that mirror QML
    // state. Cheap; safe to call from QML bindings.
    Q_INVOKABLE void setPlaybackPlaying(bool playing);
    Q_INVOKABLE void setShuffleChecked(bool checked);
    Q_INVOKABLE void setRepeatChecked(bool checked);
    Q_INVOKABLE void setRepeatMode(int mode); // 0=None, 1=All, 2=One
    Q_INVOKABLE void setSidebarVisible(bool visible);
    Q_INVOKABLE void setQueueVisible(bool visible);
    // Mark which Player Type entry matches the current Player.medium.
    // Accepts: "cd" | "vinyl" | "cassette" | "tp7".
    Q_INVOKABLE void setMediumActive(const QString &medium);

signals:
    // Spun
    void aboutTriggered();
    void settingsTriggered();
    // File
    void addMusicTriggered();
    void addFolderTriggered();
    // View
    void toggleSidebar();
    void toggleQueue();
    // Window
    void toggleMini();
    // View > Player Type
    void setMedium(const QString &medium);
    // Playback
    void playPause();
    void previousTrack();
    void nextTrack();
    void toggleShuffle();
    void cycleRepeat(); // 0 -> 1 -> 2 -> 0
    // Help
    void helpTriggered();

private:
    struct Private;
    Private *d;
};
