// MPAboutWindowController.h
// MacPulse Native Floating About & Help Window

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPAboutWindowController : NSWindowController <NSWindowDelegate>

+ (instancetype)sharedController;
- (void)showWindow:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
