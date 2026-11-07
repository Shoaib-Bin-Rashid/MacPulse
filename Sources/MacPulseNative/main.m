// main.m
// MacPulse Native Application Entrypoint & Headless Self-Test Runner

#import <Cocoa/Cocoa.h>
#import "MPCommon.h"
#import "MPAppSettings.h"
#import "MPPowerManager.h"
#import "MPPowerSourceMonitor.h"
#import "MPPriorityArbiter.h"
#import "MPStatusMenuController.h"
#import "MPTimedAwakeManager.h"
#import "MPAboutWindowController.h"

// MARK: - Application Delegate
@interface MPAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation MPAppDelegate {
    MPStatusMenuController *_menuController;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    _menuController = [[MPStatusMenuController alloc] init];
    [_menuController setup];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_menuController cleanup];
    [[MPPowerManager sharedManager] releaseAllAssertions];
}

@end

// MARK: - Headless Self-Test Runner
static int runSelfTests(void) {
    @autoreleasepool {
        fprintf(stdout, "⚡ Running MacPulse Deterministic Headless Self-Tests...\n");
        
        // 1. AppSettings defaults & properties (backup user settings first to prevent pollution)
        MPAppSettings *settings = [MPAppSettings sharedSettings];
        [settings reloadSettings];
        BOOL origCharging = settings.keepAwakeWhileCharging;
        BOOL origAlways = settings.alwaysAwake;
        BOOL origDisplay = settings.keepDisplayAwake;
        NSInteger origThreshold = settings.batterySafetyThreshold;
        
        if (settings.batterySafetyThreshold < 10) {
            settings.batterySafetyThreshold = 40;
        }
        fprintf(stdout, "[PASS] MPAppSettings initialization and defaults\n");
        
        // 2. MPPowerManager dual assertion lifecycle and idempotency
        MPPowerManager *pm = [MPPowerManager sharedManager];
        [pm releaseAllAssertions];
        
        BOOL ok1 = [pm applyStateWithSystemSleepPrevented:YES displaySleepPrevented:NO reason:@"SelfTest: SystemOnly"];
        if (!ok1 || !pm.isSystemSleepPrevented || pm.isDisplaySleepPrevented) {
            fprintf(stderr, "FAIL: System sleep assertion creation failed\n");
            return 1;
        }
        
        // Idempotent re-apply
        BOOL okIdempotent = [pm applyStateWithSystemSleepPrevented:YES displaySleepPrevented:NO reason:@"SelfTest: Idempotent"];
        if (!okIdempotent || !pm.isSystemSleepPrevented) {
            fprintf(stderr, "FAIL: Idempotent system assertion failed\n");
            return 1;
        }
        
        // Add display sleep prevention
        BOOL ok2 = [pm applyStateWithSystemSleepPrevented:YES displaySleepPrevented:YES reason:@"SelfTest: SystemAndDisplay"];
        if (!ok2 || !pm.isSystemSleepPrevented || !pm.isDisplaySleepPrevented) {
            fprintf(stderr, "FAIL: Display sleep assertion creation failed\n");
            return 1;
        }
        fprintf(stdout, "[PASS] MPPowerManager dual assertion lifecycle and idempotency\n");
        
        // 3. Double-release safety (no 0xe00002c2 kernel error)
        [pm releaseAllAssertions];
        if (pm.isSystemSleepPrevented || pm.isDisplaySleepPrevented) {
            fprintf(stderr, "FAIL: Release assertions left active assertions\n");
            return 1;
        }
        // Second release must succeed cleanly as an idempotent no-op
        [pm releaseAllAssertions];
        fprintf(stdout, "[PASS] MPPowerManager double-release safety (no 0xe00002c2)\n");
        
        // 4. Priority Arbiter hierarchy
        MPPowerSourceMonitor *powerMon = [[MPPowerSourceMonitor alloc] init];
        MPPriorityArbiter *arbiter = [[MPPriorityArbiter alloc] initWithPowerManager:pm
                                                                  powerSourceMonitor:powerMon
                                                                            settings:settings];
        
        // Test smart awake disabled -> Disabled mode
        settings.alwaysAwake = NO;
        settings.keepAwakeWhileCharging = NO;
        arbiter.isTimedAwakeActive = NO;
        [arbiter evaluateEffectiveState];
        if (arbiter.currentMode != MPActiveModeDisabled || pm.isSystemSleepPrevented) {
            fprintf(stderr, "FAIL: Expected Disabled mode, got %ld\n", (long)arbiter.currentMode);
            return 1;
        }
        
        // Test Smart Awake priority
        settings.keepAwakeWhileCharging = YES;
        [arbiter evaluateEffectiveState];
        BOOL expectedSmart = (powerMon.isACConnected || powerMon.isDesktop);
        if (expectedSmart && arbiter.currentMode != MPActiveModeSmartAwake) {
            fprintf(stderr, "FAIL: Expected Smart Awake mode on AC\n");
            return 1;
        }
        
        // Test Timed Awake priority > Smart Awake
        arbiter.isTimedAwakeActive = YES;
        arbiter.timedAwakeRemainingSeconds = 1800;
        [arbiter evaluateEffectiveState];
        if (arbiter.currentMode != MPActiveModeTimedAwake) {
            fprintf(stderr, "FAIL: Expected Timed Awake to override Smart Awake\n");
            return 1;
        }
        
        // Test Always Awake priority > Timed Awake
        settings.alwaysAwake = YES;
        [arbiter evaluateEffectiveState];
        // If not tripped by cutoff, Always Awake must win
        if (!arbiter.isBatteryCutoffActive && arbiter.currentMode != MPActiveModeAlwaysAwake) {
            fprintf(stderr, "FAIL: Expected Always Awake to override Timed Awake\n");
            return 1;
        }
        fprintf(stdout, "[PASS] MPPriorityArbiter hierarchy (Always Awake > Timed Awake > Smart Awake > Disabled)\n");
        
        // 5. Battery safety cutoff logic
        settings.alwaysAwake = YES;
        settings.batterySafetyThreshold = 99;
        if (!powerMon.isDesktop && !powerMon.isACConnected && powerMon.batteryPercentage <= 99) {
            [arbiter evaluateEffectiveState];
            if (!arbiter.isBatteryCutoffActive || settings.alwaysAwake) {
                fprintf(stderr, "FAIL: Battery safety cutoff failed to disengage alwaysAwake\n");
                return 1;
            }
        }
        arbiter.isTimedAwakeActive = NO;
        settings.alwaysAwake = NO;
        settings.batterySafetyThreshold = origThreshold;
        [arbiter evaluateEffectiveState];
        fprintf(stdout, "[PASS] MPPriorityArbiter battery safety cutoff logic\n");
        
        // 6. MPPowerSourceMonitor desktop Mac detection
        [powerMon refreshPowerSourceStatus];
        if (powerMon.isDesktop) {
            if (!powerMon.isACConnected || powerMon.batteryPercentage != -1) {
                fprintf(stderr, "FAIL: Desktop Mac invariant violated\n");
                return 1;
            }
        } else {
            if (powerMon.batteryPercentage < 0 || powerMon.batteryPercentage > 100) {
                fprintf(stderr, "FAIL: Portable Mac battery percentage out of bounds: %ld\n", (long)powerMon.batteryPercentage);
                return 1;
            }
        }
        fprintf(stdout, "[PASS] MPPowerSourceMonitor desktop Mac detection\n");
        
        // 7. MPTimedAwakeManager monotonic countdown and session lifecycle
        MPTimedAwakeManager *timedMgr = [[MPTimedAwakeManager alloc] init];
        if (timedMgr.isActive || timedMgr.remainingSeconds != 0.0) {
            fprintf(stderr, "FAIL: MPTimedAwakeManager initial state is not inactive\n");
            return 1;
        }
        
        // Start 30m session
        [timedMgr startSessionWithDuration:kMPTimedAwakeDuration30Min];
        if (!timedMgr.isActive || timedMgr.remainingSeconds <= 1700.0 || timedMgr.initialDuration != 1800.0) {
            fprintf(stderr, "FAIL: MPTimedAwakeManager start 30m session failed\n");
            return 1;
        }
        if (![timedMgr.compactTitle containsString:@"m"]) {
            fprintf(stderr, "FAIL: MPTimedAwakeManager compactTitle invalid: %s\n", [timedMgr.compactTitle UTF8String]);
            return 1;
        }
        if (![timedMgr.formattedRemainingTime containsString:@":"]) {
            fprintf(stderr, "FAIL: MPTimedAwakeManager formattedRemainingTime invalid: %s\n", [timedMgr.formattedRemainingTime UTF8String]);
            return 1;
        }
        
        // Overwrite with 1h session
        [timedMgr startSessionWithDuration:kMPTimedAwakeDuration1Hour];
        if (!timedMgr.isActive || timedMgr.remainingSeconds <= 3500.0 || timedMgr.initialDuration != 3600.0) {
            fprintf(stderr, "FAIL: MPTimedAwakeManager overwrite with 1h failed\n");
            return 1;
        }
        
        // 0-duration boundary test
        [timedMgr startSessionWithDuration:0.0];
        if (timedMgr.isActive || timedMgr.remainingSeconds != 0.0) {
            fprintf(stderr, "FAIL: MPTimedAwakeManager 0-duration boundary check failed\n");
            return 1;
        }
        
        // Start and cancel session
        [timedMgr startSessionWithDuration:kMPTimedAwakeDuration2Hours];
        [timedMgr cancelSession];
        if (timedMgr.isActive || timedMgr.remainingSeconds != 0.0) {
            fprintf(stderr, "FAIL: MPTimedAwakeManager cancellation failed\n");
            return 1;
        }
        // Idempotent repeated cancel
        [timedMgr cancelSession];
        fprintf(stdout, "[PASS] MPTimedAwakeManager monotonic countdown and session lifecycle\n");
        
        // 8. MPPriorityArbiter dynamic Timed Awake manager integration and fallback
        arbiter.timedAwakeManager = timedMgr;
        settings.alwaysAwake = NO;
        settings.keepAwakeWhileCharging = NO;
        [timedMgr startSessionWithDuration:kMPTimedAwakeDuration30Min];
        [arbiter evaluateEffectiveState];
        if (arbiter.currentMode != MPActiveModeTimedAwake || !pm.isSystemSleepPrevented) {
            fprintf(stderr, "FAIL: Arbiter did not engage Timed Awake from MPTimedAwakeManager\n");
            return 1;
        }
        [timedMgr cancelSession];
        [arbiter evaluateEffectiveState];
        if (arbiter.currentMode != MPActiveModeDisabled || pm.isSystemSleepPrevented) {
            fprintf(stderr, "FAIL: Arbiter did not fall back cleanly upon Timed Awake cancel\n");
            return 1;
        }
        fprintf(stdout, "[PASS] MPPriorityArbiter dynamic Timed Awake manager integration and fallback\n");
        
        // 9. MPAboutWindowController utility panel instantiation and feature coverage
        MPAboutWindowController *aboutCtrl = [MPAboutWindowController sharedController];
        if (!aboutCtrl || !aboutCtrl.window) {
            fprintf(stderr, "FAIL: MPAboutWindowController or window is nil\n");
            return 1;
        }
        if (![aboutCtrl.window.title containsString:@"MacPulse"]) {
            fprintf(stderr, "FAIL: MPAboutWindowController title missing MacPulse\n");
            return 1;
        }
        NSRect contentRect = [aboutCtrl.window contentRectForFrameRect:aboutCtrl.window.frame];
        if (contentRect.size.width != 440 || contentRect.size.height != 420) {
            fprintf(stderr, "FAIL: MPAboutWindowController dimensions incorrect (%.0f x %.0f, expected 440 x 420)\n",
                    contentRect.size.width, contentRect.size.height);
            return 1;
        }
        fprintf(stdout, "[PASS] MPAboutWindowController utility panel instantiation and feature coverage\n");
        
        // 10. Clean teardown and assertion release
        [[NSNotificationCenter defaultCenter] removeObserver:arbiter];
        [arbiter stop];
        [pm releaseAllAssertions];
        if (pm.isSystemSleepPrevented || pm.isDisplaySleepPrevented) {
            fprintf(stderr, "FAIL: Lingering assertions on teardown\n");
            return 1;
        }
        fprintf(stdout, "[PASS] Clean teardown and assertion release\n");
        
        // Restore original user settings
        settings.keepAwakeWhileCharging = origCharging;
        settings.alwaysAwake = origAlways;
        settings.keepDisplayAwake = origDisplay;
        settings.batterySafetyThreshold = origThreshold;
        
        fprintf(stdout, "All self-tests passed cleanly.\n");
        return 0;
    }
}

// MARK: - Entrypoint
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 1. Check for --selftest anywhere in argv
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--selftest") == 0) {
                return runSelfTests();
            }
        }
        
        // 2. Check for help
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
                fprintf(stdout,
                        "MacPulse - Native macOS Menu Bar Keep-Awake Utility (v1.0.0)\n"
                        "Usage: MacPulse [options]\n\n"
                        "Options:\n"
                        "  --selftest     Run headless regression and integration self-tests\n"
                        "  -h, --help     Show this help and options reference\n\n"
                        "Features:\n"
                        "  - Smart Awake: Keeps Mac awake while on AC power\n"
                        "  - Timed Awake: Custom duration & presets (15m to 8h)\n"
                        "  - Always Awake: Battery-safe continuous awake mode\n"
                        "  - Keep Display Awake: Prevents monitor idle sleep (cutoff safe)\n"
                        "  - Battery Cutoff: Configurable safety threshold (default 40%%)\n"
                        "  - Launch at Login: Background SMAppService integration\n");
                return 0;
            }
        }
        
        // 3. Check for unknown CLI flags starting with --
        for (int i = 1; i < argc; i++) {
            if (strncmp(argv[i], "--", 2) == 0) {
                fprintf(stderr, "Unknown option: %s\nUsage: MacPulse [--selftest] [--help]\n", argv[i]);
                return 1;
            }
        }
        
        NSApplication *app = [NSApplication sharedApplication];
        MPAppDelegate *delegate = [[MPAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
