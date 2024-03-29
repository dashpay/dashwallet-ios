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

#import <DashSync/DashSync.h>
#import <DashSync/UIWindow+DSUtils.h>
#import <CloudInAppMessaging/CloudInAppMessaging.h>
#import <UserNotifications/UserNotifications.h>

@import Firebase;

#import "DWInitialViewController.h"
#import "DWDataMigrationManager.h"
#import "DWStartViewController.h"
#import "DWStartModel.h"
#import "DWVersionManager.h"
#import "DWWindow.h"
#import "DWURLParser.h"
#import "DWEnvironment.h"
#import "dashwallet-Swift.h"
#ifndef IGNORE_WATCH_TARGET
#import "DWPhoneWCSessionManager.h"
#endif /* IGNORE_WATCH_TARGET */

#if DASH_TESTNET
#pragma message "testnet build"
#endif /* DASH_TESTNET */

#if SNAPSHOT
#pragma message "snapshot build"
#endif /* SNAPSHOT */

#define FRESH_INSTALL 0

#if FRESH_INSTALL
#pragma message "Running app as fresh installed..."
#endif /* FRESH_INSTALL */

#if (FRESH_INSTALL && !DEBUG)
#error "Debug flag FRESH_INSTALL is active during Release build. Comment this out to continue."
#endif /* (FRESH_INSTALL && !DEBUG) */

#if DASHPAY
//NSNotificationName const DWDashPayAvailabilityStatusUpdatedNotification = @"DWDashPayAvailabilityStatusUpdatedNotification"; // TODO: check if needed
#endif
NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate () <DWStartViewControllerDelegate, UNUserNotificationCenterDelegate>

@property (nonatomic, strong) DWBalanceNotifier *balanceNotifier;

@end

@implementation AppDelegate

#pragma mark - Public

+ (AppDelegate *)appDelegate {
    return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

- (void)registerForPushNotifications {
    [self.balanceNotifier registerForPushNotifications];
}

#pragma mark - UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(nullable NSDictionary *)launchOptions {
#if FRESH_INSTALL
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    NSArray *secItemClasses = @[(__bridge id)kSecClassGenericPassword,
                                (__bridge id)kSecClassInternetPassword,
                                (__bridge id)kSecClassCertificate,
                                (__bridge id)kSecClassKey,
                                (__bridge id)kSecClassIdentity];
    for (id secItemClass in secItemClasses) {
        NSDictionary *spec = @{(__bridge id)kSecClass: secItemClass};
        SecItemDelete((__bridge CFDictionaryRef)spec);
    }
#endif /* FRESH_INSTALL */
    
#if DASHPAY
    [DWGlobalOptions sharedInstance].dpInvitationFlowEnabled = YES;
#endif
    
    [DSLogger sharedInstance];
    [FIRApp configure];
    [ExploreDashObjcWrapper configure];
    [CurrencyExchangerObjcWrapper startExchangeRateFetching];
    [CoinbaseObjcWrapper start];
    [CrowdNodeObjcWrapper start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dsApplicationTerminationRequestNotification:)
                                                 name:DSApplicationTerminationRequestNotification
                                               object:nil];
    
    [CLMCloudInAppMessaging setupWithCloudKitContainerIdentifier:@"iCloud.org.dash.dashwallet"];
    
    self.window = [[DWWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    
    [[DWVersionManager sharedInstance] migrateUserDefaults];
    [[DSAuthenticationManager sharedInstance] setOneTimeShouldUseAuthentication:YES];
    [[DashSync sharedSyncController] registerBackgroundFetchOnce];
    
    [[DatabaseConnection shared] migrateIfNeededAndReturnError:nil];
    
    DWDataMigrationManager *migrationManager = [DWDataMigrationManager sharedInstance];
    if (migrationManager.shouldMigrate) {
        [self performDeferredStartWithLaunchOptions:launchOptions];
    }
    else {
        [self performNormalStartWithLaunchOptions:launchOptions wasDeferred:NO];
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
    
    // Schedule background fetch if the wallet (DashSync) had been started
    DWDataMigrationManager *migrationManager = [DWDataMigrationManager sharedInstance];
    if (!migrationManager.shouldMigrate) {
        [[DashSync sharedSyncController] scheduleBackgroundFetch];
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    
    //
    // THIS IS IMPORTANT!
    //
    // When adding any logic here mind the migration process
    //
    [self.balanceNotifier updateBalance];
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

- (void)application:(UIApplication *)application
performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    [[DashSync sharedSyncController] performFetchWithCompletionHandler:completionHandler];
}

#if DASHPAY
- (BOOL)application:(UIApplication *)application continueUserActivity:(nonnull NSUserActivity *)userActivity restorationHandler:(nonnull void (^)(NSArray<id<UIUserActivityRestoring>> *_Nullable))restorationHandler {
    __weak typeof(self) weakSelf = self;
    BOOL handled = [[FIRDynamicLinks dynamicLinks] handleUniversalLink:userActivity.webpageURL
                                                            completion:^(FIRDynamicLink * _Nullable dynamicLink,
                                                                         NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (dynamicLink.url) {
            DWInitialViewController *controller = (DWInitialViewController *)strongSelf.window.rootViewController;
            if ([controller isKindOfClass:DWInitialViewController.class]) {
                [controller handleDeeplink:dynamicLink.url];
            }
        }
    }];
    return handled;
}
#endif

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    DWStartViewController *startController = (DWStartViewController *)self.window.rootViewController;
    if ([startController isKindOfClass:DWStartViewController.class]) {
        startController.deferredURLToProcess = url;
        return NO;
    }
    
#if DASHPAY
    FIRDynamicLink *dynamicLink = [[FIRDynamicLinks dynamicLinks] dynamicLinkFromCustomSchemeURL:url];
    if (dynamicLink) {
        if (dynamicLink.url) {
            DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
            if ([controller isKindOfClass:DWInitialViewController.class]) {
                [controller handleDeeplink:dynamicLink.url];
            }
        }
        return YES;
    }
    
    // Handle URL Scheme instead
#endif
    
    if (![DWURLParser allowsURLHandling]) {
        return NO;
    }
    
    if ([DWURLParser shouldIgnoreURL:url]) {
        return NO;
    }
    
    if (![DWURLParser canHandleURL:url]) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"Not a Dash URL", nil)
                                     message:url.absoluteString
                                     preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* okAction = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"OK", nil)
                                       style:UIAlertActionStyleCancel
                                       handler:nil];

        [alert addAction:okAction];
        
        UIViewController *presentingController = [application.keyWindow ds_presentingViewController];
        [presentingController presentViewController:alert animated:YES completion:nil];
        
        return NO;
    }
    
    DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
    if ([controller isKindOfClass:DWInitialViewController.class]) {
        [controller handleURL:url];
    }
    else {
        // TODO: defer action when start controller finish
        DSLog(@"Ignoring handle URL: %@. Root controller hasn't been set up yet", url);
    }

    return YES;
}

#pragma mark - Private

- (void)performDeferredStartWithLaunchOptions:(NSDictionary *)launchOptions {
    DWStartModel *viewModel = [[DWStartModel alloc] initWithLaunchOptions:launchOptions];
    DWStartViewController *controller = [DWStartViewController controller];
    controller.viewModel = viewModel;
    controller.delegate = self;
    
    self.window.rootViewController = controller;
}

- (void)performNormalStartWithLaunchOptions:(NSDictionary *)launchOptions wasDeferred:(BOOL)wasDeferred {
    DWInitialViewController *controller = [[DWInitialViewController alloc] init];
    if (wasDeferred) {
        [controller setLaunchingAsDeferredController];
    }
    self.window.rootViewController = controller;
    
    [self setupDashWalletComponentsWithOptions:launchOptions];
}

- (void)setupDashWalletComponentsWithOptions:(NSDictionary *)launchOptions {
    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
        NSData *file = [NSData dataWithContentsOfURL:launchOptions[UIApplicationLaunchOptionsURLKey]];

        if (file.length > 0) {
            DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
            if ([controller isKindOfClass:DWInitialViewController.class]) {
                [controller handleFile:file];
            }
            else {
                // TODO: defer action when start controller finish
                DSLog(@"Ignoring handle file. Root controller hasn't been set up yet");
            }
        }
    }
    
    [[DashSync sharedSyncController] setupDashSyncOnce];
    
    [DWEnvironment sharedInstance]; //starts up the environment, this is needed here
    
#if FRESH_INSTALL
    // TODO: fix. Disabled due to crashing :(
//    [[DashSync sharedSyncController] wipeBlockchainDataForChain:[DWEnvironment sharedInstance].currentChain];
#endif /* FRESH_INSTALL */
    
    [[DSOptionsManager sharedInstance] setSyncType:DSSyncType_Default];
    
    // TODO_outdated: bitcoin protocol/payment protocol over multipeer connectivity
    
    // TODO_outdated: accessibility for the visually impaired
    
    // TODO_outdated: fast wallet restore using webservice and/or utxo p2p message
    
    // TODO_outdated: ask user if they need to sweep to a new wallet when restoring because it was compromised
    
    // TODO_outdated: figure out deterministic builds/removing app sigs: http://www.afp548.com/2012/06/05/re-signining-ios-apps/
    
    // TODO_outdated: implement importing of private keys split with shamir's secret sharing:
    //      https://github.com/cetuscetus/btctool/blob/bip/bip-xxxx.mediawiki

#ifndef IGNORE_WATCH_TARGET
    [DWPhoneWCSessionManager sharedInstance];
#endif
    
    [DSShapeshiftManager sharedInstance];

    self.balanceNotifier = [[DWBalanceNotifier alloc] init];
    [self.balanceNotifier setupNotifications];

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    
    if ([notification.request.identifier isEqual: CrowdNodeObjcWrapper.notificationID]) {
        completionHandler(UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void(^)(void))completionHandler {

    if ([response.notification.request.identifier isEqual: CrowdNodeObjcWrapper.notificationID]) {
        if (SyncingActivityMonitor.shared.state == SyncingActivityMonitorStateSyncDone) {
            UIViewController *vc = [CrowdNodeModelObjcWrapper getRootVC];
            [_window.rootViewController presentViewController:vc animated:YES completion:nil];
        }
        completionHandler();
    }
}

#pragma mark - DWStartViewControllerDelegate

- (void)startViewController:(DWStartViewController *)controller didFinishWithDeferredLaunchOptions:(NSDictionary *)launchOptions shouldRescanBlockchain:(BOOL)shouldRescanBlockchain {
    [self performNormalStartWithLaunchOptions:launchOptions wasDeferred:YES];
    
    if (shouldRescanBlockchain) {
        DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
        [chainManager masternodeListAndBlocksRescan];
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
