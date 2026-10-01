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
- (void)emitToggleMini:(id)sender;
- (void)emitBringAllToFront:(id)sender;
- (void)emitHelp:(id)sender;
- (void)emitMediumCD:(id)sender;
- (void)emitMediumVinyl:(id)sender;
- (void)emitMediumCassette:(id)sender;
- (void)emitMediumTP7:(id)sender;
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
- (void)emitToggleMini:(id)sender { if (_owner) emit _owner->toggleMini(); }
- (void)emitBringAllToFront:(id)sender { [NSApp arrangeInFront:nil]; }
- (void)emitHelp:(id)sender { if (_owner) emit _owner->helpTriggered(); }
- (void)emitMediumCD:(id)sender { if (_owner) emit _owner->setMedium("cd"); }
- (void)emitMediumVinyl:(id)sender { if (_owner) emit _owner->setMedium("vinyl"); }
- (void)emitMediumCassette:(id)sender { if (_owner) emit _owner->setMedium("cassette"); }
- (void)emitMediumTP7:(id)sender { if (_owner) emit _owner->setMedium("tp7"); }
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
    NSMenuItem *cdItem = nil;
    NSMenuItem *vinylItem = nil;
    NSMenuItem *cassetteItem = nil;
    NSMenuItem *tp7Item = nil;
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
    addSignalItem(appMenu, @"About Spun", @selector(emitAbout:), @"", NSEventModifierFlagCommand);
    addSignalItem(appMenu, @"Settings\u2026", @selector(emitSettings:), @",", NSEventModifierFlagCommand);
    [appMenu addItem:[NSMenuItem separatorItem]];
    addSignalItem(appMenu,
                  [NSString stringWithFormat:@"Hide %@", appName],
                  @selector(emitHideApp:), @"h", NSEventModifierFlagCommand);
    addSignalItem(appMenu, @"Hide Others", @selector(emitHideOthers:),
                  @"h", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addSignalItem(appMenu, @"Show All", @selector(emitShowAll:), @"", 0);
    [appMenu addItem:[NSMenuItem separatorItem]];
    addSignalItem(appMenu,
                  [NSString stringWithFormat:@"Quit %@", appName],
                  @selector(emitQuit:), @"q", NSEventModifierFlagCommand);

    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [fileItem setSubmenu:fileMenu];
    [mainMenu addItem:fileItem];
    addSignalItem(fileMenu, @"Add Music\u2026", @selector(emitAddMusic:), @"o", NSEventModifierFlagCommand);
    addSignalItem(fileMenu, @"Add Folder\u2026", @selector(emitAddFolder:),
                  @"o", NSEventModifierFlagCommand | NSEventModifierFlagShift);
    [fileMenu addItem:[NSMenuItem separatorItem]];
    addSignalItem(fileMenu, @"Close Window", @selector(emitCloseWindow:), @"w", NSEventModifierFlagCommand);

    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    [viewItem setSubmenu:viewMenu];
    [mainMenu addItem:viewItem];
    d->sidebarItem = addSignalItem(viewMenu, @"Show Sidebar",
                                   @selector(emitToggleSidebar:), @"\\", NSEventModifierFlagCommand);
    d->queueItem = addSignalItem(viewMenu, @"Show Queue",
                                 @selector(emitToggleQueue:), @"l", NSEventModifierFlagCommand);
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenu *playerMenu = [[NSMenu alloc] initWithTitle:@"Player Type"];
    NSMenuItem *playerItem = [[NSMenuItem alloc] initWithTitle:@"Player Type"
                                                          action:nil
                                                   keyEquivalent:@""];
    [playerItem setSubmenu:playerMenu];
    [viewMenu addItem:playerItem];
    d->cdItem      = addSignalItem(playerMenu, @"CD",      @selector(emitMediumCD:),      @"1", NSEventModifierFlagCommand);
    d->vinylItem   = addSignalItem(playerMenu, @"Vinyl",   @selector(emitMediumVinyl:),   @"2", NSEventModifierFlagCommand);
    d->cassetteItem= addSignalItem(playerMenu, @"Cassette",@selector(emitMediumCassette:),@"3", NSEventModifierFlagCommand);
    d->tp7Item     = addSignalItem(playerMenu, @"TP-7",    @selector(emitMediumTP7:),     @"4", NSEventModifierFlagCommand);

    NSMenu *playMenu = [[NSMenu alloc] initWithTitle:@"Playback"];
    NSMenuItem *playItem = [[NSMenuItem alloc] init];
    [playItem setSubmenu:playMenu];
    [mainMenu addItem:playItem];
    // Space is left to the QML Shortcut in Main.qml; Cmd+Space belongs to
    // Spotlight on macOS and binding it here would either be a no-op or a
    // conflict, so we leave the Play menu item without a hotkey.
    d->playPauseItem = addSignalItem(playMenu, @"Play",
                                     @selector(emitPlayPause:), @"", 0);
    addSignalItem(playMenu, @"Previous Track", @selector(emitPrevious:),
                  @"\uF702", NSEventModifierFlagCommand); // NSLeftArrow in Cocoa Unicode private area
    addSignalItem(playMenu, @"Next Track", @selector(emitNext:),
                  @"\uF703", NSEventModifierFlagCommand); // NSRightArrow
    [playMenu addItem:[NSMenuItem separatorItem]];
    d->shuffleItem = addSignalItem(playMenu, @"Shuffle",
                                   @selector(emitToggleShuffle:),
                                   @"s", NSEventModifierFlagCommand | NSEventModifierFlagShift);
    d->repeatItem = addSignalItem(playMenu, @"Repeat",
                                  @selector(emitCycleRepeat:),
                                  @"r", NSEventModifierFlagCommand | NSEventModifierFlagShift);

    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [windowItem setSubmenu:windowMenu];
    [mainMenu addItem:windowItem];
    // Cmd+M is reserved by macOS for Minimize Window. Use Cmd+Opt+M for
    // Spun's Mini Mode so users can still minimize the window normally.
    addSignalItem(windowMenu, @"Mini Mode", @selector(emitToggleMini:), @"m",
                  NSEventModifierFlagCommand | NSEventModifierFlagOption);
    [windowMenu addItem:[NSMenuItem separatorItem]];
    addSignalItem(windowMenu, @"Bring All to Front",
                  @selector(emitBringAllToFront:), @"", NSEventModifierFlagCommand);

    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *helpItem = [[NSMenuItem alloc] init];
    [helpItem setSubmenu:helpMenu];
    [mainMenu addItem:helpItem];
    addSignalItem(helpMenu, @"Spun Help", @selector(emitHelp:), @"", NSEventModifierFlagCommand);

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
    // Clear the back-pointer before `delete d` so a Cocoa target/action that
    // still holds d->actions cannot dispatch into a destroyed MacosMenuBar.
    if (d->actions) d->actions.owner = nullptr;
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

void MacosMenuBar::setMediumActive(const QString &medium) {
#ifdef Q_OS_MACOS
    auto apply = [](NSMenuItem *item, bool on) {
        if (!item) return;
        [item setState:on ? NSControlStateValueOn : NSControlStateValueOff];
    };
    apply(d->cdItem,       medium == QLatin1String("cd"));
    apply(d->vinylItem,    medium == QLatin1String("vinyl"));
    apply(d->cassetteItem, medium == QLatin1String("cassette"));
    apply(d->tp7Item,      medium == QLatin1String("tp7"));
#endif
}
