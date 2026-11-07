// MPAboutWindowController.m
// MacPulse Native Floating About & Help Window

#import "MPAboutWindowController.h"

@implementation MPAboutWindowController

+ (instancetype)sharedController {
    static MPAboutWindowController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[MPAboutWindowController alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    NSRect contentRect = NSMakeRect(0, 0, 440, 420);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:contentRect
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"About MacPulse";
    panel.level = NSFloatingWindowLevel;
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    
    self = [super initWithWindow:panel];
    if (self) {
        panel.delegate = self;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSWindow *window = self.window;
    if (!window) return;
    
    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 440, 420)];
    window.contentView = contentView;
    
    // App Icon Branding (48x48)
    NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(24, 356, 48, 48)];
    NSImage *appIcon = [NSImage imageNamed:NSImageNameApplicationIcon];
    if (!appIcon) {
        NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        if (iconPath) {
            appIcon = [[NSImage alloc] initWithContentsOfFile:iconPath];
        }
    }
    iconView.image = appIcon;
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [contentView addSubview:iconView];
    
    // Header Branding
    NSTextField *titleLabel = [NSTextField labelWithString:@"MacPulse"];
    titleLabel.font = [NSFont boldSystemFontOfSize:18];
    titleLabel.alignment = NSTextAlignmentLeft;
    titleLabel.frame = NSMakeRect(84, 380, 336, 24);
    [contentView addSubview:titleLabel];
    
    NSTextField *subtitleLabel = [NSTextField labelWithString:@"Version 1.0.0 — Native macOS Automatic Awake Utility"];
    subtitleLabel.font = [NSFont systemFontOfSize:11];
    subtitleLabel.textColor = [NSColor secondaryLabelColor];
    subtitleLabel.alignment = NSTextAlignmentLeft;
    subtitleLabel.frame = NSMakeRect(84, 360, 336, 18);
    [contentView addSubview:subtitleLabel];
    
    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(20, 345, 400, 1)];
    separator.boxType = NSBoxSeparator;
    [contentView addSubview:separator];
    
    // Feature descriptions
    NSArray<NSDictionary<NSString *, NSString *> *> *features = @[
        @{
            @"title": @"Smart Awake",
            @"desc": @"Automatically prevents system sleep when connected to AC power, and releases assertions immediately when unplugged."
        },
        @{
            @"title": @"Timed Awake & Custom Durations",
            @"desc": @"Custom duration or quick presets (15m to 8h) with live countdown in menu bar. Automatically reverts when finished."
        },
        @{
            @"title": @"Always Awake & Battery Shield",
            @"desc": @"Keeps system awake on both AC and battery; battery cutoff automatically disengages below safety threshold (10%-80%, default 40%)."
        },
        @{
            @"title": @"Keep Display Awake",
            @"desc": @"Prevents monitor idle sleep when enabled. Automatically disengages below battery safety threshold (default 40%) to protect power."
        },
        @{
            @"title": @"Launch at Login",
            @"desc": @"Configures persistent login item registration via macOS ServiceManagement (SMAppService.mainApp)."
        }
    ];
    
    CGFloat currentY = 285.0;
    const CGFloat sectionSpacing = 56.0;
    
    for (NSDictionary<NSString *, NSString *> *feature in features) {
        NSTextField *header = [NSTextField labelWithString:feature[@"title"]];
        header.font = [NSFont boldSystemFontOfSize:12];
        header.frame = NSMakeRect(24, currentY + 18, 392, 18);
        [contentView addSubview:header];
        
        NSTextField *detail = [NSTextField labelWithString:feature[@"desc"]];
        detail.font = [NSFont systemFontOfSize:11];
        detail.textColor = [NSColor secondaryLabelColor];
        detail.maximumNumberOfLines = 2;
        detail.lineBreakMode = NSLineBreakByWordWrapping;
        detail.frame = NSMakeRect(24, currentY - 14, 392, 32);
        [contentView addSubview:detail];
        
        currentY -= sectionSpacing;
    }
    
    // Close Button
    NSButton *closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeWindow:)];
    closeButton.bezelStyle = NSBezelStyleRounded;
    closeButton.frame = NSMakeRect(336, 12, 84, 30);
    closeButton.keyEquivalent = @"\e"; // Escape key
    [contentView addSubview:closeButton];
}

- (void)showWindow:(nullable id)sender {
    [self.window center];
    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)closeWindow:(nullable id)sender {
    [self.window performClose:sender];
}

@end
