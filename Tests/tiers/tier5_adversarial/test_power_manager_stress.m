// test_power_manager_stress.m
// Empirical Adversarial Stress Test for MPPowerManager
// Tests: Concurrency under os_unfair_lock, double-release safety, null-assertion idempotency

#import <Foundation/Foundation.h>
#import "MPPowerManager.h"
#import <stdatomic.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        fprintf(stdout, ">>> [STRESS 1] Starting MPPowerManager Concurrency & Idempotency Harness...\n");
        
        MPPowerManager *pm = [MPPowerManager sharedManager];
        [pm releaseAllAssertions];
        
        // --- Phase 1: Null-assertion & Double-release Safety ---
        fprintf(stdout, "  [Step 1.1] Testing 500 repeated null releases...\n");
        for (int i = 0; i < 500; i++) {
            [pm releaseAllAssertions];
            [pm releaseAssertion];
            if ([pm isSystemSleepPrevented] || [pm isDisplaySleepPrevented]) {
                fprintf(stderr, "FAIL: Assertions active during null release phase!\n");
                return 1;
            }
        }
        fprintf(stdout, "  [Step 1.1 PASS] Zero crashes or errors on 500 null releases.\n");
        
        // --- Phase 2: Rapid Single-Thread Toggle ---
        fprintf(stdout, "  [Step 1.2] Testing 1,000 rapid sequential state transitions...\n");
        for (int i = 0; i < 1000; i++) {
            BOOL sys = (i % 2 == 0);
            BOOL disp = (i % 4 == 0);
            BOOL ok = [pm applyStateWithSystemSleepPrevented:sys
                                      displaySleepPrevented:disp
                                                     reason:@"StressTest: Sequential"];
            if (!ok) {
                fprintf(stderr, "FAIL: applyState failed at iteration %d\n", i);
                return 1;
            }
            if ([pm isSystemSleepPrevented] != sys) {
                fprintf(stderr, "FAIL: System sleep assertion mismatch at iteration %d (expected %d, got %d)\n",
                        i, sys, [pm isSystemSleepPrevented]);
                return 1;
            }
            BOOL expectedDisp = sys && disp;
            if ([pm isDisplaySleepPrevented] != expectedDisp) {
                fprintf(stderr, "FAIL: Display sleep assertion mismatch at iteration %d (expected %d, got %d)\n",
                        i, expectedDisp, [pm isDisplaySleepPrevented]);
                return 1;
            }
        }
        [pm releaseAllAssertions];
        fprintf(stdout, "  [Step 1.2 PASS] 1,000 sequential transitions passed cleanly.\n");
        
        // --- Phase 3: High-Concurrency Multi-Threaded Hammer ---
        fprintf(stdout, "  [Step 1.3] Launching 10 concurrent threads hammering os_unfair_lock (5,000 total operations)...\n");
        dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        dispatch_group_t group = dispatch_group_create();
        
        __block _Atomic int errorCount = 0;
        const int kThreadCount = 10;
        const int kOpsPerThread = 500;
        
        for (int t = 0; t < kThreadCount; t++) {
            dispatch_group_async(group, queue, ^{
                for (int i = 0; i < kOpsPerThread; i++) {
                    int op = (i + t) % 5;
                    switch (op) {
                        case 0:
                            [pm applyStateWithSystemSleepPrevented:YES displaySleepPrevented:NO reason:@"StressThread"];
                            break;
                        case 1:
                            [pm applyStateWithSystemSleepPrevented:YES displaySleepPrevented:YES reason:@"StressThread"];
                            break;
                        case 2:
                            [pm applyStateWithSystemSleepPrevented:NO displaySleepPrevented:NO reason:@"StressThread"];
                            break;
                        case 3:
                            [pm releaseAssertion];
                            break;
                        case 4:
                            [pm releaseAllAssertions];
                            break;
                    }
                    // Validate invariants atomically under lock
                    BOOL s = NO, d = NO;
                    [pm getSystemSleepPrevented:&s displaySleepPrevented:&d];
                    if (!s && d) {
                        // Display sleep must NEVER be active if system sleep is not active
                        atomic_fetch_add(&errorCount, 1);
                        fprintf(stderr, "INVARIANT VIOLATION: Display sleep prevented while system sleep allowed!\n");
                    }
                }
            });
        }
        
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        
        if (atomic_load(&errorCount) > 0) {
            fprintf(stderr, "FAIL: %d invariant violations during multi-threaded stress!\n", atomic_load(&errorCount));
            return 1;
        }
        fprintf(stdout, "  [Step 1.3 PASS] 5,000 multi-threaded operations passed without invariant violations.\n");
        
        // --- Phase 4: Final Teardown Verification ---
        fprintf(stdout, "  [Step 1.4] Final teardown and leak check...\n");
        [pm releaseAllAssertions];
        if ([pm isSystemSleepPrevented] || [pm isDisplaySleepPrevented]) {
            fprintf(stderr, "FAIL: Lingering assertions after final releaseAllAssertions!\n");
            return 1;
        }
        // Second release to confirm double-release idempotency after multi-threaded stress
        [pm releaseAllAssertions];
        fprintf(stdout, "  [Step 1.4 PASS] MPPowerManager clean teardown verified.\n");
        
        fprintf(stdout, ">>> [STRESS 1 COMPLETE] All MPPowerManager stress tests PASSED.\n");
        return 0;
    }
}
