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
#import "DWMainTabbarViewController.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWRecoverViewController.h"
#import "DWSecureWalletInfoViewController.h"
#import "DWSetPinModel.h"
#import "DWSetPinViewController.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ANIMATION_DURATION = 0.25;

@interface DWSetupViewController () <DWSetPinViewControllerDelegate,
                                     DWBiometricAuthViewControllerDelegate,
                                     DWSecureWalletDelegate,
                                     DWRecoverViewControllerDelegate>

@property (nonatomic, assign) BOOL initialAnimationCompleted;

@property (strong, nonatomic) IBOutlet UIButton *createWalletButton;
@property (strong, nonatomic) IBOutlet UIButton *recoverWalletButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *logoLayoutViewBottomContraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@property (nullable, nonatomic, strong) DWRecoverWalletCommand *recoverWalletCommand;

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
    [self.recoverWalletCommand execute];
    self.recoverWalletCommand = nil;

    [self continueOrCompleteWalletSetup];
}

#pragma mark - DWBiometricAuthViewControllerDelegate

- (void)biometricAuthViewControllerDidFinish:(DWBiometricAuthViewController *)controller {
    [self continueOrCompleteWalletSetup];
}

#pragma mark - DWSecureWalletDelegate

- (void)secureWalletRoutineDidCanceled:(UIViewController *)controller {
    [self completeSetup];
}

- (void)secureWalletRoutineDidVerify:(UIViewController *)controller { }

- (void)secureWalletRoutineDidFinish:(DWVerifiedSuccessfullyViewController *)controller {
    [self completeSetup];
}

- (void)secureWalletInfoViewControllerDidFinish:(DWSecureWalletInfoViewController *)controller {
    [self.navigationController popViewControllerAnimated:NO];
}

#pragma mark - DWRecoverViewControllerDelegate

- (void)recoverViewControllerDidRecoverWallet:(DWRecoverViewController *)controller
                               recoverCommand:(nonnull DWRecoverWalletCommand *)recoverCommand {
    // Defer recovering until a pin is set
    self.recoverWalletCommand = recoverCommand;

    [DWGlobalOptions sharedInstance].walletNeedsBackup = NO;

    [self continueOrCompleteWalletSetup];
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
    DWSecureWalletInfoViewController *controller = [DWSecureWalletInfoViewController controller];
    controller.type = DWSecureWalletInfoType_Setup;
    controller.delegate = self;

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
    [self.delegate setupViewControllerDidFinish:self];
}

@end

NS_ASSUME_NONNULL_END
