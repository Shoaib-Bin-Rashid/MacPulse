// MPTimedAwakeManager.h
// MacPulse Native Timed Keep-Awake Session & Monotonic Countdown Engine

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSTimeInterval kMPTimedAwakeDuration30Min; // 1800.0s (30m)
FOUNDATION_EXPORT const NSTimeInterval kMPTimedAwakeDuration1Hour; // 3600.0s (1h)
FOUNDATION_EXPORT const NSTimeInterval kMPTimedAwakeDuration2Hours; // 7200.0s (2h)

typedef void (^MPTimedAwakeTickHandler)(NSTimeInterval remainingSeconds);
typedef void (^MPTimedAwakeCompletionHandler)(BOOL expired);

@interface MPTimedAwakeManager : NSObject

@property (nonatomic, readonly) BOOL isActive;
@property (nonatomic, readonly) NSTimeInterval initialDuration;
@property (nonatomic, readonly) NSTimeInterval remainingSeconds;
@property (nonatomic, readonly) NSString *formattedRemainingTime; // e.g. "29:59" or "1:59:59"
@property (nonatomic, readonly) NSString *compactTitle;           // e.g. " 29m" or " 1h 59m"

@property (nonatomic, copy, nullable) MPTimedAwakeTickHandler onTick;
@property (nonatomic, copy, nullable) MPTimedAwakeCompletionHandler onCompletion;

- (void)startSessionWithDuration:(NSTimeInterval)duration;
- (void)cancelSession;

@end

NS_ASSUME_NONNULL_END
