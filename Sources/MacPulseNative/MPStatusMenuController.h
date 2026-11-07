// MPStatusMenuController.h
// MacPulse Native Status Bar Menu Controller

#import <Cocoa/Cocoa.h>
#import "MPPriorityArbiter.h"
#import "MPTimedAwakeManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface MPStatusMenuController : NSObject <NSMenuDelegate>

@property (nonatomic, readonly) MPPriorityArbiter *arbiter;
@property (nonatomic, readonly) MPTimedAwakeManager *timedAwakeManager;

- (void)setup;
- (void)cleanup;
- (void)promptCustomDuration;

@end

NS_ASSUME_NONNULL_END
