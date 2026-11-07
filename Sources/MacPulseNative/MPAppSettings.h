// MPAppSettings.h
// MacPulse Native Persistent Settings

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kMPAppSettingsDidChangeNotification;

@interface MPAppSettings : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *suiteName;
@property (nonatomic, readonly) NSUserDefaults *userDefaults;

@property (nonatomic, assign) BOOL keepAwakeWhileCharging;
@property (nonatomic, assign) BOOL alwaysAwake;
@property (nonatomic, assign) BOOL keepDisplayAwake; // Controlled via 'Keep Display On' in menu (Default: NO)
@property (nonatomic, assign) BOOL allowDisplaySleep; // Legacy inverted alias for keepDisplayAwake (!keepDisplayAwake)
@property (nonatomic, assign) NSInteger batterySafetyThreshold; // Default: 40 (percent)

+ (instancetype)sharedSettings;
+ (instancetype)sharedSettingsWithSuiteName:(nullable NSString *)suiteName;
+ (void)resetSharedInstance;

- (instancetype)initWithSuiteName:(nullable NSString *)suiteName;
- (void)reloadSettings;
- (void)resetSuite;

@end

NS_ASSUME_NONNULL_END
