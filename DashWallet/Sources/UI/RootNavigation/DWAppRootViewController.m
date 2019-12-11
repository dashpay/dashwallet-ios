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

#import <DashSync/UIWindow+DSUtils.h>

#import "DWHomeModel.h"
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

static NSTimeInterval const TRANSITION_DURATION = 0.35;
static NSTimeInterval const UNLOCK_ANIMATION_DURATION = 0.25;

@interface DWAppRootViewController () <DWSetupViewControllerDelegate,
                                       DWWipeDelegate,
                                       DWLockScreenViewControllerDelegate>

@property (readonly, nonatomic, strong) DWRootModel *model;
@property (nullable, nonatomic, strong) UIViewController *currentController;

@property (null_resettable, nonatomic, strong) DWMainTabbarViewController *mainController;

@property (nullable, nonatomic, strong) UIImageView *overlayImageView;
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nullable, nonatomic, weak) DWLockScreenViewController *lockController;
@property (nullable, nonatomic, weak) UIViewController *displayedLockNavigationController;

@property (nonatomic, assign) BOOL launchingWasDeferred;

@end

@implementation DWAppRootViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = [[DWRootModel alloc] init];
    }
    return self;
}

#pragma mark - Public

- (void)setLaunchingAsDeferredController {
    self.launchingWasDeferred = YES;
}

- (void)handleURL:(NSURL *)url {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

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
        if (self.lockController) {
            [self.lockController performScanQRCodeAction];
        }
        else {
            [self.mainController performScanQRCodeAction];
        }
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
        if (self.lockController) {
            [self.lockController performPayToURL:paymentURL];
        }
        else {
            [self.mainController performPayToURL:paymentURL];
        }
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

#pragma mark - Life Cycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

    const CGRect screenBounds = [UIScreen mainScreen].bounds;
    UIWindow *lockWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    lockWindow.backgroundColor = [UIColor blackColor];
    lockWindow.windowLevel = UIWindowLevelNormal;
    self.lockWindow = lockWindow;

    const BOOL hasAWallet = self.model.hasAWallet;
    UIViewController *controller = nil;
    if (hasAWallet) {
        controller = [self mainController];
    }
    else {
        controller = [self setupController];
    }
    [self displayViewController:controller];

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
        [strongSelf performTransitionToViewController:controller];
    };
}

- (nullable UIViewController *)childViewControllerForStatusBarStyle {
    return self.currentController;
}

- (nullable UIViewController *)childViewControllerForStatusBarHidden {
    return self.currentController;
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
    [self.model setupDidFinished];

    UIViewController *mainController = self.mainController;
    [self performTransitionToViewController:mainController];
}

#pragma mark - DWWipeDelegate

- (void)didWipeWallet {
    UIViewController *setupController = [self setupController];
    [self performTransitionToViewController:setupController];

    // reset main controller stack
    _mainController = nil;
}

#pragma mark - DWLockScreenViewControllerDelegate

- (void)lockScreenViewControllerDidUnlock:(DWLockScreenViewController *)controller {
    NSParameterAssert(self.displayedLockNavigationController);

    [self hideAndRemoveOverlayImageView];

    [UIView animateWithDuration:UNLOCK_ANIMATION_DURATION
        animations:^{
            self.lockWindow.alpha = 0.0;
        }
        completion:^(BOOL finished) {
            self.lockWindow.rootViewController = nil;
            self.lockWindow.hidden = YES;
            self.lockWindow.alpha = 1.0;
        }];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActiveNotification {
    [self showLockControllerIfNeeded];
}

- (void)applicationDidEnterBackgroundNotification {
    [self.model applicationDidEnterBackground];
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
        alertControllerWithTitle:NSLocalizedString(@"Turn device passcode on", nil)
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
    UIViewController *controller = [DWSetupViewController controllerEmbededInNavigationWithDelegate:self];

    return controller;
}

- (DWMainTabbarViewController *)mainController {
    if (_mainController == nil) {
        DWHomeModel *homeModel = self.model.homeModel;
        DWMainTabbarViewController *controller = [DWMainTabbarViewController controllerWithHomeModel:homeModel];
        controller.delegate = self;

        _mainController = controller;
    }

    return _mainController;
}

- (void)showLockControllerWithMode:(DWLockScreenViewControllerUnlockMode)mode {
    NSAssert(self.displayedLockNavigationController == nil, @"Inconsistent state");

    DWHomeModel *homeModel = self.model.homeModel;
    DWPayModel *payModel = homeModel.payModel;
    DWReceiveModel *receiveModel = homeModel.receiveModel;
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

- (void)displayViewController:(UIViewController *)controller {
    NSParameterAssert(controller);

    UIView *contentView = self.view;
    UIView *childView = controller.view;

    [self addChildViewController:controller];

    childView.frame = contentView.bounds;
    childView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [contentView addSubview:childView];

    [controller didMoveToParentViewController:self];

    self.currentController = controller;

    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)performTransitionToViewController:(UIViewController *)toViewController {
    UIViewController *fromViewController = self.childViewControllers.firstObject;
    NSAssert(fromViewController, @"To perform transition there should be child view controller. Use displayViewController: instead");

    UIView *toView = toViewController.view;
    UIView *fromView = fromViewController.view;
    UIView *contentView = self.view;

    self.currentController = toViewController;

    [fromViewController willMoveToParentViewController:nil];
    [self addChildViewController:toViewController];

    toView.frame = contentView.bounds;
    toView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [contentView addSubview:toView];

    toView.alpha = 0.0;
    toView.transform = CGAffineTransformMakeScale(1.25, 1.25);

    [UIView animateWithDuration:TRANSITION_DURATION
        delay:0.0
        usingSpringWithDamping:1.0
        initialSpringVelocity:0.0
        options:UIViewAnimationOptionCurveEaseInOut
        animations:^{
            toView.alpha = 1.0;
            toView.transform = CGAffineTransformIdentity;
            fromView.alpha = 0.0;

            [self setNeedsStatusBarAppearanceUpdate];
        }
        completion:^(BOOL finished) {
            [fromView removeFromSuperview];
            [fromViewController removeFromParentViewController];
            [toViewController didMoveToParentViewController:self];
        }];
}

@end

NS_ASSUME_NONNULL_END
