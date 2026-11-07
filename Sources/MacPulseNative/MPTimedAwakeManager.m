// MPTimedAwakeManager.m
// MacPulse Native Timed Keep-Awake Session & Monotonic Countdown Engine

#import "MPTimedAwakeManager.h"
#import <Cocoa/Cocoa.h>

const NSTimeInterval kMPTimedAwakeDuration30Min = 1800.0;
const NSTimeInterval kMPTimedAwakeDuration1Hour = 3600.0;
const NSTimeInterval kMPTimedAwakeDuration2Hours = 7200.0;

@implementation MPTimedAwakeManager {
    NSTimer *_timer;
    NSTimeInterval _targetEndUptime;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isActive = NO;
        _initialDuration = 0.0;
        _targetEndUptime = 0.0;
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(handleSystemWake:)
                                                                   name:NSWorkspaceDidWakeNotification
                                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [self cancelTimerOnly];
}

- (void)handleSystemWake:(NSNotification *)note {
    if (_isActive) {
        [self handleTimerTick];
    }
}

- (void)cancelTimerOnly {
    if (_timer) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)startSessionWithDuration:(NSTimeInterval)duration {
    // Boundary check: 0 or negative duration transitions immediately without remaining active
    if (duration <= 0.0) {
        [self cancelTimerOnly];
        _isActive = NO;
        _initialDuration = 0.0;
        _targetEndUptime = 0.0;
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"activeTimedDuration"];
        
        if (self.onTick) {
            self.onTick(0.0);
        }
        if (self.onCompletion) {
            self.onCompletion(YES);
        }
        return;
    }
    
    // Invalidate existing timer cleanly to avoid duplicate timers on restart
    [self cancelTimerOnly];
    
    _isActive = YES;
    _initialDuration = duration;
    _targetEndUptime = [[NSProcessInfo processInfo] systemUptime] + duration;
    
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)duration forKey:@"activeTimedDuration"];
    
    // Schedule repeating 1-second monotonic countdown timer on the main runloop
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:1.0
                                    repeats:YES
                                      block:^(NSTimer * _Nonnull timer) {
        [weakSelf handleTimerTick];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    
    if (self.onTick) {
        self.onTick([self remainingSeconds]);
    }
}

- (void)cancelSession {
    if (!_isActive) {
        return; // Safe idempotent no-op
    }
    
    _isActive = NO;
    _initialDuration = 0.0;
    _targetEndUptime = 0.0;
    [self cancelTimerOnly];
    
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"activeTimedDuration"];
    
    if (self.onTick) {
        self.onTick(0.0);
    }
    if (self.onCompletion) {
        self.onCompletion(NO); // Cancelled manually, not expired
    }
}

- (void)handleTimerTick {
    if (!_isActive) {
        [self cancelTimerOnly];
        return;
    }
    
    NSTimeInterval remaining = [self remainingSeconds];
    if (remaining <= 0.0) {
        _isActive = NO;
        _initialDuration = 0.0;
        _targetEndUptime = 0.0;
        [self cancelTimerOnly];
        
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"activeTimedDuration"];
        
        if (self.onTick) {
            self.onTick(0.0);
        }
        if (self.onCompletion) {
            self.onCompletion(YES); // Successfully expired
        }
    } else {
        if (self.onTick) {
            self.onTick(remaining);
        }
    }
}

- (NSTimeInterval)remainingSeconds {
    if (!_isActive) {
        return 0.0;
    }
    NSTimeInterval now = [[NSProcessInfo processInfo] systemUptime];
    NSTimeInterval remaining = _targetEndUptime - now;
    if (remaining < 0.0) {
        return 0.0;
    }
    return remaining;
}

- (NSString *)formattedRemainingTime {
    if (!_isActive) {
        return @"00:00";
    }
    NSTimeInterval rem = [self remainingSeconds];
    NSInteger totalSecs = (NSInteger)ceil(rem);
    if (totalSecs < 0) {
        totalSecs = 0;
    }
    NSInteger hours = totalSecs / 3600;
    NSInteger mins = (totalSecs % 3600) / 60;
    NSInteger secs = totalSecs % 60;
    
    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)mins, (long)secs];
    } else {
        return [NSString stringWithFormat:@"%02ld:%02ld", (long)mins, (long)secs];
    }
}

- (NSString *)compactTitle {
    if (!_isActive) {
        return @"";
    }
    NSTimeInterval rem = [self remainingSeconds];
    NSInteger totalMins = (NSInteger)(rem / 60.0);
    NSInteger hours = totalMins / 60;
    NSInteger remainingMins = totalMins % 60;
    
    if (hours > 0) {
        return [NSString stringWithFormat:@" %ldh %02ldm", (long)hours, (long)remainingMins];
    } else {
        return [NSString stringWithFormat:@" %ldm", (long)totalMins];
    }
}

@end
