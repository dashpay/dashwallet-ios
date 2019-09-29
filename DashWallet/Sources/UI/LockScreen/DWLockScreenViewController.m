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

#import "DWLockScreenViewController.h"

#import "DWLockActionButton.h"
#import "DWLockPinInputView.h"
#import "DWLockScreenModel.h"
#import "DWNavigationController.h"
#import "DWNumberKeyboard.h"
#import "DWQuickReceiveViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ANIMATION_DURATION = 0.35;

static CGFloat DashLogoTopPadding(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 0.0;
    }
    else if (IS_IPHONE_6) {
        return 16.0;
    }
    else {
        return 42.0;
    }
}

static CGFloat KeyboardSpacingViewHeight(void) {
    const CGFloat homeIndicatorHeight = 34.0;

    if (IS_IPAD) { // All iPads including ones with home indicator
        return homeIndicatorHeight + 24.0;
    }
    else if (DEVICE_HAS_HOME_INDICATOR) { // iPhone X-like, XS Max, X
        return homeIndicatorHeight + 4.0;
    }
    else if (IS_IPHONE_6_PLUS) { // iPhone 6 Plus-like
        return 20.0;
    }
    else { // iPhone 5-like, 6-like
        return 0.0;
    }
}

static CGFloat ActionButtonsHeight(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 76.0;
    }
    else {
        return 96.0;
    }
}

@interface DWLockScreenViewController () <DWLockPinInputViewDelegate, DWLockScreenModelDelegate>

@property (strong, nonatomic) DWLockScreenModel *model;
@property (nonatomic, strong) DWReceiveModel *receiveModel;

@property (strong, nonatomic) IBOutlet DWLockPinInputView *pinInputView;
@property (strong, nonatomic) IBOutlet UIButton *forgotPinButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *quickReceiveButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *loginButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *scanToPayButton;
@property (strong, nonatomic) IBOutlet DWNumberKeyboard *keyboarView;

@property (strong, nonatomic) IBOutlet NSLayoutConstraint *dashLogoTopConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *keyboardSpacingViewHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *actionButtonsHeightConstraint;

@property (nonatomic, assign) BOOL biometricsAuthorizationAttemptWasMade;

@end

@implementation DWLockScreenViewController

+ (UIViewController *)lockNavigationWithDelegate:(id<DWLockScreenViewControllerDelegate>)delegate
                                      unlockMode:(DWLockScreenViewControllerUnlockMode)unlockMode
                                        payModel:(DWPayModel *)payModel
                                    receiveModel:(DWReceiveModel *)receiveModel
                                    dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LockScreen" bundle:nil];
    DWLockScreenViewController *controller = [storyboard instantiateInitialViewController];
    controller.delegate = delegate;
    controller.unlockMode = unlockMode;
    controller.payModel = payModel;
    controller.receiveModel = receiveModel;
    controller.dataProvider = dataProvider;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;

    return navigationController;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.model = [[DWLockScreenModel alloc] init];
    self.model.delegate = self;

    [self setupView];

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

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.pinInputView activatePinField];
    [self.model startCheckingAuthState];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.unlockMode == DWLockScreenViewControllerUnlockMode_Instantly) {
        [self tryOnceToUnlockUsingBiometrics];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.model stopCheckingAuthState];
}

#pragma mark - Actions

- (IBAction)forgotPinButtonAction:(UIButton *)sender {
    [self.model stopCheckingAuthState];

    __weak typeof(self) weakSelf = self;
    [[DSAuthenticationManager sharedInstance]
        resetWalletWithWipeHandler:nil
                        completion:^(BOOL success) {
                            __strong typeof(weakSelf) strongSelf = weakSelf;
                            if (!strongSelf) {
                                return;
                            }

                            if (success) {
                                [self.delegate lockScreenViewControllerDidUnlock:self];
                            }
                            else {
                                [self.model startCheckingAuthState];
                            }
                        }];
}

- (IBAction)receiveButtonAction:(DWLockActionButton *)sender {
    UIViewController *controller = [DWQuickReceiveViewController controllerWithModel:self.receiveModel];
    [self presentViewController:controller animated:YES completion:nil];
}

- (IBAction)loginButtonAction:(DWLockActionButton *)sender {
    [self performBiometricAuthentication];
}

- (IBAction)scanToPayButtonAction:(DWLockActionButton *)sender {
    [self performScanQRCodeAction];
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - DWLockScreenModelDelegate

- (void)lockScreenModel:(DWLockScreenModel *)model
    shouldContinueAuthentication:(BOOL)shouldContinueAuthentication
                   authenticated:(BOOL)authenticated
                   shouldLockout:(BOOL)shouldLockout
                 attemptsMessage:(nullable NSString *)attemptsMessage {
    self.keyboarView.enabled = shouldContinueAuthentication;
    self.scanToPayButton.enabled = shouldContinueAuthentication;

    [self hideLoginButtonIfNeeded];

    if (shouldContinueAuthentication) {
        [self.pinInputView setTitleText:NSLocalizedString(@"Enter PIN", nil)];
        [self.pinInputView setAttemptsText:attemptsMessage errorText:nil];
    }
    else {
        if (shouldLockout) {
            NSString *errorText = [self.model lockoutErrorMessage];
            [self.pinInputView setAttemptsText:nil errorText:errorText];
        }
        else if (!authenticated) {
            // error reading from the Keychain
            [self.pinInputView setAttemptsText:nil
                                     errorText:NSLocalizedString(@"Authentication is unvailable", nil)];
        }

        if (authenticated) {
            [self.delegate lockScreenViewControllerDidUnlock:self];
        }
        else {
            [self.pinInputView setTitleText:NSLocalizedString(@"Wallet disabled", nil)];
        }
    }
}

#pragma mark - DWLockPinInputViewDelegate

- (void)lockPinInputView:(DWLockPinInputView *)view didFinishInputWithText:(NSString *)text {
    BOOL isPinValid = [self.model checkPin:text];
    if (isPinValid) {
        [self.delegate lockScreenViewControllerDidUnlock:self];
    }
    else {
        [view clearAndShakePinField];
    }
}

#pragma mark - Notifications

- (void)applicationDidBecomeActiveNotification {
    [self tryOnceToUnlockUsingBiometrics];
    [self.model startCheckingAuthState];
}

- (void)applicationDidEnterBackgroundNotification {
    // If the user leave the app while on the lock screen reset flag to request biometrics on the next launch
    self.biometricsAuthorizationAttemptWasMade = NO;
    [self.model stopCheckingAuthState];
}

#pragma mark - Private

- (void)tryOnceToUnlockUsingBiometrics {
    if (!self.biometricsAuthorizationAttemptWasMade) {
        self.biometricsAuthorizationAttemptWasMade = YES;

        [self performBiometricAuthentication];
    }
}

- (void)setupView {
    NSParameterAssert(self.model);

    self.pinInputView.delegate = self;
    [self.pinInputView configureWithKeyboard:self.keyboarView];

    [self.forgotPinButton setTitle:NSLocalizedString(@"Forgot PIN?", nil) forState:UIControlStateNormal];

    self.quickReceiveButton.title = NSLocalizedString(@"Quick Receive", nil);
    self.quickReceiveButton.image = [UIImage imageNamed:@"icon_lock_receive"];

    switch (self.model.biometryType) {
        case LABiometryTypeFaceID: {
            self.loginButton.title = NSLocalizedString(@"Login with Face ID", nil);
            self.loginButton.image = [UIImage imageNamed:@"icon_lock_faceid"];

            break;
        }
        case LABiometryTypeTouchID: {
            self.loginButton.title = NSLocalizedString(@"Login with Touch ID", nil);
            self.loginButton.image = [UIImage imageNamed:@"icon_lock_touchid"];

            break;
        }
        default: {
            self.loginButton.hidden = YES;

            break;
        }
    }
    [self hideLoginButtonIfNeeded];

    self.scanToPayButton.title = NSLocalizedString(@"Scan to Pay", nil);
    self.scanToPayButton.image = [UIImage imageNamed:@"icon_lock_scan_to_pay"];

    [self.keyboarView configureFunctionButtonAsHidden];

    self.dashLogoTopConstraint.constant = DashLogoTopPadding();
    self.keyboardSpacingViewHeightConstraint.constant = KeyboardSpacingViewHeight();
    self.actionButtonsHeightConstraint.constant = ActionButtonsHeight();
}

- (void)performBiometricAuthentication {
    if (self.model.isBiometricAuthenticationAllowed) {
        [self.model authenticateUsingBiometricsOnlyCompletion:^(BOOL authenticated) {
            if (authenticated) {
                [self.delegate lockScreenViewControllerDidUnlock:self];
            }
            else {
                [self hideLoginButtonIfNeeded];
            }
        }];
    }
}

- (void)hideLoginButtonIfNeeded {
    self.loginButton.hidden = !self.model.isBiometricAuthenticationAllowed;
}

@end

NS_ASSUME_NONNULL_END
