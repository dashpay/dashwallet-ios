//  
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "AppDelegate.h"

#import <UserNotifications/UserNotifications.h>
#import "DWRootNavigationController.h"
#import <DashSync/DashSync.h>
#import "DWDataMigrationManager.h"
#import "DWStartViewController.h"
#import "DWStartModel.h"
#import "DWCrashReporter.h"

// TODO: re-enable Watch App
//#ifndef IGNORE_WATCH_TARGET
//#import "DWPhoneWCSessionManager.h"
//#endif /* IGNORE_WATCH_TARGET */

#if DASH_TESTNET
#pragma message "testnet build"
#endif /* DASH_TESTNET */

#if SNAPSHOT
#pragma message "snapshot build"
#endif /* SNAPSHOT */

#define FRESH_INSTALL 0

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate () <DWStartViewControllerDelegate>

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(nullable NSDictionary *)launchOptions {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dsApplicationTerminationRequestNotification:)
                                                 name:DSApplicationTerminationRequestNotification
                                               object:nil];
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    
    [[DSAuthenticationManager sharedInstance] setOneTimeShouldUseAuthentication:YES];
    
    DWCrashReporter *crashReporter = [DWCrashReporter sharedInstance];
    DWDataMigrationManager *migrationManager = [DWDataMigrationManager sharedInstance];
    if (migrationManager.shouldMigrate || crashReporter.shouldHandleCrashReports) {
        // start updating prices earlier than migration to update `secureTime`
        // otherwise, `startExchangeRateFetching` will be performed within DashSync initialization process
        if (migrationManager.shouldMigrate) {
            [[DSPriceManager sharedInstance] startExchangeRateFetching];
        }
        
        [self performDeferredStartWithLaunchOptions:launchOptions];
    }
    else {
        [self performNormalStartWithLaunchOptions:launchOptions];
    }
    
    NSParameterAssert(self.window.rootViewController);
    
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

// Applications may reject specific types of extensions based on the extension point identifier.
// Constants representing common extension point identifiers are provided further down.
// If unimplemented, the default behavior is to allow the extension point identifier.
- (BOOL)application:(UIApplication *)application shouldAllowExtensionPointIdentifier:(NSString *)extensionPointIdentifier {
    return NO; // disable extensions such as custom keyboards for security purposes
}

// TODO: register for notifications when appropriate
- (void)registerForPushNotifications {
    UNAuthorizationOptions options = (UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert);
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error) {
        
    }];
}

#pragma mark - Private

- (void)performDeferredStartWithLaunchOptions:(NSDictionary *)launchOptions {
    DWStartModel *viewModel = [[DWStartModel alloc] initWithLaunchOptions:launchOptions];
    DWStartViewController *controller = [DWStartViewController controller];
    controller.viewModel = viewModel;
    controller.delegate = self;
    
    self.window.rootViewController = controller;
}

- (void)performNormalStartWithLaunchOptions:(NSDictionary *)launchOptions {
    [[DWCrashReporter sharedInstance] enableCrashReporter];
    
    DWRootNavigationController *rootController = [[DWRootNavigationController alloc] init];
    self.window.rootViewController = rootController;
    
    [self setupDashWalletComponentsWithOptions:launchOptions];
}

- (void)setupDashWalletComponentsWithOptions:(NSDictionary *)launchOptions {
    // TODO: impl
//    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
//        NSData *file = [NSData dataWithContentsOfURL:launchOptions[UIApplicationLaunchOptionsURLKey]];
//
//        if (file.length > 0) {
//            [[NSNotificationCenter defaultCenter] postNotificationName:BRFileNotification object:nil
//                                                              userInfo:@{@"file":file}];
//        }
//    }
    
    [DashSync sharedSyncController];
    
    [DWEnvironment sharedInstance]; //starts up the environment, this is needed here
    
#if FRESH_INSTALL
    [[DashSync sharedSyncController] wipeBlockchainDataForChain:[DWEnvironment sharedInstance].currentChain];
#endif
    
    [[DSOptionsManager sharedInstance] setSyncType:DSSyncType_Default];
    
    // TODO_outdated: bitcoin protocol/payment protocol over multipeer connectivity
    
    // TODO_outdated: accessibility for the visually impaired
    
    // TODO_outdated: fast wallet restore using webservice and/or utxo p2p message
    
    // TODO_outdated: ask user if they need to sweep to a new wallet when restoring because it was compromised
    
    // TODO_outdated: figure out deterministic builds/removing app sigs: http://www.afp548.com/2012/06/05/re-signining-ios-apps/
    
    // TODO_outdated: implement importing of private keys split with shamir's secret sharing:
    //      https://github.com/cetuscetus/btctool/blob/bip/bip-xxxx.mediawiki

    // TODO: Watch App
//#ifndef IGNORE_WATCH_TARGET
//    [DWPhoneWCSessionManager sharedInstance];
//#endif
    
    [DSShapeshiftManager sharedInstance];

    // TODO: notifications
    // observe balance and create notifications
//    [self setupBalanceNotification:[UIApplication sharedApplication]];
//    [self setupPreferenceDefaults];
}

#pragma mark - DWStartViewControllerDelegate

- (void)startViewController:(DWStartViewController *)controller didFinishWithDeferredLaunchOptions:(NSDictionary *)launchOptions shouldRescanBlockchain:(BOOL)shouldRescanBlockchain {
    [self performNormalStartWithLaunchOptions:launchOptions];
    
    if (shouldRescanBlockchain) {
        DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
        [chainManager rescan];
    }
}

#pragma mark - Notifications

- (void)dsApplicationTerminationRequestNotification:(NSNotification *)sender {
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication); // force NSUserDefaults to save
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

@end

NS_ASSUME_NONNULL_END
