// MPCommon.h
// MacPulse Native Common Definitions

#ifndef MPCommon_h
#define MPCommon_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MPActiveMode) {
    MPActiveModeDisabled = 0,
    MPActiveModeSmartAwake = 1,
    MPActiveModeTimedAwake = 2,
    MPActiveModeAlwaysAwake = 3
};

#define kMPBatteryThresholdMin 10
#define kMPBatteryThresholdMax 80
#define kMPBatteryThresholdDefault 40

#endif /* MPCommon_h */

