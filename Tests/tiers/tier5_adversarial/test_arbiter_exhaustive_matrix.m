// test_arbiter_exhaustive_matrix.m
// Empirical Adversarial Stress Test for MPPriorityArbiter
// Exhaustively tests all 3,840 state combinations against formal specification oracles

#import <Foundation/Foundation.h>
#import "MPCommon.h"
#import "MPAppSettings.h"
#import "MPPowerManager.h"
#import "MPPowerSourceMonitor.h"
#import "MPPriorityArbiter.h"

@interface MPMockPowerMonitor : MPPowerSourceMonitor
@property (nonatomic, assign) BOOL mockAC;
@property (nonatomic, assign) NSInteger mockBattery;
@property (nonatomic, assign) BOOL mockCharging;
@property (nonatomic, assign) BOOL mockDesktop;
@end

@implementation MPMockPowerMonitor
- (BOOL)isACConnected { return self.mockAC; }
- (NSInteger)batteryPercentage { return self.mockBattery; }
- (BOOL)isCharging { return self.mockCharging; }
- (BOOL)isDesktop { return self.mockDesktop; }
- (void)startMonitoring {}
- (void)stopMonitoring {}
- (void)refreshPowerSourceStatus {}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        fprintf(stdout, ">>> [STRESS 2] Starting MPPriorityArbiter Exhaustive State Matrix Harness...\n");
        
        MPAppSettings *settings = [MPAppSettings sharedSettings];
        MPPowerManager *pm = [MPPowerManager sharedManager];
        [pm releaseAllAssertions];
        
        MPMockPowerMonitor *mockMonitor = [[MPMockPowerMonitor alloc] init];
        MPPriorityArbiter *arbiter = [[MPPriorityArbiter alloc] initWithPowerManager:pm
                                                                  powerSourceMonitor:mockMonitor
                                                                            settings:settings];
        
        // Remove notification observer to avoid evaluating half-configured states during batch setup
        [[NSNotificationCenter defaultCenter] removeObserver:arbiter
                                                        name:kMPAppSettingsDidChangeNotification
                                                      object:nil];
        
        BOOL boolVals[2] = { NO, YES };
        NSInteger batteryValues[] = { -1, 0, 5, 10, 15, 20, 25, 30, 40, 50, 75, 100 };
        int batteryCount = sizeof(batteryValues) / sizeof(batteryValues[0]);
        NSInteger thresholdValues[] = { 10, 20, 30, 40, 50 };
        int thresholdCount = sizeof(thresholdValues) / sizeof(thresholdValues[0]);
        
        int totalTests = 0;
        int failureCount = 0;
        
        for (int bAlways = 0; bAlways < 2; bAlways++) {
            for (int bTimed = 0; bTimed < 2; bTimed++) {
                for (int bSmart = 0; bSmart < 2; bSmart++) {
                    for (int bDisplay = 0; bDisplay < 2; bDisplay++) {
                        for (int bAC = 0; bAC < 2; bAC++) {
                            for (int bDesk = 0; bDesk < 2; bDesk++) {
                                for (int bBat = 0; bBat < batteryCount; bBat++) {
                                    for (int bThresh = 0; bThresh < thresholdCount; bThresh++) {
                                        totalTests++;
                                        
                                        BOOL reqAlways = boolVals[bAlways];
                                        BOOL reqTimed = boolVals[bTimed];
                                        BOOL reqSmart = boolVals[bSmart];
                                        BOOL reqAllowDisplay = boolVals[bDisplay];
                                        BOOL reqAC = boolVals[bAC];
                                        BOOL reqDesk = boolVals[bDesk];
                                        NSInteger reqBattery = batteryValues[bBat];
                                        NSInteger reqThreshold = thresholdValues[bThresh];
                                        
                                        // Configure mock power monitor
                                        mockMonitor.mockAC = reqAC;
                                        mockMonitor.mockDesktop = reqDesk;
                                        mockMonitor.mockBattery = reqBattery;
                                        mockMonitor.mockCharging = NO;
                                        
                                        // Configure settings
                                        settings.batterySafetyThreshold = reqThreshold;
                                        settings.keepAwakeWhileCharging = reqSmart;
                                        settings.allowDisplaySleep = reqAllowDisplay;
                                        settings.alwaysAwake = reqAlways;
                                        
                                        // Configure Timed Awake state
                                        arbiter.isTimedAwakeActive = reqTimed;
                                        arbiter.timedAwakeRemainingSeconds = reqTimed ? 1800 : 0;
                                        
                                        // Trigger arbitration evaluation
                                        [arbiter evaluateEffectiveState];
                                        
                                        // --- ORACLE SPECIFICATION ---
                                        BOOL isPortableOnBattery = (!reqDesk && !reqAC);
                                        BOOL shouldCutoff = (reqAlways && isPortableOnBattery && reqBattery >= 0 && reqBattery <= reqThreshold);
                                        
                                        MPActiveMode expectedMode = MPActiveModeDisabled;
                                        if (reqAlways && !shouldCutoff) {
                                            expectedMode = MPActiveModeAlwaysAwake;
                                        } else if (reqTimed) {
                                            expectedMode = MPActiveModeTimedAwake;
                                        } else if (reqSmart && (reqAC || reqDesk)) {
                                            expectedMode = MPActiveModeSmartAwake;
                                        } else {
                                            expectedMode = MPActiveModeDisabled;
                                        }
                                        
                                        BOOL expectedSystem = (expectedMode != MPActiveModeDisabled);
                                        BOOL expectedDisplay = expectedSystem && (!reqAllowDisplay);
                                        
                                        // Invariant 1: Battery Cutoff detection
                                        if (arbiter.isBatteryCutoffActive != shouldCutoff) {
                                            fprintf(stderr, "FAIL [Cutoff Mismatch]: Test %d: bat=%ld thresh=%ld desk=%d ac=%d always=%d | expectedCutoff=%d actualCutoff=%d\n",
                                                    totalTests, (long)reqBattery, (long)reqThreshold, reqDesk, reqAC, reqAlways,
                                                    shouldCutoff, arbiter.isBatteryCutoffActive);
                                            failureCount++;
                                            if (failureCount > 10) break;
                                        }
                                        
                                        // Invariant 2: Mode Priority Arbitration
                                        if (arbiter.currentMode != expectedMode) {
                                            fprintf(stderr, "FAIL [Mode Priority Mismatch]: Test %d: expectedMode=%ld actualMode=%ld\n",
                                                    totalTests, (long)expectedMode, (long)arbiter.currentMode);
                                            failureCount++;
                                            if (failureCount > 10) break;
                                        }
                                        
                                        // Invariant 3: Power Manager System Assertion
                                        if (pm.isSystemSleepPrevented != expectedSystem) {
                                            fprintf(stderr, "FAIL [System Assertion Mismatch]: Test %d: expectedSystem=%d actualSystem=%d\n",
                                                    totalTests, expectedSystem, pm.isSystemSleepPrevented);
                                            failureCount++;
                                            if (failureCount > 10) break;
                                        }
                                        
                                        // Invariant 4: Power Manager Display Assertion
                                        if (pm.isDisplaySleepPrevented != expectedDisplay) {
                                            fprintf(stderr, "FAIL [Display Assertion Mismatch]: Test %d: allowDisplay=%d sys=%d | expectedDisp=%d actualDisp=%d\n",
                                                    totalTests, reqAllowDisplay, expectedSystem, expectedDisplay, pm.isDisplaySleepPrevented);
                                            failureCount++;
                                            if (failureCount > 10) break;
                                        }
                                    }
                                    if (failureCount > 10) break;
                                }
                                if (failureCount > 10) break;
                            }
                            if (failureCount > 10) break;
                        }
                        if (failureCount > 10) break;
                    }
                    if (failureCount > 10) break;
                }
                if (failureCount > 10) break;
            }
            if (failureCount > 10) break;
        }
        
        [arbiter stop];
        [pm releaseAllAssertions];
        
        if (failureCount > 0) {
            fprintf(stderr, "FAIL: %d failures out of %d state combinations!\n", failureCount, totalTests);
            return 1;
        }
        
        fprintf(stdout, ">>> [STRESS 2 PASS] All %d state combinations matched specification oracle 100%%.\n", totalTests);
        return 0;
    }
}
