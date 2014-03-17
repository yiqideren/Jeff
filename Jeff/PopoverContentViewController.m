//
//  PopoverContentViewController.m
//  Jeff
//
//  Created by Brandon on 2/21/2014.
//  Copyright (c) 2014 Brandon Evans. All rights reserved.
//

#import <MASPreferences/MASPreferencesWindowController.h>

#import "PopoverContentViewController.h"
#import "JEFUploaderPreferencesViewController.h"
#import "JEFAboutPreferencesViewController.h"
#import "JEFRecording.h"
#import "AppDelegate.h"
#import "JEFDepositBoxUploader.h"
#import "JEFDropboxUploader.h"
#import "Converter.h"
#import "Recorder.h"

#define kShadyWindowLevel (NSDockWindowLevel + 1000)

@interface PopoverContentViewController () <NSTableViewDelegate, DrawMouseBoxViewDelegate, NSUserNotificationCenterDelegate>

@property (strong, nonatomic) IBOutlet NSArrayController *recentRecordingsArrayController;
@property (weak, nonatomic) IBOutlet NSTableView *tableView;
@property (weak, nonatomic) IBOutlet NSButton *recordingCellShareButton;
@property (weak, nonatomic) IBOutlet NSButton *recordingCellCopyLinkButton;
@property (weak, nonatomic) IBOutlet NSTextField *recordingCellCreationDateTextField;

@property (strong, nonatomic) MASPreferencesWindowController *preferencesWindowController;
@property (strong, nonatomic) NSMutableArray *recentRecordings;
@property (strong, nonatomic) NSMutableArray *overlayWindows;

@end

@implementation PopoverContentViewController

- (void)awakeFromNib {
    [super awakeFromNib];

    self.overlayWindows = [NSMutableArray array];
    self.recentRecordings = [self loadRecentRecordings];

    [NSUserNotificationCenter defaultUserNotificationCenter].delegate = self;

    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"createdAt" ascending:YES];
    [self.recentRecordingsArrayController setSortDescriptors:@[ sortDescriptor ]];

    [self.tableView setTarget:self];
    [self.tableView setDoubleAction:@selector(didDoubleClickRow:)];

    [self.recordingCellShareButton sendActionOn:NSLeftMouseDownMask];
    [self.recordingCellCopyLinkButton sendActionOn:NSLeftMouseDownMask];

    __weak __typeof(self) weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:JEFStopRecordingNotification object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *note) {
        [weakSelf stopRecording:nil];
    }];
}

- (IBAction)showMenu:(NSButton *)sender {
    NSMenu *actionMenu = [[NSMenu alloc] initWithTitle:@""];
    [actionMenu setAutoenablesItems:YES];

    NSMenuItem *preferencesMenuItem = [[NSMenuItem alloc] initWithTitle:@"Preferences" action:@selector(showPreferencesMenu:) keyEquivalent:@""];
    [preferencesMenuItem setTarget:self];
    NSMenuItem *quitPreferencesMenuItem = [[NSMenuItem alloc] initWithTitle:@"Quit Jeff" action:@selector(quit:) keyEquivalent:@""];
    [quitPreferencesMenuItem setTarget:self];

    [actionMenu addItem:preferencesMenuItem];
    [actionMenu addItem:[NSMenuItem separatorItem]];
    [actionMenu addItem:quitPreferencesMenuItem];

    CGPoint menuPoint = CGPointMake(CGRectGetMidX(sender.frame), CGRectGetMinY(sender.frame));
    [actionMenu popUpMenuPositioningItem:nil atLocation:menuPoint inView:self.view];
}

#pragma mark - Recording

- (IBAction)recordScreen:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:JEFSetStatusViewNotRecordingNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:JEFClosePopoverNotification object:self];

    [Recorder screenRecordingWithCompletion:^(NSURL *movieURL) {
        [Converter convertMOVAtURLToGIF:movieURL completion:^(NSURL *gifURL) {
            [[NSFileManager defaultManager] removeItemAtPath:[movieURL path] error:nil];
            [self uploadGIFAtURL:gifURL];
        }];
    }];
}

- (IBAction)recordSelection:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:JEFClosePopoverNotification object:self];

    for (NSScreen *screen in [NSScreen screens]) {
        NSRect frame = [screen frame];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
        [window setBackgroundColor:[NSColor clearColor]];
        [window setOpaque:NO];
        [window setLevel:kShadyWindowLevel];
        [window setReleasedWhenClosed:NO];
        SelectionView *drawMouseBoxView = [[SelectionView alloc] initWithFrame:frame];
        drawMouseBoxView.delegate = self;
        [window setContentView:drawMouseBoxView];
        [window makeKeyAndOrderFront:self];

        [self.overlayWindows addObject:window];
    }

    [[NSCursor crosshairCursor] push];
}

- (void)stopRecording:(id)sender {
    [Recorder finishRecording];
    [[NSNotificationCenter defaultCenter] postNotificationName:JEFSetStatusViewRecordingNotification object:self];
}

#pragma mark - DrawMouseBoxViewDelegate

- (void)selectionView:(SelectionView *)view didSelectRect:(NSRect)rect {
    [[NSNotificationCenter defaultCenter] postNotificationName:JEFSetStatusViewNotRecordingNotification object:self];

    for (NSWindow *window in self.overlayWindows) {
        [window setIgnoresMouseEvents:YES];
    }

    // Map point into global coordinates.
    NSRect globalRect = rect;
    NSRect windowRect = [[view window] frame];
    globalRect = NSOffsetRect(globalRect, windowRect.origin.x, windowRect.origin.y);
    globalRect.origin.y = CGDisplayPixelsHigh(CGMainDisplayID()) - globalRect.origin.y;

    // Get a list of online displays with bounds that include the specified point.
    CGDirectDisplayID displayID = CGMainDisplayID();
    uint32_t matchingDisplayCount = 0;
    CGError error = CGGetDisplaysWithPoint(NSPointToCGPoint(globalRect.origin), 1, &displayID, &matchingDisplayCount);
    if ((error == kCGErrorSuccess) && (matchingDisplayCount == 1)) {
        [Recorder recordRect:rect display:displayID completion:^(NSURL *movieURL) {
            [self.overlayWindows makeObjectsPerformSelector:@selector(close)];
            [self.overlayWindows removeAllObjects];

            [Converter convertMOVAtURLToGIF:movieURL completion:^(NSURL *gifURL) {
                [[NSFileManager defaultManager] removeItemAtPath:[movieURL path] error:nil];
                [self uploadGIFAtURL:gifURL];
            }];
        }];
    }

    [[NSCursor currentCursor] pop];
}

#pragma mark - Uploading

- (void)uploadGIFAtURL:(NSURL *)gifURL {
    [[self uploader] uploadGIF:gifURL withName:[[gifURL path] lastPathComponent] completion:^(BOOL succeeded, NSURL *publicURL, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:[gifURL path] error:nil];

        JEFRecording *newRecording = [JEFRecording recordingWithURL:publicURL];
        [self insertObject:newRecording inRecentClipsAtIndex:[self countOfRecentClips]];
        [self saveRecentRecordings];

        [newRecording copyURLStringToPasteboard];
        [self displayPasteboardUserNotification];
    }];
}

- (id <JEFUploaderProtocol>)uploader {
    enum JEFUploaderType uploaderType = (enum JEFUploaderType)[[NSUserDefaults standardUserDefaults] integerForKey:@"selectedUploader"];
    switch (uploaderType) {
        case JEFUploaderTypeDropbox:
            return [JEFDropboxUploader uploader];
        case JEFUploaderTypeDepositBox:
        default:
            return [JEFDepositBoxUploader uploader];
    }
}

#pragma mark - Actions

- (void)showPreferencesMenu:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:JEFClosePopoverNotification object:self];
    [self.preferencesWindowController showWindow:sender];
}

- (void)quit:(id)sender {
    [NSApp terminate:self];
}

- (IBAction)showShareMenu:(id)sender {
    NSButton *button = (NSButton *)sender;
    JEFRecording *recording = [(NSTableCellView *)[button superview] objectValue];
    NSSharingServicePicker *sharePicker = [[NSSharingServicePicker alloc] initWithItems:@[ [recording.url absoluteString] ]];
    [sharePicker showRelativeToRect:button.bounds ofView:button preferredEdge:NSMinYEdge];
}

- (IBAction)copyLinkToPasteboard:(id)sender {
    NSButton *button = (NSButton *)sender;
    JEFRecording *recording = [(NSTableCellView *)[button superview] objectValue];
    [recording copyURLStringToPasteboard];
    [self displayPasteboardUserNotification];
}

#pragma mark - NSTableViewDelegate

- (void)didDoubleClickRow:(NSTableView *)sender {
    NSInteger clickedRow = [sender selectedRow];
    JEFRecording *recording = self.recentRecordings[clickedRow];
    [[NSWorkspace sharedWorkspace] openURL:recording.url];
}

#pragma mark - Properties

- (MASPreferencesWindowController *)preferencesWindowController {
    if (!_preferencesWindowController) {
        NSViewController *uploadsViewController = [[JEFUploaderPreferencesViewController alloc] initWithNibName:@"JEFUploaderPreferencesViewController" bundle:nil];
        NSViewController *aboutViewController = [[JEFAboutPreferencesViewController alloc] initWithNibName:@"JEFAboutPreferencesViewController" bundle:nil];
        NSArray *controllers = @[ uploadsViewController, [NSNull null], aboutViewController ];

        _preferencesWindowController = [[MASPreferencesWindowController alloc] initWithViewControllers:controllers title:@"Preferences"];
    }
    return _preferencesWindowController;
}

#pragma mark - Recording Persistence

- (NSMutableArray *)loadRecentRecordings {
    NSString *filePath = [self userDataFilePathForUserID:nil];
    NSMutableDictionary *userData = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
    if (!userData) {
        userData = [@{} mutableCopy];
        userData[@"recentRecordings"] = [NSKeyedArchiver archivedDataWithRootObject:[@[] mutableCopy]];
        [userData writeToFile:filePath atomically:YES];
    }
    return [NSKeyedUnarchiver unarchiveObjectWithData:userData[@"recentRecordings"]];
}

- (void)saveRecentRecordings {
    NSString *filePath = [self userDataFilePathForUserID:nil];
    NSMutableDictionary *userData = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
    userData[@"recentRecordings"] = [NSKeyedArchiver archivedDataWithRootObject:self.recentRecordings];
    [userData writeToFile:filePath atomically:YES];
}

#pragma mark - Recent Clips KVO

- (NSUInteger)countOfRecentClips {
    return [self.recentRecordings count];
}

- (void)insertObject:(JEFRecording *)recording inRecentClipsAtIndex:(NSUInteger)index {
    [self.recentRecordings insertObject:recording atIndex:index];
}

- (void)insertRecentClips:(NSArray *)array atIndexes:(NSIndexSet *)indexes {
    [self.recentRecordings insertObjects:array atIndexes:indexes];
}

- (void)removeObjectFromRecentClipsAtIndex:(NSUInteger)index {
    [self.recentRecordings removeObjectAtIndex:index];
}

- (void)removeRecentClipsAtIndexes:(NSIndexSet *)indexes {
    [self.recentRecordings removeObjectsAtIndexes:indexes];
}

#pragma mark - Saving recent recordings

- (NSString *)userDataFilePathForUserID:(NSString *)userID {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/userID"] stringByAppendingPathExtension:@"plist"];
}

#pragma mark - Private

- (void)displayPasteboardUserNotification {
    NSUserNotification *publishedNotification = [[NSUserNotification alloc] init];
    publishedNotification.title = NSLocalizedString(@"GIFSharedSuccessNotificationTitle", nil);
    publishedNotification.informativeText = NSLocalizedString(@"GIFSharedSuccessNotificationBody", nil);
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:publishedNotification];
}

#pragma mark - NSUserNotificationCenterDelegate

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification {
    return YES;
}

@end
