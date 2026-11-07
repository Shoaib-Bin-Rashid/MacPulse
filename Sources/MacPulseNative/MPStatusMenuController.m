// MPStatusMenuController.m
// MacPulse Native Status Bar Menu Controller

#import "MPStatusMenuController.h"
#import "MPAppSettings.h"
#import "MPPowerManager.h"
#import "MPPowerSourceMonitor.h"
#import "MPPriorityArbiter.h"
#import "MPTimedAwakeManager.h"
#import "MPAboutWindowController.h"
#import <ServiceManagement/ServiceManagement.h>

// MARK: - LoginItemManager
@interface MPLoginItemManager : NSObject
@property (nonatomic, readonly) BOOL isLaunchAtLoginEnabled;
@property (nonatomic, readonly) BOOL requiresApproval;
+ (instancetype)sharedManager;
- (BOOL)toggleLaunchAtLogin;
- (void)refreshStatus;
- (void)openSystemSettings;
@end

@implementation MPLoginItemManager

+ (instancetype)sharedManager {
    static MPLoginItemManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MPLoginItemManager alloc] init];
    });
    return instance;
}

- (void)refreshStatus {
    if (@available(macOS 13.0, *)) {
        SMAppServiceStatus status = [SMAppService mainAppService].status;
        _isLaunchAtLoginEnabled = (status == SMAppServiceStatusEnabled);
        _requiresApproval = (status == SMAppServiceStatusRequiresApproval);
    } else {
        _isLaunchAtLoginEnabled = NO;
        _requiresApproval = NO;
    }
}

- (void)openSystemSettings {
    if (@available(macOS 13.0, *)) {
        [SMAppService openSystemSettingsLoginItems];
    }
}

- (BOOL)toggleLaunchAtLogin {
    if (@available(macOS 13.0, *)) {
        NSError *error = nil;
        SMAppService *service = [SMAppService mainAppService];
        if (service.status == SMAppServiceStatusEnabled) {
            [service unregisterAndReturnError:&error];
        } else {
            [service registerAndReturnError:&error];
        }
        [self refreshStatus];
        return (error == nil && !_requiresApproval);
    }
    return NO;
}

@end

// MARK: - StatusMenuController Implementation
@implementation MPStatusMenuController {
    NSStatusItem *_statusItem;
    NSMenu *_menu;
    
    MPPowerManager *_powerManager;
    MPPowerSourceMonitor *_powerMonitor;
    MPAppSettings *_settings;
    MPPriorityArbiter *_arbiter;
    MPLoginItemManager *_loginManager;
    MPTimedAwakeManager *_timedAwakeManager;
    
    NSMenuItem *_keepAwakeChargingItem;
    NSMenuItem *_timedAwakeParentItem;
    NSMenu *_timedAwakeSubmenu;
    NSMenuItem *_alwaysAwakeItem;
    NSMenuItem *_thresholdParentItem;
    NSMenuItem *_keepDisplayAwakeItem;
    NSMenuItem *_batteryWarningItem;
    NSMenuItem *_powerSourceStatusItem;
    NSMenuItem *_systemStatusItem;
    NSMenuItem *_launchAtLoginItem;
    NSMenuItem *_aboutHelpItem;
}

- (MPPriorityArbiter *)arbiter {
    return _arbiter;
}

- (MPTimedAwakeManager *)timedAwakeManager {
    return _timedAwakeManager;
}

- (void)setup {
    _powerManager = [MPPowerManager sharedManager];
    _powerMonitor = [[MPPowerSourceMonitor alloc] init];
    _settings = [MPAppSettings sharedSettings];
    _loginManager = [MPLoginItemManager sharedManager];
    _timedAwakeManager = [[MPTimedAwakeManager alloc] init];
    
    _arbiter = [[MPPriorityArbiter alloc] initWithPowerManager:_powerManager
                                            powerSourceMonitor:_powerMonitor
                                                      settings:_settings];
    _arbiter.timedAwakeManager = _timedAwakeManager;
    
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    [self buildMenu];
    _statusItem.menu = _menu;
    
    __weak typeof(self) weakSelf = self;
    _arbiter.onStateChanged = ^(MPPriorityArbiter *arbiter) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateUI];
        });
    };
    
    _arbiter.onBatteryCutoffEngaged = ^(NSInteger threshold, NSInteger batteryPercentage) {
        dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            NSUserNotification *notification = [[NSUserNotification alloc] init];
            notification.title = @"MacPulse: Battery Saver Active";
            notification.informativeText = [NSString stringWithFormat:@"Always Awake was paused because battery dropped to %ld%% (threshold: %ld%%).", (long)batteryPercentage, (long)threshold];
            notification.soundName = NSUserNotificationDefaultSoundName;
            [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
#pragma clang diagnostic pop
            [weakSelf updateUI];
        });
    };
    
    _timedAwakeManager.onTick = ^(NSTimeInterval remaining) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MPStatusMenuController *strongSelf = weakSelf;
            if (strongSelf) {
                NSStatusBarButton *button = strongSelf->_statusItem.button;
                if (button) {
                    button.title = strongSelf->_timedAwakeManager.compactTitle;
                }
            }
        });
    };
    
    _timedAwakeManager.onCompletion = ^(BOOL expired) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MPStatusMenuController *strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->_arbiter evaluateEffectiveState];
                [strongSelf updateUI];
            }
        });
    };
    
    [_arbiter start];
    [self updateUI];
}

- (void)cleanup {
    [_timedAwakeManager cancelSession];
    [_arbiter stop];
    [_powerManager releaseAllAssertions];
}

- (void)buildMenu {
    _menu = [[NSMenu alloc] initWithTitle:@"MacPulse"];
    _menu.delegate = self;
    
    // Header
    NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"MacPulse" action:nil keyEquivalent:@""];
    titleItem.enabled = NO;
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    titleItem.attributedTitle = [[NSAttributedString alloc] initWithString:@"MacPulse" attributes:attributes];
    [_menu addItem:titleItem];
    [_menu addItem:[NSMenuItem separatorItem]];
    
    // Keep Awake While Charging Toggle
    _keepAwakeChargingItem = [[NSMenuItem alloc] initWithTitle:@"Keep Awake While Charging"
                                                        action:@selector(toggleKeepAwakeWhileCharging)
                                                 keyEquivalent:@"c"];
    _keepAwakeChargingItem.target = self;
    _keepAwakeChargingItem.toolTip = @"Keep your Mac awake while connected to AC power.";
    [_menu addItem:_keepAwakeChargingItem];
    
    // Timed Awake Submenu
    _timedAwakeParentItem = [[NSMenuItem alloc] initWithTitle:@"Timed Awake" action:nil keyEquivalent:@""];
    _timedAwakeParentItem.toolTip = @"Keep your Mac awake for a set countdown duration.";
    _timedAwakeSubmenu = [[NSMenu alloc] initWithTitle:@"Timed Awake"];
    _timedAwakeParentItem.submenu = _timedAwakeSubmenu;
    [_menu addItem:_timedAwakeParentItem];
    
    // Always Awake Toggle
    _alwaysAwakeItem = [[NSMenuItem alloc] initWithTitle:@"Always Awake"
                                                  action:@selector(toggleAlwaysAwake)
                                           keyEquivalent:@"a"];
    _alwaysAwakeItem.target = self;
    _alwaysAwakeItem.toolTip = @"Keep your Mac awake continuously until battery reaches the safety threshold.";
    [_menu addItem:_alwaysAwakeItem];
    
    // Keep Display Awake Toggle (Default: OFF - screen sleeps naturally, respects battery threshold)
    _keepDisplayAwakeItem = [[NSMenuItem alloc] initWithTitle:@"Keep Display Awake"
                                                       action:@selector(toggleKeepDisplayAwake)
                                                keyEquivalent:@"d"];
    _keepDisplayAwakeItem.target = self;
    _keepDisplayAwakeItem.toolTip = @"Keep the display awake. Default is off so screen sleeps normally.";
    [_menu addItem:_keepDisplayAwakeItem];
    
    // Battery Safety Threshold Submenu (Applies to Always Awake & Keep Display Awake)
    _thresholdParentItem = [[NSMenuItem alloc] initWithTitle:@"Battery Safety Threshold" action:nil keyEquivalent:@""];
    _thresholdParentItem.toolTip = @"Battery percentage below which continuous keep-awake and display awake automatically pause.";
    NSMenu *thresholdSubmenu = [[NSMenu alloc] initWithTitle:@"Battery Safety Threshold"];
    NSArray<NSNumber *> *thresholds = @[@10, @20, @30, @40, @50, @60, @70, @80];
    for (NSNumber *num in thresholds) {
        NSString *subTitle = [NSString stringWithFormat:@"%@%%", num];
        NSMenuItem *subItem = [[NSMenuItem alloc] initWithTitle:subTitle action:@selector(selectThreshold:) keyEquivalent:@""];
        subItem.target = self;
        subItem.tag = [num integerValue];
        [thresholdSubmenu addItem:subItem];
    }
    _thresholdParentItem.submenu = thresholdSubmenu;
    [_menu addItem:_thresholdParentItem];
    
    [_menu addItem:[NSMenuItem separatorItem]];
    
    // Battery Warning Item
    _batteryWarningItem = [[NSMenuItem alloc] initWithTitle:@"⚠️ Battery Saver Active"
                                                     action:nil
                                              keyEquivalent:@""];
    _batteryWarningItem.enabled = NO;
    _batteryWarningItem.hidden = YES;
    [_menu addItem:_batteryWarningItem];
    
    // Status items
    _powerSourceStatusItem = [[NSMenuItem alloc] initWithTitle:@"Power Source: Detecting..."
                                                        action:nil
                                                 keyEquivalent:@""];
    _powerSourceStatusItem.enabled = NO;
    [_menu addItem:_powerSourceStatusItem];
    
    _systemStatusItem = [[NSMenuItem alloc] initWithTitle:@"System Status: Normal Sleep"
                                                   action:nil
                                            keyEquivalent:@""];
    _systemStatusItem.enabled = NO;
    [_menu addItem:_systemStatusItem];
    
    [_menu addItem:[NSMenuItem separatorItem]];
    
    // Launch at login
    _launchAtLoginItem = [[NSMenuItem alloc] initWithTitle:@"Launch at Login"
                                                    action:@selector(toggleLaunchAtLogin)
                                             keyEquivalent:@"l"];
    _launchAtLoginItem.target = self;
    _launchAtLoginItem.toolTip = @"Automatically start MacPulse in the menu bar when you log in to macOS.";
    [_menu addItem:_launchAtLoginItem];
    
    [_menu addItem:[NSMenuItem separatorItem]];
    
    // About & Help
    _aboutHelpItem = [[NSMenuItem alloc] initWithTitle:@"About & Help..."
                                                action:@selector(showAboutHelp)
                                         keyEquivalent:@""];
    _aboutHelpItem.target = self;
    _aboutHelpItem.toolTip = @"View MacPulse features, controls, version, and documentation.";
    [_menu addItem:_aboutHelpItem];
    
    [_menu addItem:[NSMenuItem separatorItem]];
    
    // Quit
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit MacPulse"
                                                      action:@selector(quitApp)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    quitItem.toolTip = @"Quit MacPulse and release all sleep assertions.";
    [_menu addItem:quitItem];
    
    [self updateTimedAwakeSubmenu];
}

- (void)updateTimedAwakeSubmenu {
    [_timedAwakeSubmenu removeAllItems];
    
    if (_timedAwakeManager.isActive) {
        NSString *remainingTitle = [NSString stringWithFormat:@"Time Remaining: %@", _timedAwakeManager.formattedRemainingTime];
        NSMenuItem *remainingItem = [[NSMenuItem alloc] initWithTitle:remainingTitle action:nil keyEquivalent:@""];
        remainingItem.enabled = NO;
        [_timedAwakeSubmenu addItem:remainingItem];
        
        NSMenuItem *cancelItem = [[NSMenuItem alloc] initWithTitle:@"Cancel Timed Session"
                                                            action:@selector(cancelTimedSession)
                                                     keyEquivalent:@""];
        cancelItem.target = self;
        [_timedAwakeSubmenu addItem:cancelItem];
        
        [_timedAwakeSubmenu addItem:[NSMenuItem separatorItem]];
    }
    
    // Custom duration action item
    NSString *customTitle = @"Custom Duration...";
    BOOL isCustomActive = NO;
    if (_timedAwakeManager.isActive) {
        NSInteger currentMins = (NSInteger)round(_timedAwakeManager.initialDuration / 60.0);
        BOOL matchesPreset = (currentMins == 15 || currentMins == 30 || currentMins == 45 ||
                              currentMins == 60 || currentMins == 120 || currentMins == 240 || currentMins == 480);
        if (!matchesPreset) {
            isCustomActive = YES;
            customTitle = [NSString stringWithFormat:@"Custom Duration... (%ldm Active)", (long)currentMins];
        }
    }
    NSMenuItem *customItem = [[NSMenuItem alloc] initWithTitle:customTitle
                                                        action:@selector(promptCustomDuration)
                                                 keyEquivalent:@""];
    customItem.target = self;
    customItem.state = isCustomActive ? NSControlStateValueOn : NSControlStateValueOff;
    [_timedAwakeSubmenu addItem:customItem];
    
    [_timedAwakeSubmenu addItem:[NSMenuItem separatorItem]];
    
    NSArray<NSDictionary *> *presets = @[
        @{ @"title": @"15 Minutes", @"duration": @(900.0) },
        @{ @"title": @"30 Minutes", @"duration": @(kMPTimedAwakeDuration30Min) },
        @{ @"title": @"45 Minutes", @"duration": @(2700.0) },
        @{ @"title": @"1 Hour",     @"duration": @(kMPTimedAwakeDuration1Hour) },
        @{ @"title": @"2 Hours",    @"duration": @(kMPTimedAwakeDuration2Hours) },
        @{ @"title": @"4 Hours",    @"duration": @(14400.0) },
        @{ @"title": @"8 Hours",    @"duration": @(28800.0) }
    ];
    
    for (NSDictionary *preset in presets) {
        NSString *title = preset[@"title"];
        NSTimeInterval dur = [preset[@"duration"] doubleValue];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(selectTimedPreset:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)dur;
        if (_timedAwakeManager.isActive && (NSInteger)_timedAwakeManager.initialDuration == (NSInteger)dur) {
            item.state = NSControlStateValueOn;
        } else {
            item.state = NSControlStateValueOff;
        }
        [_timedAwakeSubmenu addItem:item];
    }
}

- (void)promptCustomDuration {
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
    }
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Custom Timed Awake Duration";
    alert.informativeText = @"Enter keep-awake duration in minutes (e.g. 15, 45, 90, 180):";
    [alert addButtonWithTitle:@"Start Session"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField *inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    NSInteger defaultMins = 45;
    if (_timedAwakeManager.isActive && _timedAwakeManager.initialDuration > 0) {
        defaultMins = (NSInteger)round(_timedAwakeManager.initialDuration / 60.0);
    }
    inputField.stringValue = [NSString stringWithFormat:@"%ld", (long)defaultMins];
    inputField.placeholderString = @"Minutes (e.g. 45)";
    alert.accessoryView = inputField;
    
    [alert.window setInitialFirstResponder:inputField];
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSString *trimmed = [inputField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSInteger minutes = [trimmed integerValue];
        if (minutes > 0 && minutes <= 10080) { // Up to 7 days
            NSTimeInterval duration = (NSTimeInterval)(minutes * 60.0);
            [_timedAwakeManager startSessionWithDuration:duration];
            [_arbiter evaluateEffectiveState];
            [self updateUI];
        } else {
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.alertStyle = NSAlertStyleWarning;
            errorAlert.messageText = @"Invalid Duration";
            errorAlert.informativeText = @"Please enter a valid duration between 1 and 10080 minutes.";
            [errorAlert runModal];
        }
    }
}

- (void)updateUI {
    NSStatusBarButton *button = _statusItem.button;
    if (!button) return;
    
    BOOL isAwake = _powerManager.isSystemSleepPrevented;
    BOOL isAC = _powerMonitor.isACConnected || _powerMonitor.isDesktop;
    
    // Icon selection from Arbiter
    NSImage *image = [NSImage imageWithSystemSymbolName:_arbiter.menuIconName
                                accessibilityDescription:_arbiter.statusSummaryString];
    image.template = YES;
    button.image = image;
    
    // Status Bar Countdown Title
    if (_timedAwakeManager.isActive) {
        button.title = _timedAwakeManager.compactTitle;
    } else {
        button.title = @"";
    }
    
    // Toggles state
    _keepAwakeChargingItem.state = _settings.keepAwakeWhileCharging ? NSControlStateValueOn : NSControlStateValueOff;
    _timedAwakeParentItem.state = _timedAwakeManager.isActive ? NSControlStateValueOn : NSControlStateValueOff;
    _alwaysAwakeItem.state = _settings.alwaysAwake ? NSControlStateValueOn : NSControlStateValueOff;
    _keepDisplayAwakeItem.state = _settings.keepDisplayAwake ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Update threshold submenu item checkmarks
    NSInteger currentThreshold = _settings.batterySafetyThreshold;
    for (NSMenuItem *item in _thresholdParentItem.submenu.itemArray) {
        item.state = (item.tag == currentThreshold) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    
    // Update Timed Awake Submenu items
    [self updateTimedAwakeSubmenu];
    
    // Update battery warning item
    if (_arbiter.isBatteryCutoffActive) {
        _batteryWarningItem.hidden = NO;
        _batteryWarningItem.title = [NSString stringWithFormat:@"⚠️ Battery Saver Active (Battery < %ld%%)", (long)_settings.batterySafetyThreshold];
    } else {
        _batteryWarningItem.hidden = YES;
    }
    
    // Status labels
    NSString *percentStr = (_powerMonitor.batteryPercentage >= 0) ?
        [NSString stringWithFormat:@" (%ld%%)", (long)_powerMonitor.batteryPercentage] : @"";
    _powerSourceStatusItem.title = [NSString stringWithFormat:@"Power Source: %@%@", isAC ? @"AC Power" : @"Battery", percentStr];
    
    if (isAwake) {
        NSString *summary = _arbiter.statusSummaryString;
        if ([summary isEqualToString:@"Awake"]) {
            _systemStatusItem.title = @"System Status: Awake";
        } else {
            _systemStatusItem.title = [NSString stringWithFormat:@"System Status: Awake (%@)", summary];
        }
    } else {
        if (_arbiter.isBatteryCutoffActive) {
            _systemStatusItem.title = [NSString stringWithFormat:@"System Status: Battery Saver Paused (<%ld%%)", (long)_settings.batterySafetyThreshold];
        } else {
            _systemStatusItem.title = @"System Status: Normal Sleep";
        }
    }
    
    // Login item state reflects cached status (refreshed in menuWillOpen)
    _launchAtLoginItem.state = _loginManager.isLaunchAtLoginEnabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleKeepAwakeWhileCharging {
    _settings.keepAwakeWhileCharging = !_settings.keepAwakeWhileCharging;
    [_arbiter evaluateEffectiveState];
}

- (void)toggleAlwaysAwake {
    _settings.alwaysAwake = !_settings.alwaysAwake;
    [_arbiter evaluateEffectiveState];
}

- (void)toggleKeepDisplayAwake {
    _settings.keepDisplayAwake = !_settings.keepDisplayAwake;
    [_arbiter evaluateEffectiveState];
}

- (void)toggleDisplayAlwaysOn {
    [self toggleKeepDisplayAwake];
}

- (void)toggleAllowDisplaySleep {
    [self toggleKeepDisplayAwake];
}

- (void)selectThreshold:(NSMenuItem *)sender {
    _settings.batterySafetyThreshold = sender.tag;
    [_arbiter evaluateEffectiveState];
    [self updateUI];
}

- (void)selectTimedPreset:(NSMenuItem *)sender {
    NSTimeInterval duration = (NSTimeInterval)sender.tag;
    [_timedAwakeManager startSessionWithDuration:duration];
    [_arbiter evaluateEffectiveState];
    [self updateUI];
}

- (void)cancelTimedSession {
    [_timedAwakeManager cancelSession];
    [_arbiter evaluateEffectiveState];
    [self updateUI];
}

- (void)showAboutHelp {
    [[MPAboutWindowController sharedController] showWindow:nil];
}

- (void)toggleLaunchAtLogin {
    [_loginManager toggleLaunchAtLogin];
    if (_loginManager.requiresApproval) {
        if (@available(macOS 14.0, *)) {
            [NSApp activate];
        } else {
            [NSApp activateIgnoringOtherApps:YES];
        }
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Login Item Requires Approval";
        alert.informativeText = @"MacPulse is currently disabled in macOS System Settings > Login Items.\n\nPlease enable MacPulse in System Settings to allow Launch at Login.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"Open System Settings"];
        [alert addButtonWithTitle:@"Cancel"];
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            [_loginManager openSystemSettings];
        }
    }
    [_loginManager refreshStatus];
    [self updateUI];
}

- (void)quitApp {
    [self cleanup];
    [NSApp terminate:nil];
}

- (void)menuWillOpen:(NSMenu *)menu {
    [_powerMonitor refreshPowerSourceStatus];
    [_loginManager refreshStatus];
    [_arbiter evaluateEffectiveState];
    [self updateUI];
}

@end
