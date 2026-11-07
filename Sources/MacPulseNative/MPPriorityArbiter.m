// MPPriorityArbiter.m
// MacPulse Native Mode Priority Arbiter & Battery Safety Cutoff Engine

#import "MPPriorityArbiter.h"
#import "MPTimedAwakeManager.h"

@implementation MPPriorityArbiter {
    BOOL _isEvaluating;
}

- (instancetype)initWithPowerManager:(MPPowerManager *)powerManager
                  powerSourceMonitor:(MPPowerSourceMonitor *)powerMonitor
                            settings:(MPAppSettings *)settings {
    self = [super init];
    if (self) {
        _powerManager = powerManager;
        _powerMonitor = powerMonitor;
        _settings = settings;
        _currentMode = MPActiveModeDisabled;
        _statusSummaryString = @"Normal Sleep Behaviour";
        _menuIconName = @"bolt.slash";
        _isBatteryCutoffActive = NO;
        _isEvaluating = NO;
        _isTimedAwakeActive = NO;
        _timedAwakeRemainingSeconds = 0;
        _timedAwakeManager = nil;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleSettingsChanged:)
                                                     name:kMPAppSettingsDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stop];
}

- (void)setTimedAwakeManager:(MPTimedAwakeManager *)timedAwakeManager {
    _timedAwakeManager = timedAwakeManager;
    if (timedAwakeManager) {
        __weak typeof(self) weakSelf = self;
        timedAwakeManager.onTick = ^(NSTimeInterval remaining) {
            [weakSelf evaluateEffectiveState];
        };
        timedAwakeManager.onCompletion = ^(BOOL expired) {
            [weakSelf evaluateEffectiveState];
        };
    }
}

- (void)handleSettingsChanged:(NSNotification *)note {
    [self evaluateEffectiveState];
}

- (void)start {
    __weak typeof(self) weakSelf = self;
    self.powerMonitor.onPowerSourceChange = ^(BOOL isAC, NSInteger percent, BOOL charging, BOOL desktop) {
        [weakSelf evaluateEffectiveState];
    };
    [self.powerMonitor startMonitoring];
    [self evaluateEffectiveState];
}

- (void)stop {
    [self.powerMonitor stopMonitoring];
}

- (void)evaluateEffectiveState {
    if (_isEvaluating) return;
    _isEvaluating = YES;

    [self.settings reloadSettings];
    
    MPActiveMode effectiveMode = MPActiveModeDisabled;
    BOOL preventSystem = NO;
    NSString *reason = nil;
    
    BOOL isAC = self.powerMonitor.isACConnected || self.powerMonitor.isDesktop;
    BOOL isPortableOnBattery = (!self.powerMonitor.isDesktop && !self.powerMonitor.isACConnected);
    NSInteger battery = self.powerMonitor.batteryPercentage;
    NSInteger threshold = self.settings.batterySafetyThreshold;
    
    // Tier 1: Always Awake (with battery protection)
    if (self.settings.alwaysAwake) {
        if (isPortableOnBattery && battery >= 0 && battery <= threshold) {
            _isBatteryCutoffActive = YES;
            self.settings.alwaysAwake = NO; // Disengage setting cleanly
            effectiveMode = MPActiveModeDisabled;
            if (self.onBatteryCutoffEngaged) {
                self.onBatteryCutoffEngaged(threshold, battery);
            }
        } else {
            _isBatteryCutoffActive = NO;
            effectiveMode = MPActiveModeAlwaysAwake;
            preventSystem = YES;
            reason = @"MacPulse: Always Awake mode enabled";
        }
    } else if (isAC || (battery > threshold)) {
        _isBatteryCutoffActive = NO;
    }
    
    // Tier 2: Timed Awake
    BOOL isTimedActive = self.isTimedAwakeActive || (self.timedAwakeManager != nil && self.timedAwakeManager.isActive);
    NSTimeInterval timedRemaining = (self.timedAwakeManager != nil && self.timedAwakeManager.isActive) ? self.timedAwakeManager.remainingSeconds : self.timedAwakeRemainingSeconds;
    
    if (effectiveMode == MPActiveModeDisabled && isTimedActive) {
        effectiveMode = MPActiveModeTimedAwake;
        preventSystem = YES;
        reason = [NSString stringWithFormat:@"MacPulse: Timed Awake session (%.0fs remaining)", timedRemaining];
    }
    
    // Tier 3: Smart Awake
    if (effectiveMode == MPActiveModeDisabled) {
        if (self.settings.keepAwakeWhileCharging && isAC) {
            effectiveMode = MPActiveModeSmartAwake;
            preventSystem = YES;
            reason = @"MacPulse: Keeping system awake while charging";
        }
    }
    
    // Tier 4: Disabled
    if (effectiveMode == MPActiveModeDisabled) {
        preventSystem = NO;
        reason = @"MacPulse: Normal sleep";
    }
    
    // Display Sleep: only prevented if system sleep is prevented AND keepDisplayAwake is YES (Display Always On)
    BOOL preventDisplay = (preventSystem && self.settings.keepDisplayAwake);
    
    _currentMode = effectiveMode;
    
    switch (effectiveMode) {
        case MPActiveModeAlwaysAwake:
            _statusSummaryString = @"Always Awake";
            _menuIconName = @"sun.max.fill";
            break;
        case MPActiveModeTimedAwake:
            _statusSummaryString = @"Timed Awake";
            _menuIconName = @"timer";
            break;
        case MPActiveModeSmartAwake:
            _statusSummaryString = @"Awake";
            _menuIconName = @"bolt.fill";
            break;
        case MPActiveModeDisabled:
        default:
            _statusSummaryString = @"Normal Sleep Behaviour";
            _menuIconName = @"bolt.slash";
            break;
    }
    
    [self.powerManager applyStateWithSystemSleepPrevented:preventSystem
                                    displaySleepPrevented:preventDisplay
                                                   reason:reason];
    
    _isEvaluating = NO;
    
    if (self.onStateChanged) {
        self.onStateChanged(self);
    }
}

@end
