// MPPowerManager.h
// MacPulse Native Dual Power Assertion Manager

#import <Foundation/Foundation.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPPowerManager : NSObject

@property (nonatomic, readonly) BOOL isSystemSleepPrevented;
@property (nonatomic, readonly) BOOL isDisplaySleepPrevented;
@property (nonatomic, readonly) BOOL isAssertionActive; // Compatibility alias for isSystemSleepPrevented

- (void)getSystemSleepPrevented:(nullable BOOL *)outSystem displaySleepPrevented:(nullable BOOL *)outDisplay;

+ (instancetype)sharedManager;

- (BOOL)applyStateWithSystemSleepPrevented:(BOOL)preventSystem
                    displaySleepPrevented:(BOOL)preventDisplay
                                   reason:(nullable NSString *)reason;

- (BOOL)createPreventSystemSleepAssertionWithReason:(nullable NSString *)reason;
- (BOOL)releaseAssertion;
- (void)releaseAllAssertions;

@end

NS_ASSUME_NONNULL_END
