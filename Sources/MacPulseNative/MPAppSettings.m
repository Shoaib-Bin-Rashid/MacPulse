// MPAppSettings.m
// MacPulse Native Persistent Settings

#import "MPAppSettings.h"

NSString *const kMPAppSettingsDidChangeNotification = @"MPAppSettingsDidChangeNotification";

static NSString *const kKeepAwakeWhileChargingKey = @"keepAwakeWhileCharging";
static NSString *const kAlwaysAwakeKey = @"alwaysAwake";
static NSString *const kKeepDisplayAwakeKey = @"keepDisplayAwake";
static NSString *const kAllowDisplaySleepKey = @"allowDisplaySleep";
static NSString *const kBatterySafetyThresholdKey = @"batterySafetyThreshold";
static NSString *const kBundleIdentifier = @"com.shoaib.macpulse";

@implementation MPAppSettings {
    NSUserDefaults *_defaults;
}

+ (instancetype)sharedSettings {
    static MPAppSettings *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MPAppSettings alloc] init];
    });
    return instance;
}

- (NSUserDefaults *)userDefaults {
    if (_defaults) return _defaults;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID != nil) {
        _defaults = [NSUserDefaults standardUserDefaults];
    } else {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kBundleIdentifier] ?: [NSUserDefaults standardUserDefaults];
    }
    return _defaults;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self seedDefaultsIfNecessary];
        [self reloadSettings];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(userDefaultsDidChange:)
                                                     name:NSUserDefaultsDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)seedDefaultsIfNecessary {
    NSUserDefaults *defs = [self userDefaults];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kBundleIdentifier);
    
    if ([defs objectForKey:kKeepAwakeWhileChargingKey] == nil) {
        [defs setBool:YES forKey:kKeepAwakeWhileChargingKey];
    }
    if ([defs objectForKey:kAllowDisplaySleepKey] == nil) {
        [defs setBool:YES forKey:kAllowDisplaySleepKey];
    }
    if ([defs objectForKey:kAlwaysAwakeKey] == nil) {
        [defs setBool:NO forKey:kAlwaysAwakeKey];
    }
    if ([defs objectForKey:kBatterySafetyThresholdKey] == nil) {
        [defs setInteger:20 forKey:kBatterySafetyThresholdKey];
    }
    [defs synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kBundleIdentifier);
}

- (void)reloadSettings {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kBundleIdentifier);
    NSUserDefaults *defs = [self userDefaults];
    
    id chargingVal = [defs objectForKey:kKeepAwakeWhileChargingKey];
    _keepAwakeWhileCharging = (chargingVal != nil) ? [defs boolForKey:kKeepAwakeWhileChargingKey] : YES;
    
    id alwaysVal = [defs objectForKey:kAlwaysAwakeKey];
    _alwaysAwake = (alwaysVal != nil) ? [defs boolForKey:kAlwaysAwakeKey] : NO;
    
    if ([defs objectForKey:kKeepDisplayAwakeKey] != nil) {
        _keepDisplayAwake = [defs boolForKey:kKeepDisplayAwakeKey];
        _allowDisplaySleep = !_keepDisplayAwake;
    } else if ([defs objectForKey:kAllowDisplaySleepKey] != nil) {
        _allowDisplaySleep = [defs boolForKey:kAllowDisplaySleepKey];
        _keepDisplayAwake = !_allowDisplaySleep;
    } else {
        _keepDisplayAwake = NO;
        _allowDisplaySleep = YES;
    }
    
    id threshVal = [defs objectForKey:kBatterySafetyThresholdKey];
    NSInteger threshold = (threshVal != nil) ? [defs integerForKey:kBatterySafetyThresholdKey] : 20;
    _batterySafetyThreshold = (threshold > 0) ? threshold : 20;
}

- (void)userDefaultsDidChange:(NSNotification *)note {
    [self reloadSettings];
}

- (void)setKeepAwakeWhileCharging:(BOOL)keepAwakeWhileCharging {
    _keepAwakeWhileCharging = keepAwakeWhileCharging;
    [[self userDefaults] setBool:keepAwakeWhileCharging forKey:kKeepAwakeWhileChargingKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kBundleIdentifier);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}

- (void)setAlwaysAwake:(BOOL)alwaysAwake {
    _alwaysAwake = alwaysAwake;
    [[self userDefaults] setBool:alwaysAwake forKey:kAlwaysAwakeKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kBundleIdentifier);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}

- (void)setKeepDisplayAwake:(BOOL)keepDisplayAwake {
    _keepDisplayAwake = keepDisplayAwake;
    _allowDisplaySleep = !keepDisplayAwake;
    [[self userDefaults] setBool:keepDisplayAwake forKey:kKeepDisplayAwakeKey];
    [[self userDefaults] setBool:!keepDisplayAwake forKey:kAllowDisplaySleepKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kBundleIdentifier);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}

- (void)setAllowDisplaySleep:(BOOL)allowDisplaySleep {
    [self setKeepDisplayAwake:!allowDisplaySleep];
}

- (void)setBatterySafetyThreshold:(NSInteger)batterySafetyThreshold {
    _batterySafetyThreshold = (batterySafetyThreshold > 0) ? batterySafetyThreshold : 20;
    [[self userDefaults] setInteger:_batterySafetyThreshold forKey:kBatterySafetyThresholdKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kBundleIdentifier);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}

@end
