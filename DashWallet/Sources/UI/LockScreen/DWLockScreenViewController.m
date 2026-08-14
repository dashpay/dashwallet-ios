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
#import "DWRecoverViewController.h"
#import "DWSetPinViewController.h"
#import "DWUIKit.h"
#import "dashwallet-Swift.h"

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

@interface DWLockScreenViewController () <DWLockPinInputViewDelegate,
                                          DWLockScreenModelDelegate,
                                          DWRecoverViewControllerDelegate,
                                          DWSetPinViewControllerDelegate>

@property (strong, nonatomic) DWLockScreenModel *model;

@property (strong, nonatomic) IBOutlet DWLockPinInputView *pinInputView;
@property (strong, nonatomic) IBOutlet UIButton *forgotPinButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *quickReceiveButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *loginButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *scanToPayButton;
@property (strong, nonatomic) IBOutlet NumberKeyboard *keyboarView;

@property (strong, nonatomic) IBOutlet NSLayoutConstraint *dashLogoTopConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *keyboardSpacingViewHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *actionButtonsHeightConstraint;

@property (nonatomic, assign) BOOL biometricsAuthorizationAttemptWasMade;

@end

@implementation DWLockScreenViewController

+ (instancetype)lockScreenWithUnlockMode:(DWLockScreenViewControllerUnlockMode)unlockMode
                                payModel:(id<DWPayModelProtocol>)payModel {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LockScreen" bundle:nil];
    DWLockScreenViewController *controller = [storyboard instantiateInitialViewController];
    controller.unlockMode = unlockMode;
    controller.payModel = payModel;

    return controller;
}

- (BOOL)locksBalance {
    return YES;
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

    // No PIN record at all (partial keychain restore, interrupted setup):
    // there is nothing to forget and no fail counter can ever advance, so go
    // straight to the ownership proof. The phrase gate stays mandatory — the
    // PIN is the spending protection, so a missing record must not become a
    // free takeover of the wallet.
    if (!self.model.hasPinSet) {
        [self presentPinResetRecovery];
        return;
    }

    // Everyday forgot-PIN: prove ownership with the recovery phrase, then set a
    // new PIN and keep the wallet (app-owned DWRecoverViewController in
    // ResetPin mode). Only past the wipe threshold do we also offer a wipe —
    // matching DashSync, whose Wipe button appeared only once wiping was
    // allowed.
    if ([self.model isAllowedToWipe]) {
        UIAlertControllerStyle style = IS_IPAD ? UIAlertControllerStyleAlert : UIAlertControllerStyleActionSheet;
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                       message:nil
                                                                preferredStyle:style];
        [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Reset PIN", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    [self presentPinResetRecovery];
                                                }]];
        [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Wipe All Wallets", nil)
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
                                                    [self confirmWipeWallet];
                                                }]];
        [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *action) {
                                                    [self.model startCheckingAuthState];
                                                }]];
        [self presentViewController:sheet animated:YES completion:nil];
    }
    else {
        [self presentPinResetRecovery];
    }
}

- (void)presentPinResetRecovery {
    DWRecoverViewController *controller = [[DWRecoverViewController alloc] init];
    controller.action = DWRecoverAction_ResetPin;
    controller.delegate = self;
    UIBarButtonItem *cancelButton =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(forgotPinRecoveryCancelAction:)];
    // This controller is the root of a modal navigation stack. Our shared
    // navigation controller clears left-side items for root controllers (to
    // suppress a back button), so keep the modal escape action on the right.
    controller.navigationItem.rightBarButtonItem = cancelButton;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)forgotPinRecoveryCancelAction:(id)sender {
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self.model startCheckingAuthState];
                             }];
}

- (void)confirmWipeWallet {
    __weak typeof(self) weakSelf = self;
    [DWWalletDeleteAllConfirmationCoordinator
        presentFrom:self
        cancelHandler:^{
            typeof(self) strongSelf = weakSelf;
            [strongSelf.model startCheckingAuthState];
        }
        deleteAllHandler:^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf.delegate lockScreenViewControllerDidWipe:strongSelf];
        }];
}

#pragma mark - DWRecoverViewControllerDelegate

- (void)recoverViewControllerDidVerifyPhraseForPinReset:(DWRecoverViewController *)controller {
    // Ownership proven, wallet untouched — dismiss the phrase screen and set a
    // new PIN. Unlock happens once the PIN is set.
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self presentSetNewPin];
                             }];
}

- (void)recoverViewControllerDidWipe:(DWRecoverViewController *)controller {
    // Unreachable in ResetPin mode (wipe is offered by the lock screen's own
    // action sheet, not this screen). Implemented for protocol conformance; if
    // it ever fires, fail loud in debug and recover safely in release.
    NSAssert(NO, @"ResetPin recovery never wipes; wipe is the lock screen's own path");
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self.model startCheckingAuthState];
                             }];
}

- (void)recoverViewControllerDidRecoverWallet:(DWRecoverViewController *)controller
                               recoverCommand:(DWRecoverWalletCommand *)recoverCommand {
    // Unreachable in ResetPin mode (no wallet is recovered/re-imported here).
    NSAssert(NO, @"ResetPin recovery never recovers a wallet");
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self.model startCheckingAuthState];
                             }];
}

#pragma mark - DWSetPinViewControllerDelegate

- (void)presentSetNewPin {
    // Forgot-PIN changes an existing PIN; the no-PIN-record path sets the
    // first one — same screen, honest title.
    const DWSetPinIntent intent =
        self.model.hasPinSet ? DWSetPinIntent_ChangePin : DWSetPinIntent_SetPin;
    DWSetPinViewController *controller =
        [DWSetPinViewController controllerWithIntent:intent];
    controller.delegate = self;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)setPinViewControllerDidSetPin:(DWSetPinViewController *)controller {
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self.delegate lockScreenViewControllerDidUnlock:self];
                             }];
}

- (void)setPinViewControllerDidCancel:(DWSetPinViewController *)controller {
    // Phrase was proven but the user backed out of setting a new PIN — return
    // to the lock screen in whatever state the keychain is in: the old PIN
    // still works on the forgot-PIN path, and the no-PIN-record path re-renders
    // its Set PIN routing.
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self.model startCheckingAuthState];
                             }];
}

- (IBAction)receiveButtonAction:(DWLockActionButton *)sender {
    // SwiftUI receive surface (Transparent / Platform / Shielded toggle),
    // narrowed to the Receive tab for the locked context.
    UIViewController *controller = [DWPaymentsLandingHostingController quickReceiveController];
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
    // A wallet without a PIN record (partial keychain restore, interrupted
    // setup) can never satisfy "Enter PIN" — every entry would fail as a
    // store error, permanently locking the user out. Present the honest
    // state instead and route to the phrase-gated Set PIN flow. This wins
    // over a stale lockout counter too: with no PIN there is nothing to
    // brute-force, and setting the new PIN zeroes the counters.
    if (!model.hasPinSet) {
        self.keyboarView.isEnabled = NO;
        self.scanToPayButton.enabled = NO;
        [self hideLoginButtonIfNeeded];
        [self.pinInputView setTitleText:NSLocalizedString(@"PIN Not Set", nil)];
        // Keep this to one action phrase: the pin-input container is centered
        // without a width cap (LockScreen.storyboard), so an overlong single
        // line renders past the screen edges instead of wrapping.
        [self.pinInputView setAttemptsText:nil
                                 errorText:NSLocalizedString(@"Verify your recovery phrase to set a new PIN.", nil)];
        return;
    }

    self.keyboarView.isEnabled = shouldContinueAuthentication;
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

        // Don't try to use biometrics if there any of quick actions screen is active
        if (self.presentedViewController) {
            return;
        }

        [self performBiometricAuthentication];
    }
}

- (void)setupView {
    NSParameterAssert(self.model);

    self.pinInputView.delegate = self;
    [self.pinInputView configureWithKeyboard:self.keyboarView];

    // The button is the single escape hatch in both states; with no PIN
    // record "Forgot PIN?" would be a lie — nothing was forgotten. A PIN
    // set while this screen is alive immediately unlocks (delegate), so the
    // title never needs to flip back.
    NSString *escapeTitle = self.model.hasPinSet
                                ? NSLocalizedString(@"Forgot PIN?", nil)
                                : NSLocalizedString(@"Set PIN", nil);
    [self.forgotPinButton setTitle:escapeTitle forState:UIControlStateNormal];

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

    self.scanToPayButton.title = NSLocalizedString(@"Scan to Send", nil);
    self.scanToPayButton.image = [UIImage imageNamed:@"icon_lock_scan_to_pay"];

    [self.keyboarView configureFunctionButtonAsHidden];

    self.dashLogoTopConstraint.constant = DashLogoTopPadding();
    self.keyboardSpacingViewHeightConstraint.constant = KeyboardSpacingViewHeight();
    self.actionButtonsHeightConstraint.constant = ActionButtonsHeight();
}

- (void)performBiometricAuthentication {
    // No biometric unlock while no PIN record exists: it would bypass the
    // missing PIN into a wallet where every downstream auth gate (spend,
    // change-PIN) is unsatisfiable. The Set PIN route repairs the state first.
    if (!self.model.hasPinSet) {
        return;
    }

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
    self.loginButton.hidden = !self.model.hasPinSet || !self.model.isBiometricAuthenticationAllowed;
}

@end

NS_ASSUME_NONNULL_END
