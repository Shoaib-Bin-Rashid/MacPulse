// MPPowerSourceMonitor.m
// MacPulse Native Event-Driven Zero-Polling Power Source Monitor

#import "MPPowerSourceMonitor.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

@implementation MPPowerSourceMonitor {
    CFRunLoopSourceRef _runLoopSource;
    dispatch_block_t _pendingDebounceBlock;
    BOOL _isStopped;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isACConnected = YES;
        _batteryPercentage = -1;
        _isCharging = NO;
        _isDesktop = NO;
        _isStopped = NO;
        [self refreshPowerSourceStatus];
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

static void MPPowerSourceCallback(void *context) {
    MPPowerSourceMonitor *monitor = (__bridge MPPowerSourceMonitor *)context;
    [monitor handleHardwareNotification];
}

- (void)handleHardwareNotification {
    _isStopped = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isStopped) return;
        if (self->_pendingDebounceBlock) {
            dispatch_block_cancel(self->_pendingDebounceBlock);
            self->_pendingDebounceBlock = nil;
        }
        __weak typeof(self) weakSelf = self;
        dispatch_block_t block = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_isStopped) return;
            [strongSelf refreshPowerSourceStatus];
            [strongSelf dispatchCallbacks];
        });
        self->_pendingDebounceBlock = block;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)), dispatch_get_main_queue(), block);
    });
}

- (void)dispatchCallbacks {
    if (self.onPowerSourceChange) {
        self.onPowerSourceChange(self.isACConnected, self.batteryPercentage, self.isCharging, self.isDesktop);
    }
    if (self.onPowerChange) {
        self.onPowerChange(self.isACConnected, self.batteryPercentage);
    }
}

- (void)startMonitoring {
    if (_runLoopSource != NULL) return;
    _isStopped = NO;
    
    _runLoopSource = IOPSNotificationCreateRunLoopSource(MPPowerSourceCallback, (__bridge void *)self);
    if (_runLoopSource != NULL) {
        CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
    }
    [self refreshPowerSourceStatus];
}

- (void)stopMonitoring {
    _isStopped = YES;
    if (_pendingDebounceBlock) {
        dispatch_block_cancel(_pendingDebounceBlock);
        _pendingDebounceBlock = nil;
    }
    if (_runLoopSource != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
        CFRelease(_runLoopSource);
        _runLoopSource = NULL;
    }
}

- (void)refreshPowerSourceStatus {
    CFTypeRef snapshot = IOPSCopyPowerSourcesInfo();
    if (!snapshot) {
        // Desktop or restricted execution environment fallback
        _isDesktop = YES;
        _isACConnected = YES;
        _batteryPercentage = -1;
        _isCharging = NO;
        return;
    }
    
    CFStringRef sourceType = IOPSGetProvidingPowerSourceType(snapshot);
    BOOL isAC = (sourceType != NULL && CFStringCompare(sourceType, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo);
    
    CFArrayRef sourcesList = IOPSCopyPowerSourcesList(snapshot);
    BOOL foundBattery = NO;
    NSInteger percent = -1;
    BOOL charging = NO;
    
    if (sourcesList) {
        CFIndex count = CFArrayGetCount(sourcesList);
        for (CFIndex i = 0; i < count; i++) {
            CFTypeRef source = CFArrayGetValueAtIndex(sourcesList, i);
            CFDictionaryRef desc = IOPSGetPowerSourceDescription(snapshot, source);
            if (!desc) continue;
            
            CFStringRef type = CFDictionaryGetValue(desc, CFSTR(kIOPSTypeKey));
            CFBooleanRef isPresent = CFDictionaryGetValue(desc, CFSTR(kIOPSIsPresentKey));
            
            if (isPresent && CFBooleanGetValue(isPresent) == false) {
                continue;
            }
            
            if (type && CFStringCompare(type, CFSTR(kIOPSInternalBatteryType), 0) == kCFCompareEqualTo) {
                foundBattery = YES;
                CFNumberRef curNum = CFDictionaryGetValue(desc, CFSTR(kIOPSCurrentCapacityKey));
                CFNumberRef maxNum = CFDictionaryGetValue(desc, CFSTR(kIOPSMaxCapacityKey));
                if (curNum && maxNum) {
                    int cur = 0, max = 0;
                    CFNumberGetValue(curNum, kCFNumberIntType, &cur);
                    CFNumberGetValue(maxNum, kCFNumberIntType, &max);
                    if (max > 0) {
                        percent = (NSInteger)(((double)cur / (double)max) * 100.0);
                        if (percent < 0) percent = 0;
                        if (percent > 100) percent = 100;
                    }
                }
                
                CFBooleanRef isChargingBool = CFDictionaryGetValue(desc, CFSTR(kIOPSIsChargingKey));
                if (isChargingBool) {
                    charging = CFBooleanGetValue(isChargingBool);
                }
                break;
            }
        }
        CFRelease(sourcesList);
    }
    
    if (!foundBattery) {
        _isDesktop = YES;
        _isACConnected = YES;
        _batteryPercentage = -1;
        _isCharging = NO;
    } else {
        _isDesktop = NO;
        _isACConnected = isAC;
        _batteryPercentage = percent;
        _isCharging = charging;
    }
    
    CFRelease(snapshot);
}

@end
