#include "macosmenubar.h"

#include <QWindow>

#ifdef Q_OS_MACOS
#import <Cocoa/Cocoa.h>

// Cocoa target/action needs an Objective-C object as the target and a real
// selector; Qt's QObject is not an NSObject subclass and its meta-object
// methods are not reachable through performSelector:. This proxy holds a
// back-pointer to the MacosMenuBar and exposes one Obj-C method per menu
// choice; each method emits the corresponding Qt signal on the main
// thread.
@interface SpunMenuActions : NSObject
@property (nonatomic, assign) MacosMenuBar *owner;
- (void)emitAbout:(id)sender;
- (void)emitSettings:(id)sender;
- (void)emitHideApp:(id)sender;
- (void)emitHideOthers:(id)sender;
- (void)emitShowAll:(id)sender;
- (void)emitQuit:(id)sender;
- (void)emitAddMusic:(id)sender;
- (void)emitAddFolder:(id)sender;
- (void)emitCloseWindow:(id)sender;
- (void)emitToggleSidebar:(id)sender;
- (void)emitToggleQueue:(id)sender;
- (void)emitPlayPause:(id)sender;
- (void)emitPrevious:(id)sender;
- (void)emitNext:(id)sender;
- (void)emitToggleShuffle:(id)sender;
- (void)emitCycleRepeat:(id)sender;
- (void)emitMinimize:(id)sender;
- (void)emitZoom:(id)sender;
- (void)emitBringAllToFront:(id)sender;
- (void)emitHelp:(id)sender;
@end

@implementation SpunMenuActions
- (void)emitAbout:(id)sender { if (_owner) emit _owner->aboutTriggered(); }
- (void)emitSettings:(id)sender { if (_owner) emit _owner->settingsTriggered(); }
- (void)emitHideApp:(id)sender { [NSApp hide:nil]; }
- (void)emitHideOthers:(id)sender { [NSApp hideOtherApplications:nil]; }
- (void)emitShowAll:(id)sender { [NSApp unhideAllApplications:nil]; }
- (void)emitQuit:(id)sender { [NSApp terminate:nil]; }
- (void)emitAddMusic:(id)sender { if (_owner) emit _owner->addMusicTriggered(); }
- (void)emitAddFolder:(id)sender { if (_owner) emit _owner->addFolderTriggered(); }
- (void)emitCloseWindow:(id)sender { [[NSApp keyWindow] performClose:nil]; }
- (void)emitToggleSidebar:(id)sender { if (_owner) emit _owner->toggleSidebar(); }
- (void)emitToggleQueue:(id)sender { if (_owner) emit _owner->toggleQueue(); }
- (void)emitPlayPause:(id)sender { if (_owner) emit _owner->playPause(); }
- (void)emitPrevious:(id)sender { if (_owner) emit _owner->previousTrack(); }
- (void)emitNext:(id)sender { if (_owner) emit _owner->nextTrack(); }
- (void)emitToggleShuffle:(id)sender { if (_owner) emit _owner->toggleShuffle(); }
- (void)emitCycleRepeat:(id)sender { if (_owner) emit _owner->cycleRepeat(); }
- (void)emitMinimize:(id)sender { [[NSApp keyWindow] performMiniaturize:nil]; }
- (void)emitZoom:(id)sender { [[NSApp keyWindow] performZoom:nil]; }
- (void)emitBringAllToFront:(id)sender { [NSApp arrangeInFront:nil]; }
- (void)emitHelp:(id)sender { if (_owner) emit _owner->helpTriggered(); }
@end

// Synthesize the [NSApp hide:nil] / terminate: helpers above do not need
// bridging, they are direct Obj-C messages.
#endif

struct MacosMenuBar::Private {
#ifdef Q_OS_MACOS
    SpunMenuActions *actions = nil;
    NSMenuItem *playPauseItem = nil;
    NSMenuItem *shuffleItem = nil;
    NSMenuItem *repeatItem = nil;
    NSMenuItem *sidebarItem = nil;
    NSMenuItem *queueItem = nil;
#endif
};

MacosMenuBar::MacosMenuBar(QObject *parent) : QObject(parent), d(new Private) {
#ifdef Q_OS_MACOS
    d->actions = [[SpunMenuActions alloc] init];
    d->actions.owner = this;

    NSMenu *mainMenu = [[NSMenu alloc] init];

    auto addSignalItem = ^(NSMenu *menu, NSString *title, SEL action,
                           NSString *key, NSEventModifierFlags mask) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:action
                                               keyEquivalent:key];
        [item setTarget:d->actions];
        if (key.length > 0) [item setKeyEquivalentModifierMask:mask];
        [menu addItem:item];
        return item;
    };

    NSMenu *appMenu = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];
    NSString *appName = [[NSProcessInfo processInfo] processName];
    addSignalItem(appMenu, @"About Spun", @selector(emitAbout:), @"", NSCommandKeyMask);
    addSignalItem(appMenu, @"Settings\u2026", @selector(emitSettings:), @",", NSCommandKeyMask);
    [appMenu addItem:[NSMenuItem separatorItem]];
    addSignalItem(appMenu,
                  [NSString stringWithFormat:@"Hide %@", appName],
                  @selector(emitHideApp:), @"h", NSCommandKeyMask);
    addSignalItem(appMenu, @"Hide Others", @selector(emitHideOthers:), @"h", NSCommandKeyMask);
    addSignalItem(appMenu, @"Show All", @selector(emitShowAll:), @"",
                  NSCommandKeyMask | NSAlternateKeyMask);
    [appMenu addItem:[NSMenuItem separatorItem]];
    addSignalItem(appMenu,
                  [NSString stringWithFormat:@"Quit %@", appName],
                  @selector(emitQuit:), @"q", NSCommandKeyMask);

    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [fileItem setSubmenu:fileMenu];
    [mainMenu addItem:fileItem];
    addSignalItem(fileMenu, @"Add Music\u2026", @selector(emitAddMusic:), @"o", NSCommandKeyMask);
    addSignalItem(fileMenu, @"Add Folder\u2026", @selector(emitAddFolder:),
                  @"o", NSCommandKeyMask | NSShiftKeyMask);
    [fileMenu addItem:[NSMenuItem separatorItem]];
    addSignalItem(fileMenu, @"Close Window", @selector(emitCloseWindow:), @"w", NSCommandKeyMask);

    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    [viewItem setSubmenu:viewMenu];
    [mainMenu addItem:viewItem];
    d->sidebarItem = addSignalItem(viewMenu, @"Show Sidebar",
                                   @selector(emitToggleSidebar:), @"\\", NSCommandKeyMask);
    d->queueItem = addSignalItem(viewMenu, @"Show Queue",
                                 @selector(emitToggleQueue:), @"l", NSCommandKeyMask);

    NSMenu *playMenu = [[NSMenu alloc] initWithTitle:@"Playback"];
    NSMenuItem *playItem = [[NSMenuItem alloc] init];
    [playItem setSubmenu:playMenu];
    [mainMenu addItem:playItem];
    d->playPauseItem = addSignalItem(playMenu, @"Play",
                                     @selector(emitPlayPause:), @" ", NSCommandKeyMask);
    addSignalItem(playMenu, @"Previous Track", @selector(emitPrevious:),
                  @"", 0);
    addSignalItem(playMenu, @"Next Track", @selector(emitNext:), @"", 0);
    [playMenu addItem:[NSMenuItem separatorItem]];
    d->shuffleItem = addSignalItem(playMenu, @"Shuffle",
                                   @selector(emitToggleShuffle:),
                                   @"s", NSCommandKeyMask | NSShiftKeyMask);
    d->repeatItem = addSignalItem(playMenu, @"Repeat",
                                  @selector(emitCycleRepeat:),
                                  @"r", NSCommandKeyMask | NSShiftKeyMask);

    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [windowItem setSubmenu:windowMenu];
    [mainMenu addItem:windowItem];
    addSignalItem(windowMenu, @"Minimize", @selector(emitMinimize:), @"m", NSCommandKeyMask);
    addSignalItem(windowMenu, @"Zoom", @selector(emitZoom:), @"", NSCommandKeyMask);
    [windowMenu addItem:[NSMenuItem separatorItem]];
    addSignalItem(windowMenu, @"Bring All to Front",
                  @selector(emitBringAllToFront:), @"", NSCommandKeyMask);

    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *helpItem = [[NSMenuItem alloc] init];
    [helpItem setSubmenu:helpMenu];
    [mainMenu addItem:helpItem];
    addSignalItem(helpMenu, @"Spun Help", @selector(emitHelp:), @"", NSCommandKeyMask);

    [NSApp setMainMenu:mainMenu];
    [NSApp setWindowsMenu:windowMenu];
    [NSApp setHelpMenu:helpMenu];
#endif
}

MacosMenuBar::~MacosMenuBar() {
#ifdef Q_OS_MACOS
    [NSApp setMainMenu:nil];
    [NSApp setWindowsMenu:nil];
    [NSApp setHelpMenu:nil];
#endif
    delete d;
}

void MacosMenuBar::attachToWindow(QWindow *window) {
    Q_UNUSED(window);
}

void MacosMenuBar::setPlaybackPlaying(bool playing) {
#ifdef Q_OS_MACOS
    if (!d->playPauseItem) return;
    [d->playPauseItem setTitle:playing ? @"Pause" : @"Play"];
#endif
}

void MacosMenuBar::setShuffleChecked(bool checked) {
#ifdef Q_OS_MACOS
    if (!d->shuffleItem) return;
    [d->shuffleItem setState:checked ? NSControlStateValueOn
                                     : NSControlStateValueOff];
#endif
}

void MacosMenuBar::setRepeatChecked(bool checked) {
#ifdef Q_OS_MACOS
    if (!d->repeatItem) return;
    [d->repeatItem setState:checked ? NSControlStateValueOn
                                    : NSControlStateValueOff];
#endif
}

void MacosMenuBar::setRepeatMode(int mode) {
#ifdef Q_OS_MACOS
    if (!d->repeatItem) return;
    NSString *label = @"Repeat";
    switch (mode) {
        case 1: label = @"Repeat All"; break;
        case 2: label = @"Repeat One"; break;
        default: label = @"Repeat"; break;
    }
    [d->repeatItem setTitle:label];
    [d->repeatItem setState:mode != 0 ? NSControlStateValueOn
                                     : NSControlStateValueOff];
#endif
}

void MacosMenuBar::setSidebarVisible(bool visible) {
#ifdef Q_OS_MACOS
    if (!d->sidebarItem) return;
    [d->sidebarItem setTitle:visible ? @"Hide Sidebar" : @"Show Sidebar"];
    [d->sidebarItem setState:visible ? NSControlStateValueOn
                                     : NSControlStateValueOff];
#endif
}

void MacosMenuBar::setQueueVisible(bool visible) {
#ifdef Q_OS_MACOS
    if (!d->queueItem) return;
    [d->queueItem setTitle:visible ? @"Hide Queue" : @"Show Queue"];
    [d->queueItem setState:visible ? NSControlStateValueOn
                                   : NSControlStateValueOff];
#endif
}
