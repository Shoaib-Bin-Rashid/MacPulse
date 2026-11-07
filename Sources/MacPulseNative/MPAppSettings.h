// MPAppSettings.h
// MacPulse Native Persistent Settings

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kMPAppSettingsDidChangeNotification;

@interface MPAppSettings : NSObject

@property (nonatomic, assign) BOOL keepAwakeWhileCharging;
@property (nonatomic, assign) BOOL alwaysAwake;
@property (nonatomic, assign) BOOL keepDisplayAwake; // Default: NO (display sleeps normally unless user enables Keep Display Awake)
@property (nonatomic, assign) BOOL allowDisplaySleep; // Legacy inverted alias for keepDisplayAwake (!keepDisplayAwake)
@property (nonatomic, assign) NSInteger batterySafetyThreshold; // Default: 40 (percent)

+ (instancetype)sharedSettings;
- (void)reloadSettings;

@end

NS_ASSUME_NONNULL_END
