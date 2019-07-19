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
#import "DWCreateNewWalletModel.h"
#import "DWCreateNewWalletViewController.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWRootModel.h"
#import "DWSecureWalletInfoViewController.h"

// TODO: rm
#import "DWPreviewSeedPhraseViewController.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ANIMATION_DURATION = 0.25;

@interface DWSetupViewController () <DWCreateNewWalletViewControllerDelegate, DWBiometricAuthViewControllerDelegate, DWSecureWalletInfoViewControllerDelegate>

@property (nonatomic, strong) DWRootModel *model;
@property (nonatomic, assign) BOOL initialAnimationCompleted;

@property (strong, nonatomic) IBOutlet UIButton *createWalletButton;
@property (strong, nonatomic) IBOutlet UIButton *recoverWalletButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *logoLayoutViewBottomContraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWSetupViewController

+ (instancetype)controllerWithModel:(DWRootModel *)model {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Setup" bundle:nil];
    DWSetupViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = model;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (!self.model.walletOperationAllowed) {
        [self showDevicePasscodeAlert];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (!self.initialAnimationCompleted) {
        self.initialAnimationCompleted = YES;

        self.logoLayoutViewBottomContraint.constant = CGRectGetHeight([UIScreen mainScreen].bounds) -
                                                      CGRectGetMinY(self.createWalletButton.frame);
        [UIView animateWithDuration:ANIMATION_DURATION
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
    UIViewController *newViewController = [self nextControllerForCreateWalletRoutine];
    NSParameterAssert(newViewController);
    [self.navigationController setViewControllers:@[ self, newViewController ] animated:YES];
}

- (IBAction)recoverWalletButtonAction:(id)sender {
    DWPreviewSeedPhraseViewController *c = [DWPreviewSeedPhraseViewController controllerForNewWallet];
    [self.navigationController pushViewController:c animated:YES];
}

#pragma mark - DWCreateNewWalletViewControllerDelegate

- (void)createNewWalletViewControllerDidCancel:(DWCreateNewWalletViewController *)controller {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)createNewWalletViewControllerDidSetPin:(DWCreateNewWalletViewController *)controller {
    UIViewController *newViewController = [self nextControllerForCreateWalletRoutine];
    NSParameterAssert(newViewController);
    [self.navigationController setViewControllers:@[ self, newViewController ] animated:YES];
}

#pragma mark - DWBiometricAuthViewControllerDelegate

- (void)biometricAuthViewControllerDidFinish:(DWBiometricAuthViewController *)controller {
    UIViewController *newViewController = [self nextControllerForCreateWalletRoutine];
    NSParameterAssert(newViewController);
    [self.navigationController setViewControllers:@[ self, newViewController ] animated:YES];
}

#pragma mark - DWSecureWalletInfoViewController

- (void)secureWalletInfoViewControllerDidFinish:(DWSecureWalletInfoViewController *)controller {
    [self.navigationController popViewControllerAnimated:NO];
}

#pragma mark - DWRootNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Private

- (void)setupView {
    [self.createWalletButton setTitle:NSLocalizedString(@"Create a New Wallet", nil) forState:UIControlStateNormal];
    [self.recoverWalletButton setTitle:NSLocalizedString(@"Recover Wallet", nil) forState:UIControlStateNormal];
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

- (nullable UIViewController *)nextControllerForCreateWalletRoutine {
    if (DWCreateNewWalletModel.shouldSetPin) {
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
    DWCreateNewWalletViewController *controller = [DWCreateNewWalletViewController controller];
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
    controller.delegate = self;

    return controller;
}

@end

NS_ASSUME_NONNULL_END
