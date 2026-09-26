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

#import "DWSetupViewController.h"

#import "DWBiometricAuthModel.h"
#import "DWBiometricAuthViewController.h"
#import "DWGlobalOptions.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWRecoverViewController.h"
#import "DWSetPinModel.h"
#import "DWSetPinViewController.h"
#import "UIView+DWHUD.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ANIMATION_DURATION = 0.25;

@interface DWSetupViewController () <DWSetPinViewControllerDelegate,
                                     DWBiometricAuthViewControllerDelegate,
                                     DWSecureWalletDelegate,
                                     DWRecoverViewControllerDelegate,
                                     DWBackupInfoViewControllerDelegate>

@property (nonatomic, assign) BOOL initialAnimationCompleted;

@property (strong, nonatomic) IBOutlet UIButton *createWalletButton;
@property (strong, nonatomic) IBOutlet UIButton *recoverWalletButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *logoLayoutViewBottomContraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@property (nullable, nonatomic, strong) DWRecoverWalletCommand *recoverWalletCommand;
/// The recover import in flight, if any: blocks a second submission and
/// lets a completion tell whether it belongs to the current attempt.
@property (nonatomic, strong) DWRecoverImportAttempts *recoverAttempts;
/// The recover screen whose phrase is being imported: its input is blocked
/// for the import's duration, so the keyboard's Done cannot resubmit or
/// take the wipe route meanwhile.
@property (nullable, nonatomic, weak) DWRecoverViewController *recoverController;
/// Where the progress HUD was shown, to hide it from the same view.
@property (nullable, nonatomic, weak) UIView *recoverProgressHost;
@property (nonatomic, assign) BOOL popGestureWasEnabled;
/// The last attempt of `recoverWalletCommand` persisted the current
/// network's wallet and failed provisioning the other one: the next
/// execution re-runs the import (which resumes) instead of treating the
/// wallet it left as a finished recovery.
@property (nonatomic, assign) BOOL recoverImportLeftMaterial;

@property (nonatomic, assign) BOOL launchingWasDeferred;

@end

@implementation DWSetupViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Setup" bundle:nil];
    DWSetupViewController *controller = [storyboard instantiateInitialViewController];

    return controller;
}

#pragma mark - Public

- (void)setLaunchingAsDeferredController {
    self.launchingWasDeferred = YES;
}

#pragma mark - Life Cycle

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.recoverAttempts.isInFlight) {
        // Back on this screen while an import runs: the user left the
        // recover flow, so its completion must neither advance setup nor
        // keep a command around. The wallet the import may still persist
        // is found by the next Create/Recover's presence read.
        DWLog(@"SETUP :: recover flow left while an import was in flight; its completion is stale");
        [self.recoverAttempts invalidate];
        [self endRecoverImportBlocking];
        self.recoverWalletCommand = nil;
    }

    if (!self.initialAnimationCompleted) {
        self.initialAnimationCompleted = YES;

        self.logoLayoutViewBottomContraint.constant = CGRectGetHeight([UIScreen mainScreen].bounds) -
                                                      CGRectGetMinY(self.createWalletButton.frame);
        [UIView animateWithDuration:self.launchingWasDeferred ? 0.0 : ANIMATION_DURATION
                         animations:^{
                             [self.view layoutIfNeeded];
                         }];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (IBAction)createWalletButtonAction:(id)sender {
    self.recoverWalletCommand = nil;

    // This screen is only offered on a definite "no wallet", but the keychain
    // is re-read on every step; refuse to start creating over an unreadable
    // one rather than generate a second wallet.
    if (DWWalletEnvironment.isWalletPresenceUnknown) {
        DWLog(@"SETUP :: wallet presence unreadable; refusing to create a wallet");
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nil
                             message:NSLocalizedString(@"Your wallet couldn't be read right now. Please try again.", nil)
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    [DWGlobalOptions sharedInstance].walletNeedsBackup = YES;

    UIViewController *newViewController = [self nextControllerForCreateWalletRoutine];
    NSParameterAssert(newViewController);
    [self.navigationController setViewControllers:@[ self, newViewController ] animated:YES];
}

- (IBAction)recoverWalletButtonAction:(id)sender {
    self.recoverWalletCommand = nil;

    DWRecoverViewController *controller = [[DWRecoverViewController alloc] init];
    controller.action = DWRecoverAction_Recover;
    controller.delegate = self;
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - DWSetPinViewControllerDelegate

- (void)setPinViewControllerDidCancel:(DWSetPinViewController *)controller {
    self.recoverWalletCommand = nil;

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)setPinViewControllerDidSetPin:(DWSetPinViewController *)controller {
    // In case we're recovering, we have a deferred command to create a new wallet.
    // To avoid inconsistency create a new wallet after the pin has been set.
    [self executeRecoverCommandIfAllowedThenContinueSetup];
}

- (DWRecoverImportAttempts *)recoverAttempts {
    if (_recoverAttempts == nil) {
        _recoverAttempts = [[DWRecoverImportAttempts alloc] init];
    }
    return _recoverAttempts;
}

/// The recover screen accepted the phrase against a definite "no wallet"
/// read; the PIN step took time, and the keychain is read again here, once,
/// before the import runs. Only a read that still says "absent" imports:
/// `unknown` is a keychain that cannot be read (the wallet it may hold would
/// get a twin next to it), so the command is kept and the user gets Try
/// Again, or Cancel back to this screen; `present` is a wallet that landed
/// meanwhile (a late migration), so nothing is imported and setup completes
/// into it.
- (void)executeRecoverCommandIfAllowedThenContinueSetup {
    DWRecoverWalletCommand *command = self.recoverWalletCommand;
    if (command != nil) {
        const DWWalletPresence presence = DWWalletEnvironment.walletPresence;
        const DWRecoverImportRoute route = [DWRecoverImportRouting routeAtExecutionWithPresence:presence
                                                                          resumingPartialImport:self.recoverImportLeftMaterial];
        if (route == DWRecoverImportRouteRetryUnreadable) {
            DWLog(@"SETUP :: wallet presence unreadable at recover execution; not importing");
            [self presentRecoverRetryAlertWithMessage:NSLocalizedString(@"Your wallet couldn't be read right now. Please try again.", nil)];
            return;
        }
        if (route == DWRecoverImportRouteImportWallet) {
            // The import persists the mnemonic and creates the wallet off the
            // main queue; setup completes only once it has, so the main
            // screen never opens over a wallet that does not exist yet. A
            // failed import keeps the command behind Try Again. While it
            // runs, input and navigation are blocked (`beginRecoverImportBlocking`)
            // and the attempt token makes a completion for an earlier
            // attempt inert.
            const NSUInteger attempt = [self.recoverAttempts begin];
            [self beginRecoverImportBlocking];
            __weak typeof(self) weakSelf = self;
            [command executeWithCompletion:^(DWRecoverImportOutcome outcome) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf == nil) {
                    return;
                }
                if (![strongSelf.recoverAttempts finish:attempt]) {
                    DWLog(@"SETUP :: recover import completed for an earlier attempt; ignored");
                    return;
                }
                [strongSelf endRecoverImportBlocking];
                if (outcome != DWRecoverImportOutcomeImported) {
                    // `failedAfterPersisting`: the current network's wallet
                    // is stored; Try Again re-runs the same import, which
                    // resumes from it and provisions only what is missing.
                    strongSelf.recoverImportLeftMaterial = (outcome == DWRecoverImportOutcomeFailedAfterPersisting);
                    DWLog(@"SETUP :: recover import did not complete (%@); keeping the command for a retry",
                          strongSelf.recoverImportLeftMaterial ? @"wallet persisted, provisioning incomplete" : @"nothing persisted");
                    [strongSelf presentRecoverRetryAlertWithMessage:NSLocalizedString(@"Your wallet couldn't be recovered right now. Please try again.", nil)];
                    return;
                }
                strongSelf.recoverImportLeftMaterial = NO;
                strongSelf.recoverWalletCommand = nil;
                [strongSelf continueOrCompleteWalletSetup];
            }];
            return;
        }
        DWLog(@"SETUP :: a wallet is present at recover execution; not importing a second one");
        self.recoverWalletCommand = nil;
    }

    [self continueOrCompleteWalletSetup];
}

/// While the import runs: the keyboard goes away and the recover screen
/// takes no input (the text view's Done key would resubmit, or take the
/// wipe route once the wallet lands), the navigation bar's back button and
/// the interactive pop are off, and a progress HUD over the stack shows
/// why. `endRecoverImportBlocking` restores all of it.
- (void)beginRecoverImportBlocking {
    UINavigationController *navigation = self.navigationController;
    [self.recoverController.view endEditing:YES];
    self.recoverController.view.userInteractionEnabled = NO;
    navigation.navigationBar.userInteractionEnabled = NO;
    self.popGestureWasEnabled = navigation.interactivePopGestureRecognizer.enabled;
    navigation.interactivePopGestureRecognizer.enabled = NO;
    UIView *host = navigation.view ?: self.view;
    self.recoverProgressHost = host;
    [host dw_showProgressHUDWithMessage:NSLocalizedString(@"Recovering...", nil)];
}

- (void)endRecoverImportBlocking {
    UINavigationController *navigation = self.navigationController;
    [self.recoverProgressHost dw_hideProgressHUD];
    self.recoverProgressHost = nil;
    self.recoverController.view.userInteractionEnabled = YES;
    navigation.navigationBar.userInteractionEnabled = YES;
    navigation.interactivePopGestureRecognizer.enabled = self.popGestureWasEnabled;
}

/// Try Again re-runs `executeRecoverCommandIfAllowedThenContinueSetup` with
/// the command still in hand; Cancel drops it and returns to this screen.
/// Presented from the navigation controller: the PIN screen may be on top.
- (void)presentRecoverRetryAlertWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Try Again", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                [weakSelf executeRecoverCommandIfAllowedThenContinueSetup];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
                                                __strong typeof(weakSelf) strongSelf = weakSelf;
                                                strongSelf.recoverWalletCommand = nil;
                                                strongSelf.recoverImportLeftMaterial = NO;
                                                [strongSelf.navigationController popToViewController:strongSelf animated:YES];
                                            }]];
    [self.navigationController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - DWBiometricAuthViewControllerDelegate

- (void)biometricAuthViewControllerDidFinish:(DWBiometricAuthViewController *)controller {
    [self continueOrCompleteWalletSetup];
}

#pragma mark - DWSecureWalletDelegate

- (void)secureWalletRoutineDidCancel:(UIViewController *)controller {
    [self completeSetup];
}

- (void)secureWalletRoutineDidVerify:(UIViewController *)controller {
}

- (void)secureWalletRoutineDidFinish:(DWVerifiedSuccessfullyViewController *)controller {
    [self completeSetup];
}

#pragma mark - DWRecoverViewControllerDelegate

- (void)recoverViewControllerDidRecoverWallet:(DWRecoverViewController *)controller
                               recoverCommand:(nonnull DWRecoverWalletCommand *)recoverCommand {
    const DWRecoverImportRoute route = [DWRecoverImportRouting routeAtSubmissionInFlight:self.recoverAttempts.isInFlight
                                                                            shouldSetPin:DWSetPinModel.shouldSetPin];
    if (route == DWRecoverImportRouteIgnoreWhileInFlight) {
        // A submission while the previous import is still persisting the
        // wallet would start a second import; the blocked input normally
        // prevents it.
        DWLog(@"SETUP :: recover submitted while an import is in flight; ignored");
        return;
    }
    self.recoverController = controller;
    self.recoverWalletCommand = recoverCommand;
    self.recoverImportLeftMaterial = NO;

    [DWGlobalOptions sharedInstance].walletNeedsBackup = NO;

    if (route == DWRecoverImportRouteDeferUntilPinSet) {
        // The PIN step's callback executes the command once the PIN is set.
        [self continueOrCompleteWalletSetup];
    }
    else {
        // A PIN already exists — kept through a reinstall, or set by an
        // earlier recover attempt that stopped at the unreadable-wallet
        // alert — so the PIN step, and with it the only callback that
        // executed the command, is skipped. Execute here instead, with the
        // same presence re-read, then continue.
        [self executeRecoverCommandIfAllowedThenContinueSetup];
    }
}

- (void)recoverViewControllerDidWipe:(DWRecoverViewController *)controller {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Private

- (void)setupView {
    [self.createWalletButton setTitle:NSLocalizedString(@"Create a New Wallet", nil) forState:UIControlStateNormal];
    [self.recoverWalletButton setTitle:NSLocalizedString(@"Recover Wallet", nil) forState:UIControlStateNormal];
}

- (nullable UIViewController *)nextControllerForCreateWalletRoutine {
    if (DWSetPinModel.shouldSetPin) {
        return [self setPinController];
    }
    else if (DWBiometricAuthModel.shouldEnableBiometricAuthentication && DWBiometricAuthModel.biometricAuthenticationAvailable) {
        return [self biometricAuthController];
    }
    else if (DWPreviewSeedPhraseModel.shouldVerifyPassphrase) {
        return [self secureWalletInfoController];
    }

    return nil;
}

- (UIViewController *)setPinController {
    DWSetPinViewController *controller = [DWSetPinViewController controllerWithIntent:DWSetPinIntent_CreateNewWallet];
    controller.delegate = self;

    return controller;
}

- (UIViewController *)biometricAuthController {
    DWBiometricAuthViewController *controller = [DWBiometricAuthViewController controller];
    controller.delegate = self;

    return controller;
}

- (UIViewController *)secureWalletInfoController {
    DWBackupInfoViewController *controller = [DWBackupInfoViewController controllerWith:DWSecureWalletInfoType_Setup];
    controller.delegate = self;
    controller.isCloseButtonHidden = true;
    controller.isSkipButtonHidden = false;
    return controller;
}

- (void)continueOrCompleteWalletSetup {
    UIViewController *newViewController = [self nextControllerForCreateWalletRoutine];
    if (newViewController) {
        [self.navigationController setViewControllers:@[ self, newViewController ] animated:YES];
    }
    else {
        [self completeSetup];
    }
}

- (void)completeSetup {
    // Setup can complete into a wallet nothing started: one that an earlier
    // attempt persisted, or one found present at recover execution. A
    // successful create/import already asked for this; the runtime elides
    // a refresh it has satisfied, so asking again is cheap, and the main
    // screen never opens over a stopped runtime.
    [DWSwiftDashSDKWalletRuntime handleWalletMaterialChanged];
    [self.delegate setupViewControllerDidFinish:self];
}

@end

NS_ASSUME_NONNULL_END
