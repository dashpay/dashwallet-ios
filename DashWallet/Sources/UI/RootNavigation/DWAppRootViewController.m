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

#import <DashSync/DashSync.h>
#import <DashSync/UIWindow+DSUtils.h>

#import "DWLockScreenViewController.h"
#import "DWMainTabbarViewController.h"
#import "DWNavigationController.h"
#import "DWRootModel.h"
#import "DWSetupViewController.h"
#import "DWUIKit.h"
#import "DWURLParser.h"
#import "DWURLRequestHandler.h"
#import "DWUpholdAuthURLNotification.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const UNLOCK_ANIMATION_DURATION = 0.25;

@interface DWAppRootViewController () <DWSetupViewControllerDelegate,
                                       DWWipeDelegate,
                                       DWLockScreenViewControllerDelegate>

@property (readonly, nonatomic, strong) id<DWRootProtocol> model;

@property (null_resettable, nonatomic, strong) DWMainTabbarViewController *mainController;

@property (nullable, nonatomic, strong) UIImageView *overlayImageView;
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nullable, nonatomic, weak) DWLockScreenViewController *lockController;
@property (nullable, nonatomic, weak) UIViewController *displayedLockNavigationController;

@property (nullable, nonatomic, strong) NSURL *deferredURLToProcess;
@property (nullable, nonatomic, strong) NSURL *deferredDeeplinkToProcess;

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
    }
    return self;
}

#pragma mark - Public

+ (Class)mainControllerClass {
    return [DWMainTabbarViewController class];
}

- (void)setLaunchingAsDeferredController {
    self.launchingWasDeferred = YES;
}

- (void)handleDeeplink:(NSURL *)url {
    // Defer URL until unlocked.
    // This also prevents an issue with too fast unlocking via Face ID.
    BOOL isLocked = [self.model shouldShowLockScreen] || self.lockController;
    if (isLocked && self.deferredDeeplinkToProcess == nil) {
        self.deferredDeeplinkToProcess = url;
        return;
    }

    [self.mainController handleDeeplink:url];
}

- (void)handleURL:(NSURL *)url {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    // Defer URL until unlocked.
    // This also prevents an issue with too fast unlocking via Face ID.
    BOOL isLocked = [self.model shouldShowLockScreen] || self.lockController;
    if (isLocked && self.deferredURLToProcess == nil) {
        self.deferredURLToProcess = url;
        return;
    }

    DWURLAction *action = [DWURLParser actionForURL:url];
    if (!action) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"Unsupported URL", nil)
                             message:url.absoluteString
                      preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"OK", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];

        [alert addAction:okAction];

        UIApplication *application = [UIApplication sharedApplication];
        UIViewController *presentingController = [application.keyWindow ds_presentingViewController];
        [presentingController presentViewController:alert animated:YES completion:nil];

        return;
    }

    if ([action isKindOfClass:DWURLScanQRAction.class]) {
        [self.mainController performScanQRCodeAction];
    }
    else if ([action isKindOfClass:DWURLUpholdAction.class]) {
        NSURL *url = [(DWURLUpholdAction *)action url];
        [[NSNotificationCenter defaultCenter] postNotificationName:DWUpholdAuthURLNotification object:url];
    }
    else if ([action isKindOfClass:DWURLRequestAction.class]) {
        [DWURLRequestHandler handleURLRequest:(DWURLRequestAction *)action];
    }
    else if ([action isKindOfClass:DWURLPayAction.class]) {
        NSURL *paymentURL = [(DWURLPayAction *)action paymentURL];
        [self.mainController performPayToURL:paymentURL];
    }
    else {
        NSAssert(NO, @"Unhandled action", action);
    }
}

- (void)handleFile:(NSData *)file {
    if (self.lockController) {
        [self.lockController handleFile:file];
    }
    else {
        [self.mainController handleFile:file];
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
    self.lockWindow = lockWindow;

    // Display main controller initially if there is a wallet and lock screen is disabled
    // Otherwise main controller will be set as current in `lockScreenViewControllerDidUnlock:`
    const BOOL hasAWallet = self.model.hasAWallet;
    UIViewController *controller = nil;
    if (hasAWallet) {
        if (![self.model shouldShowLockScreen]) {
            controller = [self mainController];
        }
    }
    else {
        controller = [self setupController];
    }

    if (controller) {
        [self transitionToController:controller];
    }

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

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActiveNotification)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidEnterBackgroundNotification)
                               name:UIApplicationDidEnterBackgroundNotification
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

    // If launch of DWAppRootViewController was deferred by DWStartViewController perform
    // missed UIApplicationDidBecomeActiveNotification notification action
    if (self.launchingWasDeferred) {
        self.launchingWasDeferred = NO;

        [self applicationDidBecomeActiveNotification];
    }
}

#pragma mark - DWSetupViewControllerDelegate

- (void)setupViewControllerDidFinish:(DWSetupViewController *)controller {
    [self.model setupDidFinish];

    UIViewController *mainController = self.mainController;
    [self transitionToController:mainController
                  transitionType:DWContainerTransitionType_ScaleAndCrossDissolve];
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
            self.lockWindow.rootViewController = nil;
            self.lockWindow.hidden = YES;
            self.lockWindow.alpha = 1.0;

            if (self.deferredDeeplinkToProcess) {
                [self handleDeeplink:self.deferredDeeplinkToProcess];
            }
            else if (self.deferredURLToProcess) {
                [self handleURL:self.deferredURLToProcess];
            }
            self.deferredDeeplinkToProcess = nil;
            self.deferredURLToProcess = nil;
        }];
}

- (void)lockScreenViewControllerDidWipe:(DWLockScreenViewController *)controller {
    NSParameterAssert(self.displayedLockNavigationController);

    [self hideAndRemoveOverlayImageView];

    self.lockWindow.rootViewController = nil;
    self.lockWindow.hidden = YES;
    self.lockWindow.alpha = 1.0;

    [self.model wipeWallet];
    [self didWipeWallet];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActiveNotification {
    [self showLockControllerIfNeeded];
}

- (void)applicationDidEnterBackgroundNotification {
    [self.model applicationDidEnterBackground];
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
                    [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
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

- (DWMainTabbarViewController *)mainController {
    if (_mainController == nil) {
        id<DWHomeProtocol> homeModel = self.model.homeModel;
        Class klass = [self.class mainControllerClass];
        DWMainTabbarViewController *controller = [[klass alloc] init];
        controller.homeModel = homeModel;
        controller.delegate = self;
        controller.demoMode = self.demoMode;
        controller.demoDelegate = self.demoDelegate;

        _mainController = controller;
    }

    return _mainController;
}

- (void)showLockControllerWithMode:(DWLockScreenViewControllerUnlockMode)mode {
    NSAssert(self.displayedLockNavigationController == nil, @"Inconsistent state");

    id<DWHomeProtocol> homeModel = self.model.homeModel;
    id<DWPayModelProtocol> payModel = homeModel.payModel;
    id<DWReceiveModelProtocol> receiveModel = homeModel.receiveModel;
    id<DWTransactionListDataProviderProtocol> dataProvider = [homeModel getDataProvider];
    DWLockScreenViewController *controller = [DWLockScreenViewController lockScreenWithUnlockMode:mode
                                                                                         payModel:payModel
                                                                                     receiveModel:receiveModel
                                                                                     dataProvider:dataProvider];
    controller.delegate = self;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;

    self.lockWindow.rootViewController = navigationController;
    [self.lockWindow makeKeyAndVisible];

    self.lockController = controller;
    self.displayedLockNavigationController = navigationController;
}

@end

NS_ASSUME_NONNULL_END
