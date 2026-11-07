// MPPowerSourceMonitor.h
// MacPulse Native Event-Driven Zero-Polling Power Source Monitor

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MPPowerSourceChangeHandler)(BOOL isACConnected, NSInteger batteryPercentage, BOOL isCharging, BOOL isDesktop);

@interface MPPowerSourceMonitor : NSObject

@property (nonatomic, readonly) BOOL isACConnected;
@property (nonatomic, readonly) NSInteger batteryPercentage; // -1 on desktop Mac or when no battery
@property (nonatomic, readonly) BOOL isCharging;
@property (nonatomic, readonly) BOOL isDesktop;

@property (nonatomic, copy, nullable) MPPowerSourceChangeHandler onPowerSourceChange;
@property (nonatomic, copy, nullable) void (^onPowerChange)(BOOL isAC, NSInteger percent); // Backward compatibility

- (void)startMonitoring;
- (void)stopMonitoring;
- (void)refreshPowerSourceStatus;

@end

NS_ASSUME_NONNULL_END
