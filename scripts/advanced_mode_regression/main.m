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

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"org.dash.advanced-mode-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        DWGlobalOptions *options = [[DWGlobalOptions alloc] initWithUserDefaults:defaults defaults:nil];
        __block NSUInteger notifications = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:DWAdvancedModeDidChangeNotification
                                                                      object:nil
                                                                       queue:nil
                                                                  usingBlock:^(NSNotification *note) {
                                                                      notifications++;
                                                                  }];
        check(!options.advancedModeEnabled, @"Upgrade without saved preference starts off");
        [options enableAdvancedModeForPlatformBalance:0 walletIdHex:@"a" network:@"testnet"];
        check(!options.advancedModeEnabled && notifications == 0, @"Zero balance leaves automatic enablement pending");
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"" network:@"testnet"];
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"a" network:@""];
        check(!options.advancedModeEnabled, @"Missing wallet/network context cannot enable mode");
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"a" network:@"testnet"];
        check(options.advancedModeEnabled && notifications == 1, @"One raw credit enables mode and notifies once");
        [options enableAdvancedModeForPlatformBalance:200000 walletIdHex:@"a" network:@"testnet"];
        check(notifications == 1, @"Repeated positive snapshots do not notify again");
        [options updateAdvancedModeEnabled:NO];
        check(!options.advancedModeEnabled && notifications == 2, @"Manual disable persists and notifies");
        options = [[DWGlobalOptions alloc] initWithUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:suite] defaults:nil];
        [options enableAdvancedModeForPlatformBalance:0 walletIdHex:@"a" network:@"testnet"];
        [options enableAdvancedModeForPlatformBalance:999999 walletIdHex:@"a" network:@"testnet"];
        check(!options.advancedModeEnabled && notifications == 2, @"New options instance, resync and refund respect manual disable");
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"a" network:@"mainnet"];
        check(options.advancedModeEnabled, @"Another network has independent first-funding history");
        [options updateAdvancedModeEnabled:NO];
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"b" network:@"testnet"];
        check(options.advancedModeEnabled, @"Another wallet has independent first-funding history");
        NSUInteger before = notifications;
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"c" network:@"testnet"];
        check(notifications == before, @"Already-enabled mode does not emit redundant notification");
        [options updateAdvancedModeEnabled:NO];
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"c" network:@"testnet"];
        check(!options.advancedModeEnabled, @"Already-enabled first funding still records history");
        [options clearAdvancedModeBalanceHistoryForWalletIdHex:@"b"];
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"a" network:@"testnet"];
        check(!options.advancedModeEnabled, @"Removing wallet B preserves wallet A history");
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"b" network:@"testnet"];
        check(options.advancedModeEnabled, @"Removed wallet can auto-enable after reimport");
        [options restoreToDefaults];
        check(!options.advancedModeEnabled, @"Full wipe resets advanced mode");
        [options enableAdvancedModeForPlatformBalance:1 walletIdHex:@"a" network:@"testnet"];
        check(options.advancedModeEnabled, @"Full wipe clears first-funding history");
        before = notifications;
        [options updateAdvancedModeEnabled:YES];
        check(notifications == before, @"Writing unchanged preference does not notify");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [defaults removePersistentDomainForName:suite];
        printf("%lu regression checks passed\n", (unsigned long)checks);
    }
    return 0;
}
