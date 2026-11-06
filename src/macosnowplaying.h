#pragma once

#include <QObject>

class Cider;
class Player;
class PlayerAdaptor;

// Bridges Spun's shared playback controller to the macOS Now Playing center
// and system media commands. The implementation is native only on macOS.
class MacosNowPlaying : public QObject {
    Q_OBJECT
public:
    MacosNowPlaying(Player *local, Cider *cider, Player *youtube,
                    Player *jellyfin, Player *subsonic,
                    QObject *parent = nullptr);
    ~MacosNowPlaying() override;

    void setSourceWindow(QObject *window);

private slots:
    void refresh();

private:
    PlayerAdaptor *m_adaptor = nullptr;
    struct Private;
    Private *d = nullptr;
};
