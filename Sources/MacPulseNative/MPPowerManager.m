// MPPowerManager.m
// MacPulse Native Dual Power Assertion Manager

#import "MPPowerManager.h"
#import <os/lock.h>
#import <os/log.h>

@implementation MPPowerManager {
    IOPMAssertionID _systemAssertionID;
    IOPMAssertionID _displayAssertionID;
    os_unfair_lock _lock;
}

+ (instancetype)sharedManager {
    static MPPowerManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MPPowerManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _systemAssertionID = kIOPMNullAssertionID;
        _displayAssertionID = kIOPMNullAssertionID;
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (void)dealloc {
    [self releaseAllAssertions];
}

- (BOOL)isSystemSleepPrevented {
    os_unfair_lock_lock(&_lock);
    BOOL active = (_systemAssertionID != kIOPMNullAssertionID);
    os_unfair_lock_unlock(&_lock);
    return active;
}

- (BOOL)isDisplaySleepPrevented {
    os_unfair_lock_lock(&_lock);
    BOOL active = (_displayAssertionID != kIOPMNullAssertionID);
    os_unfair_lock_unlock(&_lock);
    return active;
}

- (BOOL)isAssertionActive {
    return [self isSystemSleepPrevented];
}

- (void)getSystemSleepPrevented:(nullable BOOL *)outSystem displaySleepPrevented:(nullable BOOL *)outDisplay {
    os_unfair_lock_lock(&_lock);
    if (outSystem) *outSystem = (_systemAssertionID != kIOPMNullAssertionID);
    if (outDisplay) *outDisplay = (_displayAssertionID != kIOPMNullAssertionID);
    os_unfair_lock_unlock(&_lock);
}

- (BOOL)createPreventSystemSleepAssertionWithReason:(nullable NSString *)reason {
    os_unfair_lock_lock(&_lock);
    BOOL currentDisplay = (_displayAssertionID != kIOPMNullAssertionID);
    os_unfair_lock_unlock(&_lock);
    return [self applyStateWithSystemSleepPrevented:YES
                             displaySleepPrevented:currentDisplay
                                            reason:reason];
}

- (BOOL)releaseAssertion {
    return [self applyStateWithSystemSleepPrevented:NO
                             displaySleepPrevented:NO
                                            reason:nil];
}

- (BOOL)applyStateWithSystemSleepPrevented:(BOOL)preventSystem
                    displaySleepPrevented:(BOOL)preventDisplay
                                   reason:(nullable NSString *)reason {
    os_unfair_lock_lock(&_lock);
    
    NSString *safeReason = (reason && reason.length > 0) ? reason : @"MacPulse: Keeping system awake";
    CFStringRef reasonCF = (__bridge CFStringRef)safeReason;
    BOOL allSucceeded = YES;
    
    // 1. Invariant protection: If display sleep is not prevented, release display assertion BEFORE touching system assertion
    BOOL effectivePreventDisplay = preventSystem && preventDisplay;
    if (!effectivePreventDisplay) {
        if (_displayAssertionID != kIOPMNullAssertionID) {
            IOPMAssertionID targetID = _displayAssertionID;
            _displayAssertionID = kIOPMNullAssertionID;
            IOReturn ret = IOPMAssertionRelease(targetID);
            if (ret != kIOReturnSuccess) {
                os_log_error(OS_LOG_DEFAULT, "Failed to release display sleep assertion %u: 0x%08x", targetID, ret);
                allSucceeded = NO;
            }
        }
    }
    
    // 2. System Sleep Assertion Lifecycle
    if (preventSystem) {
        if (_systemAssertionID == kIOPMNullAssertionID) {
            IOPMAssertionID newID = kIOPMNullAssertionID;
            IOReturn ret = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep,
                kIOPMAssertionLevelOn,
                reasonCF,
                &newID
            );
            if (ret == kIOReturnSuccess) {
                _systemAssertionID = newID;
            } else {
                os_log_error(OS_LOG_DEFAULT, "Failed to create system sleep assertion: 0x%08x", ret);
                allSucceeded = NO;
            }
        }
    } else {
        if (_systemAssertionID != kIOPMNullAssertionID) {
            IOPMAssertionID targetID = _systemAssertionID;
            _systemAssertionID = kIOPMNullAssertionID;
            IOReturn ret = IOPMAssertionRelease(targetID);
            if (ret != kIOReturnSuccess) {
                os_log_error(OS_LOG_DEFAULT, "Failed to release system sleep assertion %u: 0x%08x", targetID, ret);
                allSucceeded = NO;
            }
        }
    }
    
    // 3. Display Sleep Assertion Lifecycle: created AFTER system sleep assertion exists
    if (effectivePreventDisplay) {
        if (_displayAssertionID == kIOPMNullAssertionID) {
            IOPMAssertionID newID = kIOPMNullAssertionID;
            IOReturn ret = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep,
                kIOPMAssertionLevelOn,
                reasonCF,
                &newID
            );
            if (ret == kIOReturnSuccess) {
                _displayAssertionID = newID;
            } else {
                os_log_error(OS_LOG_DEFAULT, "Failed to create display sleep assertion: 0x%08x", ret);
                allSucceeded = NO;
            }
        }
    }
    
    os_unfair_lock_unlock(&_lock);
    return allSucceeded;
}

- (void)releaseAllAssertions {
    os_unfair_lock_lock(&_lock);
    
    if (_systemAssertionID != kIOPMNullAssertionID) {
        IOPMAssertionID targetID = _systemAssertionID;
        _systemAssertionID = kIOPMNullAssertionID;
        IOPMAssertionRelease(targetID);
    }
    if (_displayAssertionID != kIOPMNullAssertionID) {
        IOPMAssertionID targetID = _displayAssertionID;
        _displayAssertionID = kIOPMNullAssertionID;
        IOPMAssertionRelease(targetID);
    }
    
    os_unfair_lock_unlock(&_lock);
}

@end
