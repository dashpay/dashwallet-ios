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

/// Whether the launch-time wallet work still waits for the first activation;
/// nil until the scene connects.
@property (nullable, nonatomic, strong) DWLaunchDecision *launchDecision;

#if DEBUG && TARGET_OS_SIMULATOR && DASHPAY
/// Built in `didFinishLaunching`, shown by `installWindowInScene:` instead of the wallet UI.
@property (nullable, nonatomic, strong) UIViewController *recoveryFixture;
#endif

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
        self.recoveryFixture = recoveryFixture;
        return YES;
    }
    UIViewController *settingsFixture = [DWSettingsRowsUITestFixture makeViewControllerIfRequested];
    if (settingsFixture != nil) {
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.window.rootViewController = settingsFixture;
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

    // Nothing here decides whether a wallet exists. A launch in the
    // background (BGAppRefresh) happens on a locked device: the mnemonics are
    // unreadable, so "no wallet" would describe the lock, not the wallet, and
    // this process would later be brought to the foreground onto
    // Create/Recover over a funded wallet. Whether this launch is one is known
    // only when the scene connects (`installWindowInScene:`), and a
    // background launch may connect none. Until then lifecycle observers (the
    // sync monitor's connectivity kick, a network-change notification) may
    // ask the runtime to start; the runtime refuses them until
    // `startWalletServices`.
    [DWSwiftDashSDKWalletRuntime holdAutomaticStartsUntilLaunchDecision];

    // The window is created later, when the scene connects (`installWindowInScene:`).
    [self setupDashWalletComponentsWithOptions:launchOptions];

    return YES;
}

#pragma mark - Scene

- (void)installWindowInScene:(UIWindowScene *)scene {
#if DEBUG
#if TARGET_OS_SIMULATOR && DASHPAY
    if (self.recoveryFixture != nil) {
        self.window = [[UIWindow alloc] initWithWindowScene:scene];
        self.window.rootViewController = self.recoveryFixture;
        [self.window makeKeyAndVisible];
        return;
    }
#endif
    if ([NSProcessInfo.processInfo.environment[@"XCODE_RUNNING_FOR_PREVIEWS"] isEqualToString:@"1"]) {
        return;
    }
#endif /* DEBUG */

    self.window = [[DWWindow alloc] initWithWindowScene:scene];
    self.window.backgroundColor = [UIColor blackColor];

    // The first scene of the process decides the launch. One connected in
    // the background (or not yet attached) may belong to a background launch,
    // on a locked device: a neutral placeholder
    // is the root, and the key migration, the runtime start and the root
    // decision run once, on the first activation (`handleDidBecomeActive`),
    // which implies an unlocked device. One connected for the foreground runs
    // them here. A cold launch from the Home screen may also connect its
    // scene still unattached and is then decided at its activation, a moment
    // later. A scene reconnected later (the system discarded the first)
    // finds the launch already decided, or still waiting for its activation.
    BOOL decidesLaunch = (self.launchDecision == nil);
    if (decidesLaunch) {
        self.launchDecision = [[DWLaunchDecision alloc] initWithSceneActivationState:scene.activationState];
    }
    if (self.launchDecision.isDeferred) {
        DWLog(@"LAUNCH scene connected not in the foreground (activation state %ld); deferring key migration, runtime start and the root decision until the app becomes active",
              (long)scene.activationState);
        self.window.rootViewController = [self launchPlaceholderController];
    }
    else {
        if (decidesLaunch) {
            [self startWalletServices];
        }
        self.window.rootViewController = [[DWInitialViewController alloc] init];
    }
    [self.window makeKeyAndVisible];
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

/// The deferred half of a launch whose scene did not connect in the
/// foreground, once: start the wallet services and replace the placeholder
/// with the real root.
- (void)completeDeferredLaunchIfNeeded {
    if (![self.launchDecision takeAtActivation]) {
        return;
    }
    DWLog(@"LAUNCH first activation; running the deferred key migration, runtime start and root decision");
    [self startWalletServices];
    DWInitialViewController *controller = [[DWInitialViewController alloc] init];
    // The root presents the lock screen from its own become-active observer,
    // which this activation has already passed: mark it deferred, so it
    // performs that step on appearance (the same path a root installed
    // after onboarding takes).
    [controller setLaunchingAsDeferredController];
    self.window.rootViewController = controller;

    // A link that brought the process to the foreground arrived before this
    // root existed; hand it to the initial controller now. Not through
    // `handleOpenURL:`: its wallet gate reads presence at this
    // very moment, when the key migration was only just enqueued and an
    // upgrader's wallet has not landed, and would drop the link. The initial
    // controller keeps it until its root controller exists, and the root
    // controller until a wallet is presented and unlocked.
    NSURL *pendingURL = [self.launchDecision takePendingURL];
    if (pendingURL != nil) {
        DWLog(@"LAUNCH replaying a link kept during the deferred launch (scheme %@)", pendingURL.scheme);
        [self deliverReplayedURL:pendingURL toInitialController:controller];
    }
#if DASHPAY
    NSUserActivity *pendingActivity = [self.launchDecision takePendingUserActivity];
    NSURL *pendingActivityURL = pendingActivity.webpageURL;
    if (pendingActivityURL != nil) {
        DWLog(@"LAUNCH replaying a universal link kept during the deferred launch (host %@)", pendingActivityURL.host);
        [controller handleDeeplink:pendingActivityURL];
    }
#endif
}

/// The replayed link, routed as the handlers route a live one but without
/// the wallet gate (`DWURLParser.allowsURLHandling`), which cannot answer
/// yet; malformed links are still refused.
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

- (void)handleDidBecomeActive {
    //
    // THIS IS IMPORTANT!
    //
    // When adding any logic here mind the migration process
    //

    // A background launch decided nothing; the first activation runs the
    // launch-time wallet work (see `installWindowInScene:`).
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

- (void)handleUserActivity:(NSUserActivity *)userActivity {
#if DASHPAY
    // Universal links (invitations.dashpay.io applink). Firebase
    // Dynamic Links previously unwrapped these; the service was shut
    // down in 2025, so the invitation URL is now routed directly —
    // normalization/validation happens in the redeem flow
    // (DWInvitationLinkNormalizer + ClaimInvitationScreen).
    NSURL *url = userActivity.webpageURL;
    if (url == nil || ![DWInvitationLinkNormalizer isInvitationURL:url]) {
        return;
    }
    // Delivered while a background launch still waits for its activation:
    // kept, and replayed once the real root is installed.
    if ([self.launchDecision holdUserActivityIfPending:userActivity]) {
        DWLog(@"LAUNCH universal link kept until the deferred launch completes");
        return;
    }
    DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
    if ([controller isKindOfClass:DWInitialViewController.class]) {
        [controller handleDeeplink:url];
    }
#endif
}

- (void)handleOpenURL:(NSURL *)url {
    // Delivered while a background launch still waits for its activation:
    // kept, and replayed once the real root is installed.
    // Only the scheme is logged: an invitation link carries a bearer key.
    if ([self.launchDecision holdURLIfPending:url]) {
        DWLog(@"LAUNCH link kept until the deferred launch completes (scheme %@)", url.scheme);
        return;
    }
#if DASHPAY
    // dashpay://invite (and pasted-transport) invitation links open the
    // redeem flow; every other scheme falls through to DWURLParser.
    if ([DWInvitationLinkNormalizer isInvitationURL:url]) {
        DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
        if ([controller isKindOfClass:DWInitialViewController.class]) {
            [controller handleDeeplink:url];
        }
        return;
    }

    // Handle URL Scheme instead
#endif
    
    if (![DWURLParser allowsURLHandling]) {
        return;
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
        
        // The key window, not self.window: while the PIN lock window is up it is the key one.
        UIViewController *presentingController = [[UIApplication sharedApplication].keyWindow.rootViewController topController];
        [presentingController presentViewController:alert animated:YES completion:nil];
        
        return;
    }
    
    DWInitialViewController *controller = (DWInitialViewController *)self.window.rootViewController;
    if ([controller isKindOfClass:DWInitialViewController.class]) {
        [controller handleURL:url];
    }
    else {
        // TODO: defer action when start controller finish
        DWLog(@"Ignoring handle URL: %@. Root controller hasn't been set up yet", url);
    }
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
    // delegate (foreground presentation, tap routing, clearing). It must
    // exist before launch returns, so it reads the window lazily.
    __weak typeof(self) weakSelf = self;
    self.notifications = [[DWNotificationsBootstrap alloc] initWithWindowProvider:^UIWindow *_Nullable {
        return weakSelf.window;
    }];
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
