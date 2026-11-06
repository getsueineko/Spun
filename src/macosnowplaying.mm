#include "macosnowplaying.h"

#include "cider.h"
#include "mpris.h"
#include "player.h"

#include <QBuffer>
#include <QDBusObjectPath>
#include <QImage>
#include <QMetaObject>
#include <QTimer>

#import <AppKit/AppKit.h>
#import <MediaPlayer/MediaPlayer.h>

static NSString *nativeString(const QString &value)
{
    return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar *>(value.utf16())
                                         length:static_cast<NSUInteger>(value.size())];
}

struct MacosNowPlaying::Private {
    MPRemoteCommandCenter *commands = nil;
    MPMediaItemArtwork *nativeArtwork = nil;
    id playTarget = nil;
    id pauseTarget = nil;
    id toggleTarget = nil;
    id nextTarget = nil;
    id previousTarget = nil;
    id seekTarget = nil;
    QTimer *timer = nullptr;
    QString trackId;
    QString title;
    QString artist;
    QString album;
    qint64 durationMs = -1;
    qint64 artworkCacheKey = -1;
};

MacosNowPlaying::MacosNowPlaying(Player *local, Cider *cider, Player *youtube,
                                 Player *jellyfin, Player *subsonic,
                                 QObject *parent)
    : QObject(parent),
      m_adaptor(new PlayerAdaptor(local, cider, youtube, jellyfin, subsonic)),
      d(new Private)
{
    d->commands = [MPRemoteCommandCenter sharedCommandCenter];
    auto addTarget = [this](MPRemoteCommand *command, auto action) {
        id target = [command addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *) {
            QMetaObject::invokeMethod(this, action, Qt::QueuedConnection);
            return MPRemoteCommandHandlerStatusSuccess;
        }];
        return target;
    };
    d->playTarget = addTarget(d->commands.playCommand, [this] {
        m_adaptor->Play();
        refresh();
    });
    d->pauseTarget = addTarget(d->commands.pauseCommand, [this] {
        m_adaptor->Pause();
        refresh();
    });
    d->toggleTarget = addTarget(d->commands.togglePlayPauseCommand, [this] {
        m_adaptor->PlayPause();
        refresh();
    });
    d->nextTarget = addTarget(d->commands.nextTrackCommand, [this] {
        m_adaptor->Next();
        refresh();
    });
    d->previousTarget = addTarget(d->commands.previousTrackCommand, [this] {
        m_adaptor->Previous();
        refresh();
    });
    d->seekTarget = [d->commands.changePlaybackPositionCommand
        addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
            auto *position = (MPChangePlaybackPositionCommandEvent *)event;
            const double seconds = position.positionTime;
            QMetaObject::invokeMethod(this, [this, seconds] {
                if (!m_adaptor->canSeek() || seconds < 0.0)
                    return;
                const auto usec = static_cast<qlonglong>(seconds * 1000000.0);
                m_adaptor->SetPosition(QDBusObjectPath(m_adaptor->trackId()), usec);
                refresh();
            }, Qt::QueuedConnection);
            return MPRemoteCommandHandlerStatusSuccess;
        }];

    d->timer = new QTimer(this);
    d->timer->setInterval(1000);
    connect(d->timer, &QTimer::timeout, this, &MacosNowPlaying::refresh);
    d->timer->start();
    refresh();
}

MacosNowPlaying::~MacosNowPlaying()
{
    [d->commands.playCommand removeTarget:d->playTarget];
    [d->commands.pauseCommand removeTarget:d->pauseTarget];
    [d->commands.togglePlayPauseCommand removeTarget:d->toggleTarget];
    [d->commands.nextTrackCommand removeTarget:d->nextTarget];
    [d->commands.previousTrackCommand removeTarget:d->previousTarget];
    [d->commands.changePlaybackPositionCommand removeTarget:d->seekTarget];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStateStopped;
    delete m_adaptor;
    delete d;
}

void MacosNowPlaying::setSourceWindow(QObject *window)
{
    m_adaptor->setSourceWindow(window);
    refresh();
}

void MacosNowPlaying::refresh()
{
    auto *center = [MPNowPlayingInfoCenter defaultCenter];
    auto *commands = d->commands;
    const bool available = m_adaptor->canControl();

    commands.playCommand.enabled = available;
    commands.pauseCommand.enabled = available;
    commands.togglePlayPauseCommand.enabled = available;
    commands.nextTrackCommand.enabled = available && m_adaptor->canNext();
    commands.previousTrackCommand.enabled = available && m_adaptor->canPrevious();
    commands.changePlaybackPositionCommand.enabled = available && m_adaptor->canSeek();

    if (!available) {
        center.nowPlayingInfo = nil;
        center.playbackState = MPNowPlayingPlaybackStateStopped;
        d->trackId.clear();
        d->title.clear();
        d->artist.clear();
        d->album.clear();
        d->durationMs = -1;
        d->artworkCacheKey = -1;
        d->nativeArtwork = nil;
        return;
    }

    const auto metadata = m_adaptor->metadata();
    const auto trackId = metadata.value(QStringLiteral("mpris:trackid")).value<QDBusObjectPath>().path();
    const auto title = metadata.value(QStringLiteral("xesam:title")).toString();
    const auto artist = metadata.value(QStringLiteral("xesam:artist")).toStringList().join(QStringLiteral(", "));
    const auto album = metadata.value(QStringLiteral("xesam:album")).toString();
    const auto durationMs = m_adaptor->duration();
    const auto artwork = m_adaptor->artwork();
    const auto artworkKey = artwork.isNull() ? qint64(-1) : artwork.cacheKey();
    const bool itemChanged = trackId != d->trackId || title != d->title ||
        artist != d->artist || album != d->album || durationMs != d->durationMs ||
        artworkKey != d->artworkCacheKey;

    NSMutableDictionary<NSString *, id> *info = [NSMutableDictionary dictionary];
    if (!title.isEmpty())
        info[MPMediaItemPropertyTitle] = nativeString(title);
    if (!artist.isEmpty())
        info[MPMediaItemPropertyArtist] = nativeString(artist);
    if (!album.isEmpty())
        info[MPMediaItemPropertyAlbumTitle] = nativeString(album);
    if (durationMs > 0)
        info[MPMediaItemPropertyPlaybackDuration] = @(durationMs / 1000.0);

    if (artworkKey != d->artworkCacheKey) {
        d->nativeArtwork = nil;
        QByteArray png;
        QBuffer buffer(&png);
        if (!artwork.isNull() && buffer.open(QIODevice::WriteOnly) && artwork.save(&buffer, "PNG")) {
            NSData *data = [NSData dataWithBytes:png.constData() length:static_cast<NSUInteger>(png.size())];
            NSImage *image = [[NSImage alloc] initWithData:data];
            if (image) {
                const NSSize size = image.size;
                d->nativeArtwork = [[MPMediaItemArtwork alloc]
                    initWithBoundsSize:size
                    requestHandler:^NSImage *(NSSize) { return image; }];
            }
        }
    }
    if (d->nativeArtwork)
        info[MPMediaItemPropertyArtwork] = d->nativeArtwork;

    const double elapsed = m_adaptor->position() / 1000000.0;
    const bool playing = m_adaptor->status() == QStringLiteral("Playing");
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(playing ? 1.0 : 0.0);

    // Position changes every timer tick; keep the item signature so artwork
    // is decoded only when the current item actually changes.
    if (itemChanged) {
        d->trackId = trackId;
        d->title = title;
        d->artist = artist;
        d->album = album;
        d->durationMs = durationMs;
        d->artworkCacheKey = artworkKey;
    }
    center.nowPlayingInfo = info;
    center.playbackState = playing ? MPNowPlayingPlaybackStatePlaying :
        m_adaptor->status() == QStringLiteral("Paused") ? MPNowPlayingPlaybackStatePaused :
        MPNowPlayingPlaybackStateStopped;
}
