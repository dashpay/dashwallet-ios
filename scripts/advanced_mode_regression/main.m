#import "DWGlobalOptions.h"
#import "dashwallet-Swift.h"
#import <Foundation/Foundation.h>

@implementation DWKeychainStore
+ (int64_t)int64ForAccount:(NSString *)account {
    return 0;
}
+ (void)setInt64:(int64_t)value forAccount:(NSString *)account authenticated:(BOOL)authenticated {
}
@end
@implementation DWWalletEnvironment
+ (NSString *)activeWalletIdHex {
    return nil;
}
@end

static NSUInteger checks;
static void check(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
    checks++;
    printf("PASS: %s\n", message.UTF8String);
}

static NSMutableArray<NSString *> *usedSuites;

static NSString *freshSuite(void) {
    NSString *suite = [@"org.dash.advanced-mode-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    [usedSuites addObject:suite];
    return suite;
}

static DWGlobalOptions *optionsForSuite(NSString *suite) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    return [[DWGlobalOptions alloc] initWithUserDefaults:defaults defaults:nil];
}

int main(void) {
    @autoreleasepool {
        usedSuites = [NSMutableArray array];
        __block NSUInteger notifications = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:DWAdvancedModeDidChangeNotification
                                                                      object:nil
                                                                       queue:nil
                                                                  usingBlock:^(NSNotification *note) {
                                                                      notifications++;
                                                                  }];

        // The upgrade path: no saved preference, a wallet that already holds
        // Platform credits, and the first sighting of them.
        NSString *suite = freshSuite();
        DWGlobalOptions *options = optionsForSuite(suite);
        check(!options.advancedModeEnabled, @"Upgrade without saved preference starts off");
        check(!options.advancedModeUserManaged, @"Upgrade without saved preference is not user-managed");
        [options enableAdvancedModeForPlatformBalance:0];
        check(!options.advancedModeEnabled && notifications == 0, @"Zero balance leaves automatic enablement pending");
        [options enableAdvancedModeForPlatformBalance:1];
        check(options.advancedModeEnabled && notifications == 1, @"One raw credit enables mode and notifies once");
        check(!options.advancedModeUserManaged, @"The automatic enable does not claim the preference for the user");
        [options enableAdvancedModeForPlatformBalance:200000];
        check(notifications == 1, @"Repeated positive snapshots do not notify again");

        // A manual disable hands the preference to the user for good.
        [options setAdvancedModeEnabledByUser:NO];
        check(!options.advancedModeEnabled && notifications == 2, @"Manual disable persists and notifies");
        check(options.advancedModeUserManaged, @"Manual disable claims the preference for the user");
        options = optionsForSuite(suite);
        check(options.advancedModeUserManaged, @"The claim survives a new options instance");
        [options enableAdvancedModeForPlatformBalance:0];
        [options enableAdvancedModeForPlatformBalance:999999];
        check(!options.advancedModeEnabled && notifications == 2, @"Resync and refund respect the manual disable");
        // No per-wallet state: a wallet seen funded for the first time is the
        // same call, and it must not reopen a decision the user has made.
        [options enableAdvancedModeForPlatformBalance:1];
        check(!options.advancedModeEnabled, @"A newly funded wallet cannot undo the manual disable");

        // The ordering the per-wallet marker got wrong: an opt-out recorded
        // before any Platform funds ever arrived.
        suite = freshSuite();
        options = optionsForSuite(suite);
        [options setAdvancedModeEnabledByUser:YES];
        check(options.advancedModeEnabled && notifications == 3, @"Manual enable persists and notifies");
        [options setAdvancedModeEnabledByUser:NO];
        check(!options.advancedModeEnabled && notifications == 4, @"Manual disable before any funding persists");
        [options enableAdvancedModeForPlatformBalance:1];
        check(!options.advancedModeEnabled && notifications == 4, @"First funding respects an opt-out made before it");

        // Re-affirming the current value changes nothing on screen but still
        // settles who owns the preference.
        suite = freshSuite();
        options = optionsForSuite(suite);
        NSUInteger before = notifications;
        [options setAdvancedModeEnabledByUser:NO];
        check(notifications == before, @"Writing an unchanged preference does not notify");
        [options enableAdvancedModeForPlatformBalance:1];
        check(!options.advancedModeEnabled, @"An unchanged manual write still claims the preference");

        // A full wipe returns the wallet to a state that can auto-enable again.
        [options restoreToDefaults];
        check(!options.advancedModeEnabled && !options.advancedModeUserManaged, @"Full wipe resets mode and ownership");
        [options enableAdvancedModeForPlatformBalance:1];
        check(options.advancedModeEnabled, @"Automatic enablement works again after a full wipe");

        [NSNotificationCenter.defaultCenter removeObserver:observer];
        for (NSString *usedSuite in usedSuites) {
            [NSUserDefaults.standardUserDefaults removePersistentDomainForName:usedSuite];
        }
        printf("%lu regression checks passed\n", (unsigned long)checks);
    }
    return 0;
}
