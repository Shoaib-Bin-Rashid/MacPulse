// MPPriorityArbiter.h
// MacPulse Native Mode Priority Arbiter & Battery Safety Cutoff Engine

#import <Foundation/Foundation.h>
#import "MPCommon.h"
#import "MPAppSettings.h"
#import "MPPowerManager.h"
#import "MPPowerSourceMonitor.h"

@class MPTimedAwakeManager;

NS_ASSUME_NONNULL_BEGIN

@interface MPPriorityArbiter : NSObject

@property (nonatomic, readonly) MPActiveMode currentMode;
@property (nonatomic, readonly) NSString *statusSummaryString;
@property (nonatomic, readonly) NSString *menuIconName;
@property (nonatomic, readonly) BOOL isBatteryCutoffActive;

@property (nonatomic, strong) MPAppSettings *settings;
@property (nonatomic, strong) MPPowerSourceMonitor *powerMonitor;
@property (nonatomic, strong) MPPowerManager *powerManager;

// Timed Awake state hooks & manager
@property (nonatomic, strong, nullable) MPTimedAwakeManager *timedAwakeManager;
@property (nonatomic, assign) BOOL isTimedAwakeActive;
@property (nonatomic, assign) NSTimeInterval timedAwakeRemainingSeconds;

@property (nonatomic, copy, nullable) void (^onStateChanged)(MPPriorityArbiter *arbiter);
@property (nonatomic, copy, nullable) void (^onBatteryCutoffEngaged)(NSInteger threshold, NSInteger batteryPercentage);

- (instancetype)initWithPowerManager:(MPPowerManager *)powerManager
                  powerSourceMonitor:(MPPowerSourceMonitor *)powerMonitor
                            settings:(MPAppSettings *)settings;

- (void)start;
- (void)stop;
- (void)evaluateEffectiveState;

@end

NS_ASSUME_NONNULL_END
