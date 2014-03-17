//
//  AppDelegate.m
//  Jeff
//
//  Created by Brandon on 2/21/2014.
//  Copyright (c) 2014 Brandon Evans. All rights reserved.
//

#import "AppDelegate.h"

#import <HockeySDK/HockeySDK.h>
#import <DropboxOSX/DropboxOSX.h>

#import "StatusItemView.h"
#import "PopoverContentViewController.h"
#import "INPopoverController.h"

NSString *const JEFClosePopoverNotification = @"JEFClosePopoverNotification";
NSString *const JEFSetStatusViewNotRecordingNotification = @"JEFSetStatusViewNotRecordingNotification";
NSString *const JEFSetStatusViewRecordingNotification = @"JEFSetStatusViewRecordingNotification";

@interface AppDelegate () <BITHockeyManagerDelegate>

@property (strong, nonatomic) StatusItemView *statusItemView;
@property (strong, nonatomic) INPopoverController *popover;
@property (strong, nonatomic) id popoverTransiencyMonitor;

@end

@implementation AppDelegate

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self setupDropbox];

    [self setupStatusItem];
    [self setupPopover];

    [[BITHockeyManager sharedHockeyManager] configureWithIdentifier:@"8937bcd0d2b85a5ebe3ae3c924af1efb" companyName:@"Brandon Evans" delegate:self];
    [[BITHockeyManager sharedHockeyManager] startManager];
    [[BITHockeyManager sharedHockeyManager].crashManager setAutoSubmitCrashReport: YES];

    __weak typeof(self) weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:JEFClosePopoverNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [weakSelf closePopover:nil];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:JEFSetStatusViewNotRecordingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [weakSelf setStatusItemActionRecord:NO];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:JEFSetStatusViewRecordingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [weakSelf setStatusItemActionRecord:YES];
    }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self closePopover:nil];
}

- (void)applicationWillResignActive:(NSNotification *)aNotification {
    [self closePopover:nil];
}

- (void)applicationWillHide:(NSNotification *)aNotification {
    [self closePopover:nil];
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
}

#pragma mark - Setup

- (void)setupDropbox {
    NSString *appKey = @"***REMOVED***";
    NSString *appSecret = @"***REMOVED***";
    NSString *root = kDBRootAppFolder;
    DBSession *session = [[DBSession alloc] initWithAppKey:appKey appSecret:appSecret root:root];
    [DBSession setSharedSession:session];

    NSAppleEventManager *eventManager = [NSAppleEventManager sharedAppleEventManager];
    [eventManager setEventHandler:self andSelector:@selector(getUrl:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)setupStatusItem {
    NSStatusItem *statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItemView = [[StatusItemView alloc] initWithStatusItem:statusItem];
    [self setStatusItemActionRecord:YES];
}

- (void)setupPopover {
    self.popover = [[INPopoverController alloc] init];
    self.popover.closesWhenApplicationBecomesInactive = YES;
    PopoverContentViewController *popoverController = [[PopoverContentViewController alloc] initWithNibName:@"PopoverContentView" bundle:nil];
    self.popover.contentViewController = popoverController;
    self.popover.animates = NO;
}

#pragma mark - Toggle popover

- (void)showPopover:(StatusItemView *)sender {
    [self.statusItemView setHighlighted:YES];
    if (self.popover.popoverIsVisible) {
        [self closePopover:nil];
        return;
    }

    [self.popover presentPopoverFromRect:sender.frame inView:sender preferredArrowDirection:INPopoverArrowDirectionUp anchorsToPositionView:YES];

    if (!self.popoverTransiencyMonitor) {
        __weak __typeof(self) weakSelf = self;
        self.popoverTransiencyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSLeftMouseDownMask|NSRightMouseDownMask handler:^(NSEvent* event) {
            [weakSelf closePopover:sender];
        }];
    }

    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}

- (void)closePopover:(id)sender {
    [self.statusItemView setHighlighted:NO];
    if (self.popoverTransiencyMonitor) {
        [NSEvent removeMonitor:self.popoverTransiencyMonitor];
        self.popoverTransiencyMonitor = nil;
        [self.popover closePopover:nil];
    }
}

- (void)setStatusItemActionRecord:(BOOL)record {
    if (record) {
        self.statusItemView.image = [NSImage imageNamed:NSImageNameRightFacingTriangleTemplate];
        self.statusItemView.alternateImage = [NSImage imageNamed:NSImageNameRightFacingTriangleTemplate];
        self.statusItemView.action = @selector(showPopover:);
    }
    else {
        self.statusItemView.image = [NSImage imageNamed:NSImageNameStopProgressTemplate];
        self.statusItemView.action = @selector(stopRecording:);
    }
}

@end
