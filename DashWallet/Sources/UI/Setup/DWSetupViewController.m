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
#import "DWMainTabbarViewController.h"
#import "DWNavigationController.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWSecureWalletInfoViewController.h"
#import "DWSetPinModel.h"
#import "DWSetPinViewController.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ANIMATION_DURATION = 0.25;

@interface DWSetupViewController () <DWSetPinViewControllerDelegate,
                                     DWBiometricAuthViewControllerDelegate,
                                     DWSecureWalletDelegate>

@property (nonatomic, assign) BOOL initialAnimationCompleted;

@property (strong, nonatomic) IBOutlet UIButton *createWalletButton;
@property (strong, nonatomic) IBOutlet UIButton *recoverWalletButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *logoLayoutViewBottomContraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWSetupViewController

+ (UIViewController *)controllerEmbededInNavigationWithDelegate:(id<DWSetupViewControllerDelegate>)delegate {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Setup" bundle:nil];
    DWSetupViewController *controller = [storyboard instantiateInitialViewController];
    controller.delegate = delegate;

    DWNavigationController *navigationController = [[DWNavigationController alloc] initWithRootViewController:controller];

    return navigationController;
}

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
    // TODO: for test purposes
    [self completeSetup];
}

#pragma mark - DWSetPinViewControllerDelegate

- (void)setPinViewControllerDidCancel:(DWSetPinViewController *)controller {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)setPinViewControllerDidSetPin:(DWSetPinViewController *)controller {
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

#pragma mark - DWSecureWalletDelegate

- (void)secureWalletRoutineDidCanceled:(DWSecureWalletInfoViewController *)controller {
    [self completeSetup];
}

- (void)secureWalletRoutineDidVerify:(DWVerifiedSuccessfullyViewController *)controller {
    [self completeSetup];
}

- (void)secureWalletInfoViewControllerDidFinish:(DWSecureWalletInfoViewController *)controller {
    [self.navigationController popViewControllerAnimated:NO];
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
    DWSetPinViewController *controller = [DWSetPinViewController controller];
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

- (void)completeSetup {
    [self.delegate setupViewControllerDidFinish:self];
}

@end

NS_ASSUME_NONNULL_END
