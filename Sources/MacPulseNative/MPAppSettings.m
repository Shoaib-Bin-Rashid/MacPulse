// MPAppSettings.m
// MacPulse Native Persistent Settings

#import "MPAppSettings.h"
#import "MPCommon.h"

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

static MPAppSettings *s_sharedSettingsInstance = nil;

+ (instancetype)sharedSettings {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *envSuite = getenv("MACPULSE_DEFAULTS_SUITE");
        NSString *suite = envSuite ? [NSString stringWithUTF8String:envSuite] : nil;
        s_sharedSettingsInstance = [[MPAppSettings alloc] initWithSuiteName:suite];
    });
    return s_sharedSettingsInstance;
}

+ (instancetype)sharedSettingsWithSuiteName:(nullable NSString *)suiteName {
    @synchronized([MPAppSettings class]) {
        if (s_sharedSettingsInstance == nil ||
            (suiteName != nil && ![s_sharedSettingsInstance.suiteName isEqualToString:suiteName]) ||
            (suiteName == nil && s_sharedSettingsInstance.suiteName != nil)) {
            s_sharedSettingsInstance = [[MPAppSettings alloc] initWithSuiteName:suiteName];
        }
        return s_sharedSettingsInstance;
    }
}

+ (void)resetSharedInstance {
    @synchronized([MPAppSettings class]) {
        s_sharedSettingsInstance = nil;
    }
}

- (NSString *)effectiveDomainName {
    return _suiteName ?: kBundleIdentifier;
}

- (NSUserDefaults *)userDefaults {
    if (_defaults) return _defaults;
    if (_suiteName != nil) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suiteName];
    } else {
        const char *envSuite = getenv("MACPULSE_DEFAULTS_SUITE");
        if (envSuite != NULL && strlen(envSuite) > 0) {
            _suiteName = [NSString stringWithUTF8String:envSuite];
            _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suiteName];
        } else {
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            if (bundleID != nil) {
                _defaults = [NSUserDefaults standardUserDefaults];
            } else {
                _defaults = [[NSUserDefaults alloc] initWithSuiteName:kBundleIdentifier] ?: [NSUserDefaults standardUserDefaults];
            }
        }
    }
    return _defaults;
}

- (instancetype)init {
    return [self initWithSuiteName:nil];
}

- (instancetype)initWithSuiteName:(nullable NSString *)suiteName {
    self = [super init];
    if (self) {
        _suiteName = [suiteName copy];
        [self seedDefaultsIfNecessary];
        [self reloadSettings];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(userDefaultsDidChange:)
                                                     name:NSUserDefaultsDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)resetSuite {
    NSString *domain = [self effectiveDomainName];
    [[self userDefaults] removePersistentDomainForName:domain];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    [self seedDefaultsIfNecessary];
    [self reloadSettings];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)seedDefaultsIfNecessary {
    NSUserDefaults *defs = [self userDefaults];
    NSString *domain = [self effectiveDomainName];
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    
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
        [defs setInteger:kMPBatteryThresholdDefault forKey:kBatterySafetyThresholdKey];
    }
    [defs synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}

- (void)reloadSettings {
    NSString *domain = [self effectiveDomainName];
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    NSUserDefaults *defs = [self userDefaults];
    
    id chargingVal = [defs objectForKey:kKeepAwakeWhileChargingKey];
    _keepAwakeWhileCharging = (chargingVal != nil) ? [defs boolForKey:kKeepAwakeWhileChargingKey] : YES;
    
    id alwaysVal = [defs objectForKey:kAlwaysAwakeKey];
    _alwaysAwake = (alwaysVal != nil) ? [defs boolForKey:kAlwaysAwakeKey] : NO;
    
    id keepDisplayVal = [defs objectForKey:kKeepDisplayAwakeKey];
    id allowDisplayVal = [defs objectForKey:kAllowDisplaySleepKey];
    if (keepDisplayVal != nil && allowDisplayVal != nil) {
        BOOL keepDisp = [defs boolForKey:kKeepDisplayAwakeKey];
        BOOL allowDisp = [defs boolForKey:kAllowDisplaySleepKey];
        if (allowDisp == NO && keepDisp == NO) {
            // allowDisplaySleep was explicitly set to NO
            _keepDisplayAwake = YES;
            _allowDisplaySleep = NO;
        } else if (allowDisp == YES && keepDisp == YES) {
            // allowDisplaySleep was explicitly set to YES
            _keepDisplayAwake = NO;
            _allowDisplaySleep = YES;
        } else {
            _keepDisplayAwake = keepDisp;
            _allowDisplaySleep = allowDisp;
        }
    } else if (keepDisplayVal != nil) {
        _keepDisplayAwake = [defs boolForKey:kKeepDisplayAwakeKey];
        _allowDisplaySleep = !_keepDisplayAwake;
    } else if (allowDisplayVal != nil) {
        _allowDisplaySleep = [defs boolForKey:kAllowDisplaySleepKey];
        _keepDisplayAwake = !_allowDisplaySleep;
    } else {
        _keepDisplayAwake = NO;
        _allowDisplaySleep = YES;
    }
    
    id threshVal = [defs objectForKey:kBatterySafetyThresholdKey];
    if (threshVal != nil) {
        NSInteger val = [defs integerForKey:kBatterySafetyThresholdKey];
        if (val >= kMPBatteryThresholdMin && val <= kMPBatteryThresholdMax) {
            _batterySafetyThreshold = val;
        } else {
            // Persisted value corrupted or out of range: clamp to safe valid default
            _batterySafetyThreshold = kMPBatteryThresholdDefault;
        }
    } else {
        _batterySafetyThreshold = kMPBatteryThresholdDefault;
    }
}

- (void)userDefaultsDidChange:(NSNotification *)note {
    [self reloadSettings];
}

- (void)setKeepAwakeWhileCharging:(BOOL)keepAwakeWhileCharging {
    _keepAwakeWhileCharging = keepAwakeWhileCharging;
    [[self userDefaults] setBool:keepAwakeWhileCharging forKey:kKeepAwakeWhileChargingKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)[self effectiveDomainName]);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}

- (void)setAlwaysAwake:(BOOL)alwaysAwake {
    _alwaysAwake = alwaysAwake;
    [[self userDefaults] setBool:alwaysAwake forKey:kAlwaysAwakeKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)[self effectiveDomainName]);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}

- (void)setKeepDisplayAwake:(BOOL)keepDisplayAwake {
    _keepDisplayAwake = keepDisplayAwake;
    _allowDisplaySleep = !keepDisplayAwake;
    [[self userDefaults] setBool:keepDisplayAwake forKey:kKeepDisplayAwakeKey];
    [[self userDefaults] setBool:!keepDisplayAwake forKey:kAllowDisplaySleepKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)[self effectiveDomainName]);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}

- (void)setAllowDisplaySleep:(BOOL)allowDisplaySleep {
    [self setKeepDisplayAwake:!allowDisplaySleep];
}

- (void)setBatterySafetyThreshold:(NSInteger)batterySafetyThreshold {
    NSInteger clamped = batterySafetyThreshold;
    if (clamped < kMPBatteryThresholdMin) clamped = kMPBatteryThresholdMin;
    if (clamped > kMPBatteryThresholdMax) clamped = kMPBatteryThresholdMax;
    _batterySafetyThreshold = clamped;
    [[self userDefaults] setInteger:_batterySafetyThreshold forKey:kBatterySafetyThresholdKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)[self effectiveDomainName]);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}

@end
