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

#import "DWAppRootViewController.h"

#import "DWLockScreenViewController.h"
#import "DWRootModel.h"
#import "DWSetupViewController.h"
#import "DWUIKit.h"
#import "DWURLParser.h"
#import "DWURLRequestHandler.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWAppDidUnlockNotification = @"DWAppDidUnlockNotification";

static NSTimeInterval const UNLOCK_ANIMATION_DURATION = 0.25;

@interface DWAppRootViewController () <DWSetupViewControllerDelegate,
                                       DWWipeDelegate,
                                       DWLockScreenViewControllerDelegate,
                                       SyncingActivityMonitorObserver>

@property (readonly, nonatomic, strong) id<DWRootProtocol> model;

@property (null_resettable, nonatomic, strong) MainTabbarController *mainController;

@property (nullable, nonatomic, strong) UIImageView *overlayImageView;
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nullable, nonatomic, weak) DWLockScreenViewController *lockController;
@property (nullable, nonatomic, weak) UIViewController *displayedLockNavigationController;

/// Every deep link the app accepted and has not handled yet, in arrival
/// order; handed over one at a time by `dispatchNextLinkIfReady`.
@property (nonatomic, strong) DWDeepLinkQueue *linkQueue;
@property (nonatomic, assign) BOOL walletWipeInProgress;
/// The launch hold (legacy migration, or an unreadable inventory) has not
/// reported yet: "no wallet" is not a verdict, so nothing is handed over.
@property (nonatomic, assign) BOOL launchHoldPending;

- (void)beginWipeWalletWithAuthorization:(DWSwiftDashSDKWalletWipeAuthorization)authorization;
- (void)presentWalletWipeFailureForAuthorization:(DWSwiftDashSDKWalletWipeAuthorization)authorization;

@property (nonatomic, assign) BOOL launchingWasDeferred;

@end

@implementation DWAppRootViewController

- (instancetype)init {
    return [self initWithModel:[[DWRootModel alloc] init]];
}

- (instancetype)initWithModel:(id<DWRootProtocol>)model {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = model;
        _linkQueue = [[DWDeepLinkQueue alloc] init];
    }
    return self;
}

#pragma mark - Public

+ (Class)mainControllerClass {
    return [MainTabbarController class];
}

- (void)setLaunchingAsDeferredController {
    self.launchingWasDeferred = YES;
}

#if DASHPAY
- (void)handleDeeplink:(NSURL *)url {
    [self handleURL:url];
}
#endif

/// Every link enters here — a live one from the app delegate, one replayed
/// after a deferred launch, one the initial controller kept until this
/// controller existed — and joins the queue; it is handled when the app can
/// act on it and every earlier link has had its screen.
- (void)handleURL:(NSURL *)url {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    DWDeepLink *link = [[DWDeepLink alloc] initWithURL:url isUnsupported:[DWURLParser actionForURL:url] == nil];
    const DWDeepLinkAdmission admission = [self.linkQueue enqueue:link];
    NSString *kind = link.isInvitation ? @"an invitation" : @"a url";
    switch (admission) {
        case DWDeepLinkAdmissionQueued:
            DWLog(@"LINKS queued %@ (%lu pending)", kind, (unsigned long)self.linkQueue.pending.count);
            break;
        case DWDeepLinkAdmissionQueuedEvictingOldest:
            DWLog(@"LINKS queued %@; the oldest pending link was dropped (%lu kept)", kind, (unsigned long)self.linkQueue.pending.count);
            break;
        case DWDeepLinkAdmissionDroppedDuplicate:
            DWLog(@"LINKS dropped %@: the same link was queued just before", kind);
            return;
        case DWDeepLinkAdmissionDroppedUnsupportedCoalesced:
            DWLog(@"LINKS dropped an unsupported url: one is already pending");
            return;
    }
    [self dispatchNextLinkIfReady];
}

/// The one rule for handing a link over: the wallet is on screen, the device
/// is unlocked (no lock screen due, none displayed), the launch hold is not
/// pending and no earlier link is still presenting. Called wherever one of
/// those changes — a link arrives, the wallet is presented, the unlock
/// completes, setup finishes, a link's screen settles.
- (void)dispatchNextLinkIfReady {
    const BOOL walletPresented = _mainController != nil && self.currentController == _mainController;
    // A screen presented from a hierarchy that is not in a window yet — this
    // controller created but not attached, or the main controller's view
    // not yet added — never completes its presentation, so nothing is
    // handed over until both are attached (`viewDidAppear` asks again).
    const BOOL attached = self.viewIfLoaded.window != nil && _mainController.viewIfLoaded.window != nil;
    const BOOL unlocked = ![self.model shouldShowLockScreen] && self.lockController == nil;
    const BOOL invitationsReady = walletPresented && _mainController.isReadyForInvitations;
    DWDeepLink *link = [self.linkQueue takeNextWithWalletPresented:walletPresented
                                                          attached:attached
                                                          unlocked:unlocked
                                                 launchHoldPending:self.launchHoldPending
                                                  invitationsReady:invitationsReady];
    if (link == nil) {
        if (!self.linkQueue.isEmpty && !self.linkQueue.isDispatching) {
            DWLog(@"LINKS %lu link(s) kept: wallet presented %d, attached %d, unlocked %d, launch hold pending %d, invitations ready %d",
                  (unsigned long)self.linkQueue.pending.count, walletPresented, attached, unlocked, self.launchHoldPending, invitationsReady);
        }
        return;
    }

    const NSInteger token = self.linkQueue.dispatchToken;
    DWLog(@"LINKS handling %@ (%lu more pending)", link.isInvitation ? @"an invitation" : @"a url",
          (unsigned long)self.linkQueue.pending.count);
    __weak typeof(self) weakSelf = self;
    void (^done)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf.linkQueue dispatchDidFinishWithToken:token]) {
            DWLog(@"LINKS a link's handler reported after the queue had moved on; ignored");
            return;
        }
        [strongSelf dispatchNextLinkIfReady];
    };
    [self armLinkWatchdogForToken:token];
    if (link.isInvitation) {
#if DASHPAY
        [self.mainController handleDeeplink:link.url
                            definedUsername:nil
                                 completion:done];
#else
        done();
#endif
        return;
    }
    [self performURL:link.url completion:done];
}

/// A handler whose completion never comes — a screen presented from a
/// hierarchy that was detached after all, a flow torn down mid-way — must
/// not hold the queue forever. Fifteen seconds after a hand-over, if that
/// dispatch is still in flight and nothing is presented or animating, the
/// dispatch is ended here and the queue asked again; while something is on
/// screen the check is repeated. A late report from the handler is then
/// ignored (its token no longer matches).
- (void)armLinkWatchdogForToken:(NSInteger)token {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || !strongSelf.linkQueue.isDispatching || strongSelf.linkQueue.dispatchToken != token) {
            return;
        }
        const BOOL busy = strongSelf.view.window.rootViewController.presentedViewController != nil ||
                          strongSelf.transitionCoordinator != nil;
        if (busy) {
            [strongSelf armLinkWatchdogForToken:token];
            return;
        }
        DWLog(@"LINKS no screen appeared for the link handed over 15 s ago; releasing the queue");
        [strongSelf.linkQueue dispatchDidFinishWithToken:token];
        [strongSelf dispatchNextLinkIfReady];
    });
}

/// Perform a non-invitation link's action; `completion` runs once the
/// handler is done presenting: its screen has finished its transition, its
/// preparation ended without one (cancelled, failed), or the authentication
/// it asked for resolved.
- (void)performURL:(NSURL *)url completion:(void (^)(void))completion {
    DWURLAction *action = [DWURLParser actionForURL:url];
    if (!action) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"Unsupported URL", nil)
                             message:url.absoluteString
                      preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"OK", nil)
                      style:UIAlertActionStyleCancel
                    handler:^(UIAlertAction *action) {
                        completion();
                    }];

        [alert addAction:okAction];

        UIApplication *application = [UIApplication sharedApplication];
        UIViewController *presentingController = [application.keyWindow.rootViewController topController];
        [presentingController presentViewController:alert animated:YES completion:nil];

        return;
    }

    if ([action isKindOfClass:DWURLScanQRAction.class]) {
        [self.mainController performScanQRCodeActionWithCompletion:completion];
    }
    else if ([action isKindOfClass:DWURLIntegrationAction.class]) {
        NSURL *url = [(DWURLIntegrationAction *)action url];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSNotification.authURLReceived object:url];
        completion();
    }
    else if ([action isKindOfClass:DWURLRequestAction.class]) {
        [DWURLRequestHandler handleURLRequest:(DWURLRequestAction *)action completion:completion];
    }
    else if ([action isKindOfClass:DWURLPayAction.class]) {
        NSURL *paymentURL = [(DWURLPayAction *)action paymentURL];
        [self.mainController performPayTo:paymentURL completion:completion];
    }
    else if ([action isKindOfClass:DWURLDashConnectAction.class]) {
        [self.mainController openDashConnect:[(DWURLDashConnectAction *)action uri] completion:completion];
    }
    else {
        NSAssert(NO, @"Unhandled action", action);
        completion();
    }
}

- (void)openPaymentsScreen {
    // This method is used to simulate user action in onboarding
    // Root controller configured to be non-lockable, so these controllers should be nil
    NSAssert(self.lockController == nil, @"Inconsistent state");
    NSAssert(self.displayedLockNavigationController == nil, @"Inconsistent state");
    NSAssert([self.model shouldShowLockScreen] == NO, @"Iconsistent state");

    [self.mainController openPaymentsScreen];
}

- (void)closePaymentsScreen {
    // This method is used to simulate user action in onboarding
    // Root controller configured to be non-lockable, so these controllers should be nil
    NSAssert(self.lockController == nil, @"Inconsistent state");
    NSAssert(self.displayedLockNavigationController == nil, @"Inconsistent state");
    NSAssert([self.model shouldShowLockScreen] == NO, @"Iconsistent state");

    [self.mainController closePaymentsScreen];
}

#pragma mark - Life Cycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

    const CGRect screenBounds = [UIScreen mainScreen].bounds;
    UIWindow *lockWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    lockWindow.backgroundColor = [UIColor blackColor];
    lockWindow.windowLevel = UIWindowLevelNormal;
    [DWWalletLifecycleOverlayBridge setLockScreenVisible:[self.model shouldShowLockScreen]];
    self.lockWindow = lockWindow;

    // Display main controller initially if there is a wallet and lock screen is disabled
    // Otherwise main controller will be set as current in `lockScreenViewControllerDidUnlock:`
    //
    // One keychain read for the whole decision, so the wallet verdict and
    // the hold verdict below cannot come from two different reads.
    const DWWalletPresence walletPresence = self.model.walletPresence;
    const BOOL hasAWallet = walletPresence == DWWalletPresencePresent;
    UIViewController *controller = nil;
    if (hasAWallet) {
        if (![self.model shouldShowLockScreen]) {
            controller = [self mainController];
        }
    }
    // A DashSync-era wallet in the keychain with the async key migrator
    // still running means "no wallet" is a lie about to become true.
    // Deciding now would show Create/Recover to an upgrading user whose
    // wallet is milliseconds from appearing — and route their typed
    // phrase into the recover screen's wipe branch. Hand the launch to the
    // migration hold: it keeps the launch background, shows progress and a
    // blocking Try Again card on failure, and calls back only once a wallet
    // is present or there is nothing to migrate. Setup is never offered
    // while the old wallet is still in the keychain.
    //
    // An inventory that cannot be read is handed to the same hold: "no
    // wallet" would describe the keychain failure, not the wallet, and the
    // hold's card offers Try Again instead of Create/Recover over a wallet
    // the read missed.
    const BOOL keyMigrationPending =
        !hasAWallet && (walletPresence == DWWalletPresenceUnknown ||
                        [DWSwiftDashSDKKeyMigrator legacyWalletMaterialPendingMigration]);
    if (!hasAWallet && !keyMigrationPending) {
        controller = [self setupController];
    }

    if (controller) {
        [self transitionToController:controller];
    }

    self.launchHoldPending = keyMigrationPending;
    if (keyMigrationPending) {
        __weak typeof(self) weakSelf = self;
        [DWLegacyWalletMigrationLaunchHold beginWithCompletion:^(BOOL migratedWalletPresent) {
            [weakSelf presentInitialControllerAfterKeyMigration:migratedWalletPresent];
        }];
    }
    // Links the initial controller handed over before this view loaded: with
    // the wallet on screen and no lock due they are handled now; otherwise
    // the unlock, the hold's delivery or setup's completion hands them over.
    [self dispatchNextLinkIfReady];

    if (hasAWallet) {
        // Lock controller will be shown in applicationDidBecomeActiveNotification.
        // INFO: If we make the lockWindow key and visisble before our main window gets properly initialized
        // it will lead to weird bugs with keyboard (lockWindow will be visible, but main window remain key).
        //
        // Temporary cover root controller with overlay. It will be hidden after unlocking or
        // when unlocking is not needed
        UIImageView *overlayImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"image_bg"]];
        overlayImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlayImageView.frame = screenBounds;
        overlayImageView.contentMode = UIViewContentModeScaleAspectFill;
        [self.view addSubview:overlayImageView];
        self.overlayImageView = overlayImageView;
    }

    // Invitations wait in the queue until the sync is done; ask again then.
    [SyncingActivityMonitor.shared addObserver:self];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActiveNotification)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillResignActiveNotification)
                               name:UIApplicationWillResignActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillEnterForegroundNotification)
                               name:UIApplicationWillEnterForegroundNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidEnterBackgroundNotification)
                               name:UIApplicationDidEnterBackgroundNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(windowDidBecomeKeyNotification:)
                               name:UIWindowDidBecomeKeyNotification
                             object:nil];

    __weak typeof(self) weakSelf = self;
    self.model.currentNetworkDidChangeBlock = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        // reset main controller stack
        strongSelf->_mainController = nil;

        UIViewController *controller = [strongSelf mainController];
        [strongSelf transitionToController:controller
                            transitionType:DWContainerTransitionType_ScaleAndCrossDissolve];
    };
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (!self.model.walletOperationAllowed) {
        [self showDevicePasscodeAlert];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // If this controller was installed after launch (post-onboarding
    // setLaunchingAsDeferredController chain), perform the missed
    // UIApplicationDidBecomeActiveNotification notification action
    if (self.launchingWasDeferred) {
        self.launchingWasDeferred = NO;

        [self applicationDidBecomeActiveNotification];
    }

    // Now attached to a window: links kept because the hierarchy was not
    // (a link opened during onboarding, handed over at this controller's
    // creation) can have their screens.
    [self dispatchNextLinkIfReady];
}

#pragma mark - Key migration launch hold

/// Completion of the migration hold: present the initial controller the
/// normal launch decision would have picked. Main (behind the lock screen —
/// `PinStore` reads DashSync's PIN records in place, so the migrated wallet
/// keeps its old PIN) when the wallet landed; setup only when the hold
/// reports that nothing was left to migrate. A failed import never reaches
/// this method — the hold keeps its blocking card up until a retry lands.
/// The hold's verdict is the read: it reports `YES` only from a read that
/// saw the wallet, and re-reading here could fail where that one succeeded.
- (void)presentInitialControllerAfterKeyMigration:(BOOL)migratedWalletPresent {
    self.launchHoldPending = NO;
    if (migratedWalletPresent) {
        if ([self.model shouldShowLockScreen]) {
            // The links kept during the hold are handled after the unlock.
            [self showLockControllerIfNeeded];
        }
        else {
            [self transitionToController:[self mainController]];
            [self dispatchNextLinkIfReady];
        }
    }
    else {
        // A definite "no wallet": the links kept during the hold (an
        // invitation that opened the app, say) wait through setup and are
        // handled once it has presented the wallet.
        [self transitionToController:[self setupController]];
    }
}

#pragma mark - DWSetupViewControllerDelegate

- (void)setupViewControllerDidFinish:(DWSetupViewController *)controller {
    [self.model setupDidFinish];

    UIViewController *mainController = self.mainController;
    [self transitionToController:mainController
                  transitionType:DWContainerTransitionType_ScaleAndCrossDissolve];

    // The links kept through setup (an invitation that opened the app, a
    // payment link) are handled once the transition above has played; the
    // container transition reports no completion, hence the delay.
    if (!self.linkQueue.isEmpty) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf dispatchNextLinkIfReady];
        });
    }
}

#pragma mark - DWWipeDelegate

- (void)didWipeWallet {
    UIViewController *setupController = [self setupController];
    [self transitionToController:setupController
                  transitionType:DWContainerTransitionType_ScaleAndCrossDissolve];


    [self.model.homeModel walletDidWipe];
    // reset main controller stack
    _mainController = nil;
}

/// Coordinated path for an already-confirmed Delete All. Unlike the legacy
/// `didWipeWallet` notification, this transitions to the setup screen BEFORE
/// deleting state, then blocks that screen with a HUD until the SDK wiper's
/// FIFO barrier has completed. This avoids displaying a tappable-looking
/// onboarding screen while synchronous SDK deletion still occupies MainActor.
- (void)beginWipeWallet {
    [self beginWipeWalletWithAuthorization:DWSwiftDashSDKWalletWipeAuthorizationConfirmedDeleteAll];
}

- (void)beginDebugWipeWallet {
    [self beginWipeWalletWithAuthorization:DWSwiftDashSDKWalletWipeAuthorizationDebugReset];
}

- (void)beginWipeWalletWithAuthorization:(DWSwiftDashSDKWalletWipeAuthorization)authorization {
    if (self.walletWipeInProgress) {
        return;
    }
    // The admission gate rejects while another lifecycle operation (network
    // or wallet switch, removal) is in flight — a concurrent wipe would
    // mutate wallet state under that operation's teardown/rebuild. On
    // success the app-wide overlay window shows the blocking wipe card
    // (shared with network/wallet switches), replacing the screen-local HUD.
    if (![DWWalletLifecycleOverlayBridge beginWipingWithTitle:nil]) {
        // A silently swallowed confirm on a destructive action is worse than
        // a redundant alert — say why nothing happened.
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:nil
                                                message:NSLocalizedString(@"Another wallet operation is already in progress.", nil)
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        [self.currentController presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.walletWipeInProgress = YES;

    UIViewController *setupController = [self setupController];
    [self transitionToController:setupController
                  transitionType:DWContainerTransitionType_WithoutAnimation];

    [self.model.homeModel walletDidWipe];
    _mainController = nil;

    __weak typeof(self) weakSelf = self;
    // The SDK delete is synchronous on MainActor. Let UIKit commit the setup
    // screen and the overlay first; otherwise the first visible frame is only
    // drawn after the blocking deletion has already finished.
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC));
    dispatch_after(startTime, dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            // The gate was already taken above — release it, or `.wiping`
            // (and its blocking overlay) would outlive a wipe that never
            // started.
            [DWWalletLifecycleOverlayBridge finishWiping];
            return;
        }

        [DWSwiftDashSDKWalletWiper wipeWalletWithAuthorization:authorization];
        [DWSwiftDashSDKWalletWiper waitForPendingWipeWithCompletion:^(BOOL wipeSucceeded) {
            // Drop the overlay before anything self-dependent: the wiping
            // phase must never outlive the barrier, even if this controller
            // has gone away by the time it completes.
            [DWWalletLifecycleOverlayBridge finishWiping];
            typeof(self) completedSelf = weakSelf;
            if (completedSelf == nil) {
                return;
            }
            completedSelf.walletWipeInProgress = NO;
            if (!wipeSucceeded) {
                [completedSelf presentWalletWipeFailureForAuthorization:authorization];
            }
        }];
    });
}

- (void)presentWalletWipeFailureForAuthorization:(DWSwiftDashSDKWalletWipeAuthorization)authorization {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Couldn’t Delete All Wallets", nil)
                                            message:NSLocalizedString(@"Not all wallets could be deleted. Please try again.", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Retry", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_Nonnull action) {
                                                [weakSelf beginWipeWalletWithAuthorization:authorization];
                                            }]];
    [self.currentController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - DWLockScreenViewControllerDelegate

- (void)lockScreenViewControllerDidUnlock:(DWLockScreenViewController *)controller {
    NSParameterAssert(self.displayedLockNavigationController);

    [self hideAndRemoveOverlayImageView];

    if (self.currentController == nil) {
        UIViewController *controller = [self mainController];
        [self transitionToController:controller];
    }

    [UIView animateWithDuration:UNLOCK_ANIMATION_DURATION
        animations:^{
            self.lockWindow.alpha = 0.0;
        }
        completion:^(BOOL finished) {
            [self tearDownLockWindow];

            // After `tearDownLockWindow`: the queue reads `lockController`
            // to decide "still locked", and UIKit keeps the dismissed
            // hierarchy alive through this run-loop pass, so the weak
            // reference would not have zeroed by itself yet.
            [self dispatchNextLinkIfReady];

            [[NSNotificationCenter defaultCenter] postNotificationName:DWAppDidUnlockNotification
                                                                object:nil];
        }];
}

- (void)lockScreenViewControllerDidWipe:(DWLockScreenViewController *)controller {
    NSParameterAssert(self.displayedLockNavigationController);

    [self hideAndRemoveOverlayImageView];

    [self tearDownLockWindow];

    // The support recovery controller reports success only after the serial
    // wiper has completed. Transition to setup without issuing a second wipe.
    [self didWipeWallet];
}

/// Drop the lock screen and forget it at once. The two references are
/// weak, but the dismissed hierarchy outlives this call by a run-loop pass,
/// so anything that reads them right after (the deferred-link drain, the
/// next `showLockControllerIfNeeded`) must not see the old screen.
- (void)tearDownLockWindow {
    self.lockWindow.rootViewController = nil;
    self.lockWindow.hidden = YES;
    self.lockWindow.alpha = 1.0;
    self.lockController = nil;
    self.displayedLockNavigationController = nil;
    [DWWalletLifecycleOverlayBridge setLockScreenVisible:NO];
}

#pragma mark - SyncingActivityMonitorObserver

- (void)syncingActivityMonitorProgressDidChange:(double)progress {
}

- (void)syncingActivityMonitorStateDidChangeWithPreviousState:(enum SyncingActivityMonitorState)previousState state:(enum SyncingActivityMonitorState)state {
    if (state == SyncingActivityMonitorStateSyncDone) {
        [self dispatchNextLinkIfReady];
    }
}

#pragma mark - Notifications

- (void)applicationDidBecomeActiveNotification {
    [self showLockControllerIfNeeded];
}

- (void)applicationDidEnterBackgroundNotification {
}

- (void)applicationWillEnterForegroundNotification {
}

- (void)applicationWillResignActiveNotification {
    [self.model applicationWillResignActiveNotification];
}

- (void)windowDidBecomeKeyNotification:(NSNotification *)notification {
    // Keeps the displayed lock window key. The post-onboarding reinstall flow
    // (Keep Wallet → transitionToAppRoot → deferred
    // applicationDidBecomeActiveNotification) calls makeKeyAndVisible while the
    // onboarding container transition and the Keep/Delete alert teardown are
    // still in flight; their completion can hand key status back to the main
    // window. The lock screen then stays visible but keyboard/first-responder
    // input routes to the main window underneath — the failure mode described
    // by the INFO note in viewDidLoad. Whenever the main window becomes key
    // while the lock window is displayed, take key (and front) back.
    UIWindow *mainWindow = (UIWindow *)notification.object;
    if (mainWindow != self.view.window) {
        return;
    }
    if (self.displayedLockNavigationController == nil || self.lockWindow.hidden) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        // Re-validate before acting: only take key back if the main window
        // still holds it. If key has already moved to another window
        // (software keyboard, LocalAuthentication prompt), leave it alone —
        // a later steal by the main window fires this observer again.
        if (mainWindow != strongSelf.view.window || !mainWindow.isKeyWindow) {
            return;
        }
        if (strongSelf.displayedLockNavigationController != nil &&
            !strongSelf.lockWindow.hidden &&
            !strongSelf.lockWindow.isKeyWindow) {
            [strongSelf.lockWindow makeKeyAndVisible];
        }
    });
}

#pragma mark - Demo Mode

- (BOOL)demoMode {
    return NO;
}

- (void)setDemoDelegate:(nullable id<DWDemoDelegate>)demoDelegate {
    NSAssert(self.demoMode, @"Invalid usage. Demo delegate is to be used in the onboarding");

    _demoDelegate = demoDelegate;
}

#pragma mark - Private

- (void)showLockControllerIfNeeded {
    if (self.displayedLockNavigationController) {
        return;
    }

    if (![self.model shouldShowLockScreen]) {
        [DWWalletLifecycleOverlayBridge setLockScreenVisible:NO];
        [self hideAndRemoveOverlayImageView];

        return;
    }

    [self showLockControllerWithMode:DWLockScreenViewControllerUnlockMode_Instantly];
}

- (void)hideAndRemoveOverlayImageView {
    self.overlayImageView.hidden = YES;
    [self.overlayImageView removeFromSuperview];
    self.overlayImageView = nil;
}

- (void)showDevicePasscodeAlert {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Turn device passcode on", @"Alert title")
                         message:NSLocalizedString(@"A device passcode is needed to safeguard your wallet. Go to settings and turn passcode on to continue.", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *closeButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Close App", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:DWApp.applicationTerminationRequestNotification
                                                                        object:nil];
                }];
    [alert addAction:closeButton];
    [self presentViewController:alert animated:NO completion:nil];
}

- (UIViewController *)setupController {
    DWSetupViewController *controller = [DWSetupViewController controller];
    controller.delegate = self;

    if (self.launchingWasDeferred) {
        [controller setLaunchingAsDeferredController];
    }

    DWNavigationController *navigationController = [[DWNavigationController alloc] initWithRootViewController:controller];

    return navigationController;
}

- (MainTabbarController *)mainController {
    if (_mainController == nil) {
        id<DWHomeProtocol> homeModel = self.model.homeModel;
        MainTabbarController *controller = [[MainTabbarController alloc] initWithHomeModel:self.model.homeModel];
        controller.wipeDelegate = self;
        controller.isDemoMode = self.demoMode;
        controller.demoDelegate = self.demoDelegate;

        _mainController = controller;
    }

    return _mainController;
}

- (void)showLockControllerWithMode:(DWLockScreenViewControllerUnlockMode)mode {
    NSAssert(self.displayedLockNavigationController == nil, @"Inconsistent state");

    id<DWHomeProtocol> homeModel = self.model.homeModel;
    id<DWPayModelProtocol> payModel = homeModel.payModel;
    DWLockScreenViewController *controller = [DWLockScreenViewController lockScreenWithUnlockMode:mode
                                                                                         payModel:payModel];
    controller.delegate = self;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;

    [DWWalletLifecycleOverlayBridge setLockScreenVisible:YES];
    self.lockWindow.rootViewController = navigationController;
    [self.lockWindow makeKeyAndVisible];

    self.lockController = controller;
    self.displayedLockNavigationController = navigationController;
}

@end

NS_ASSUME_NONNULL_END
