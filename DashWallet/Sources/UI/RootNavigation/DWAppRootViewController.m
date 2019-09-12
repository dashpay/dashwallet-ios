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
#import "DWMainTabbarViewController.h"
#import "DWRootModel.h"
#import "DWSetupViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const TRANSITION_DURATION = 0.35;

@interface DWAppRootViewController () <DWSetupViewControllerDelegate,
                                       DWMainTabbarViewControllerDelegate,
                                       DWLockScreenViewControllerDelegate>

@property (readonly, nonatomic, strong) DWRootModel *model;
@property (nullable, nonatomic, strong) UIViewController *currentController;

@property (null_resettable, nonatomic, strong) UIViewController *mainController;
@property (nullable, nonatomic, weak) UIViewController *displayedLockController;

@end

@implementation DWAppRootViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = [[DWRootModel alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

    UIViewController *controller = nil;
    if (self.model.hasAWallet) {
        // always show lock controller on app's start

        // prepare controller & models
        [self mainController];

        controller = [self lockControllerWithMode:DWLockScreenViewControllerUnlockMode_ApplicationDidBecomeActive];
        self.displayedLockController = controller;
    }
    else {
        controller = [self setupController];
    }
    [self displayViewController:controller];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActiveNotification)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidEnterBackgroundNotification)
                               name:UIApplicationDidEnterBackgroundNotification
                             object:nil];
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

#pragma mark - DWSetupViewControllerDelegate

- (void)setupViewControllerDidFinish:(DWSetupViewController *)controller {
    UIViewController *mainController = self.mainController;
    [self performTransitionToViewController:mainController];
}

#pragma mark - DWMainTabbarViewControllerDelegate

- (void)mainTabbarViewControllerDidWipeWallet:(DWMainTabbarViewController *)controller {
    UIViewController *setupController = [self setupController];
    [self performTransitionToViewController:setupController];
}

#pragma mark - DWLockScreenViewControllerDelegate

- (void)lockScreenViewControllerDidUnlock:(DWLockScreenViewController *)controller {
    UIViewController *lockNavigationController = controller.navigationController;
    NSParameterAssert(lockNavigationController);

    UIViewController *mainController = self.mainController;
    [self performTransitionToViewController:mainController];
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
    if (self.displayedLockController) {
        return;
    }

    if (![self.model shouldShowLockScreen]) {
        return;
    }

    UIViewController *controller = [self lockControllerWithMode:DWLockScreenViewControllerUnlockMode_Instantly];
    [self performTransitionToViewController:controller];

    self.displayedLockController = controller;
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

- (UIViewController *)mainController {
    if (_mainController == nil) {
        DWMainTabbarViewController *controller = [DWMainTabbarViewController controller];
        controller.delegate = self;

        _mainController = controller;
    }

    return _mainController;
}

- (UIViewController *)lockControllerWithMode:(DWLockScreenViewControllerUnlockMode)mode {
    UIViewController *controller = [DWLockScreenViewController controllerEmbededInNavigationWithDelegate:self
                                                                                              unlockMode:mode];

    return controller;
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
