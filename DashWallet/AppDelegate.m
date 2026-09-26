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

#import <CloudInAppMessaging/CloudInAppMessaging.h>

@import Firebase;

#import "DWInitialViewController.h"
#import "DWVersionManager.h"
#import "UIColor+DWStyle.h"
#import "DWWindow.h"
#import "DWURLParser.h"
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

@interface AppDelegate ()

/// The notifications composition root: store, permission coordinator,
/// dispatcher, lifecycle (the UNUserNotificationCenter delegate), router,
/// and the transaction producer.
@property (nonatomic, strong) DWNotificationsBootstrap *notifications;

/// Whether the launch-time wallet work still waits for the first activation.
@property (nonatomic, strong) DWLaunchDecision *launchDecision;

@end

@implementation AppDelegate

#pragma mark - Public

+ (AppDelegate *)appDelegate {
    return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

- (void)registerForPushNotifications {
    [self.notifications registerForPushNotifications];
}

#pragma mark - UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(nullable NSDictionary *)launchOptions {
#if DEBUG
#if TARGET_OS_SIMULATOR && DASHPAY
    UIViewController *recoveryFixture = [DWUsernameRecoveryUITestFixture makeViewControllerIfRequested];
    if (recoveryFixture != nil) {
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.window.rootViewController = recoveryFixture;
        [self.window makeKeyAndVisible];
        return YES;
    }
#endif
    if ([NSProcessInfo.processInfo.environment[@"XCODE_RUNNING_FOR_PREVIEWS"] isEqualToString:@"1"]) {
        return YES;
    }
#endif /* DEBUG */

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
    
    // Shortcut customization banner state machine
    DWGlobalOptions *bannerOptions = [DWGlobalOptions sharedInstance];
    if (bannerOptions.shortcutBannerState == 0) {
        if (bannerOptions.shouldDisplayOnboarding) {
            // New install — defer banner to second app open
            bannerOptions.shortcutBannerState = 1;
        } else {
            // Update from prior version — show on this open
            bannerOptions.shortcutBannerState = 2;
        }
    } else if (bannerOptions.shortcutBannerState == 1) {
        // New install, second+ launch — ready to show
        bannerOptions.shortcutBannerState = 2;
    }

    [DWLogger sharedInstance];
#if DEBUG
    // Etap-C diagnostic: logs main-runloop stalls >=250ms through DWLogger
    // so hangs can be attributed to bootstrap stages by timestamp.
    [DWMainThreadStallMonitor start];
#endif /* DEBUG */
    [FIRApp configure];
    [ExploreDashObjcWrapper configure];
    [CurrencyExchangerObjcWrapper startExchangeRateFetching];
    [CoinbaseObjcWrapper start];
    [CrowdNodeObjcWrapper start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationTerminationRequestNotification:)
                                                 name:DWApp.applicationTerminationRequestNotification
                                               object:nil];
    
    [CLMCloudInAppMessaging setupWithCloudKitContainerIdentifier:@"iCloud.org.dash.dashwallet"];
    
    self.window = [[DWWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    
    [[DWVersionManager sharedInstance] migrateUserDefaults];
    [[DWAuthenticationService shared] enableAuthenticationIfNeeded];
#ifdef DEBUG
    // QA fixture: fabricate the wallet-without-PIN keychain state (partial
    // restore / interrupted setup) to exercise the lock screen's Set PIN
    // routing. No-op unless QA_DROP_PIN_RECORDS=1 is in the environment.
    [DWAuthenticationService debugDropPinRecordsIfRequested];
#endif

    // Advance the PIN-lockout clock to the wall clock at every launch, so a
    // lockout keeps elapsing even fully offline (Bug #2 — DashSync's own
    // secure-time feed died with the M6 freeze; HTTP responses re-feed it
    // continuously via HTTPClient).
    [[DWSecureTimeService shared] ratchetToWallClock];

    NSError *databaseMigrationError = nil;
    if (![[DatabaseConnection shared] migrateIfNeededAndReturnError:&databaseMigrationError]) {
        DWLog(@"Database migration failed: %@", databaseMigrationError);
    }

    // After migrateIfNeeded: the tracking service reads `swap_orders` as soon as it starts,
    // so on a fresh install it must not race the migration that creates the table.
    [SwapTrackingServiceObjcWrapper start];

#ifdef DEBUG
    // QA fixture: fabricate DashSync's legacy keychain layout when either
    // LEGACY_KEYCHAIN_MNEMONIC or LEGACY_KEYCHAIN_INVALID=1 is set in the
    // environment (simulator upgrade-path testing). No-op otherwise;
    // DEBUG builds only.
    [DWSwiftDashSDKKeyMigrator debugInstallLegacyFixtureIfRequested];
#endif
    [DWSwiftDashSDKWalletRuntime startObservingNetworkChanges];

    // A launch in the background (BGAppRefresh) happens on a locked device:
    // the mnemonics are unreadable, so "no wallet" would describe the lock,
    // not the wallet, and this process would later be brought to the
    // foreground onto Create/Recover over a funded wallet. Decide nothing
    // now: a neutral placeholder is the root, and the key migration, the
    // runtime start and the root decision run once, on the first activation
    // (`applicationDidBecomeActive:`), which implies an unlocked device. A
    // foreground launch runs them here, as before.
    self.launchDecision = [[DWLaunchDecision alloc] initWithApplicationState:application.applicationState];
    if (self.launchDecision.isDeferred) {
        DWLog(@"LAUNCH background launch; deferring key migration, runtime start and the root decision until the app becomes active");
        // Lifecycle observers (the sync monitor's connectivity kick, a
        // network-change notification) may ask the runtime to start before
        // the activation; the runtime refuses them until `startWalletServices`.
        [DWSwiftDashSDKWalletRuntime holdAutomaticStartsUntilLaunchDecision];
        self.window.rootViewController = [self launchPlaceholderController];
    }
    else {
        [self startWalletServices];
        DWInitialViewController *controller = [[DWInitialViewController alloc] init];
        self.window.rootViewController = controller;
    }
    [self setupDashWalletComponentsWithOptions:launchOptions];

    NSParameterAssert(self.window.rootViewController);

    [self.window makeKeyAndVisible];

    return YES;
}

/// Kick off the SwiftDashSDK key migration and app-owned runtime. The
/// runtime wallet is restored from app-owned Keychain state, not from a
/// SwiftData wallet store.
- (void)startWalletServices {
    [DWSwiftDashSDKWalletRuntime releaseAutomaticStartsForLaunchDecision];
    [DWSwiftDashSDKKeyMigrator migrateIfNeeded];
    [DWSwiftDashSDKWalletRuntime startIfReady];
}

/// The launch screen, shown while a background launch waits for its first
/// activation: it decides nothing and reads nothing.
- (UIViewController *)launchPlaceholderController {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LaunchScreen" bundle:nil];
    UIViewController *controller = [storyboard instantiateInitialViewController];
    if (controller == nil) {
        controller = [[UIViewController alloc] init];
        controller.view.backgroundColor = [UIColor dw_backgroundColor];
    }
    return controller;
}

/// The deferred half of a background launch, once: start the wallet
/// services and replace the placeholder with the real root.
- (void)completeDeferredLaunchIfNeeded {
    if (![self.launchDecision takeAtActivation]) {
        return;
    }
    DWLog(@"LAUNCH app active after a background launch; running the deferred key migration, runtime start and root decision");
    [self startWalletServices];
    DWInitialViewController *controller = [[DWInitialViewController alloc] init];
    // The root presents the lock screen from its own become-active observer,
    // which this activation has already passed: mark it deferred, so it
    // performs that step on appearance (the same path a root installed
    // after onboarding takes).
    [controller setLaunchingAsDeferredController];
    self.window.rootViewController = controller;

    // The links that brought the process to the foreground arrived before
    // this root existed; hand them to the initial controller now, in order.
    // The initial controller keeps them until its root controller exists,
    // and the root controller's queue until a wallet is presented and
    // unlocked.
    for (NSURL *url in [self.launchDecision takePendingLinks]) {
        DWLog(@"LAUNCH replaying a link kept during the deferred launch (scheme %@)", url.scheme);
        [self deliverReplayedURL:url toInitialController:controller];
    }
}

/// The replayed link, routed as the handlers route a live one: an invitation
/// to the invitation entry, anything else through the URL parser's check —
/// malformed links are refused.
- (void)deliverReplayedURL:(NSURL *)url toInitialController:(DWInitialViewController *)controller {
#if DASHPAY
    if ([DWInvitationLinkNormalizer isInvitationURL:url]) {
        [controller handleDeeplink:url];
        return;
    }
#endif
    if (![DWURLParser canHandleURL:url]) {
        DWLog(@"LAUNCH replayed link is not a Dash URL (scheme %@); dropped", url.scheme);
        return;
    }
    [controller handleURL:url];
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

    //
    // THIS IS IMPORTANT!
    //
    // When adding any logic here mind the migration process
    //

    // A background launch decided nothing; the first activation runs the
    // launch-time wallet work (see `didFinishLaunching`).
    [self completeDeferredLaunchIfNeeded];

    // Badge reset and delivered-notification clearing live in
    // DWNotificationsBootstrap's NotificationLifecycle, which observes
    // UIApplicationDidBecomeActiveNotification itself.

    // Check geo-restriction for PiggyCards (if available)
    // This logs location info each time the app becomes active for debugging
    SEL checkGeoRestrictionSelector = NSSelectorFromString(@"checkGeoRestriction");
    if ([ExploreDashObjcWrapper respondsToSelector:checkGeoRestrictionSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [ExploreDashObjcWrapper performSelector:checkGeoRestrictionSelector];
#pragma clang diagnostic pop
    }
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

#if DASHPAY
- (BOOL)application:(UIApplication *)application continueUserActivity:(nonnull NSUserActivity *)userActivity restorationHandler:(nonnull void (^)(NSArray<id<UIUserActivityRestoring>> *_Nullable))restorationHandler {
    // Universal links (invitations.dashpay.io applink). Firebase
    // Dynamic Links previously unwrapped these; the service was shut
    // down in 2025, so the invitation URL is now routed directly —
    // normalization/validation happens in the redeem flow
    // (DWInvitationLinkNormalizer + ClaimInvitationScreen).
    NSURL *url = userActivity.webpageURL;
    if (url == nil || ![DWInvitationLinkNormalizer isInvitationURL:url]) {
        return NO;
    }
    // Delivered while a background launch still waits for its activation:
    // kept, and replayed once the real root is installed.
    if ([self.launchDecision holdUserActivityIfPending:userActivity]) {
        DWLog(@"LAUNCH universal link kept until the deferred launch completes");
        return YES;
    }
    DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
    if ([controller isKindOfClass:DWInitialViewController.class]) {
        [controller handleDeeplink:url];
        return YES;
    }
    return NO;
}
#endif

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    // Delivered while a background launch still waits for its activation:
    // kept, and replayed through this method once the real root is installed.
    // Only the scheme is logged: an invitation link carries a bearer key.
    if ([self.launchDecision holdURLIfPending:url]) {
        DWLog(@"LAUNCH link kept until the deferred launch completes (scheme %@)", url.scheme);
        return YES;
    }
#if DASHPAY
    // dashpay://invite (and pasted-transport) invitation links open the
    // redeem flow; every other scheme falls through to DWURLParser.
    if ([DWInvitationLinkNormalizer isInvitationURL:url]) {
        DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
        if ([controller isKindOfClass:DWInitialViewController.class]) {
            [controller handleDeeplink:url];
        }
        return YES;
    }

    // Handle URL Scheme instead
#endif

    // No gate on a present wallet here: a link that arrives while the
    // launch hold is still migrating (or its card is up), or while setup
    // is on screen, waits in the root controller's queue until a wallet is
    // presented, and in the initial controller until the root exists.
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
        
        UIViewController *presentingController = [application.keyWindow.rootViewController topController];
        [presentingController presentViewController:alert animated:YES completion:nil];
        
        return NO;
    }
    
    DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
    if ([controller isKindOfClass:DWInitialViewController.class]) {
        [controller handleURL:url];
    }
    else {
        // TODO: defer action when start controller finish
        DWLog(@"Ignoring handle URL: %@. Root controller hasn't been set up yet", url);
    }

    return YES;
}

#pragma mark - Private

- (void)setupDashWalletComponentsWithOptions:(NSDictionary *)launchOptions {
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

    // The notifications composition root: builds the module graph and
    // installs NotificationLifecycle as the UNUserNotificationCenter
    // delegate (foreground presentation, tap routing, clearing).
    self.notifications = [[DWNotificationsBootstrap alloc] initWithWindow:self.window];
}

#pragma mark - Notifications

- (void)applicationTerminationRequestNotification:(NSNotification *)sender {
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication); // force NSUserDefaults to save
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

@end

NS_ASSUME_NONNULL_END
