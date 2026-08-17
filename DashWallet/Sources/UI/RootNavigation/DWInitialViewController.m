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

#import "DWInitialViewController.h"

#import "DWAppRootViewController.h"
#import "DWGlobalOptions.h"
#import "DWOnboardingViewController.h"
#import "DWRecoverViewController.h"
#import "DWUIKit.h"
#import "dashwallet-Swift.h"

#if SNAPSHOT
#import "DWDemoAppRootViewController.h"
#endif /* SNAPSHOT */

NS_ASSUME_NONNULL_BEGIN

@interface DWInitialViewController () <DWOnboardingViewControllerDelegate, DWRecoverViewControllerDelegate>

@property (nonatomic, assign) BOOL launchingWasDeferred;
@property (nullable, nonatomic, strong) DWAppRootViewController *rootController;
@property (nullable, nonatomic, weak) UIViewController *reinstallWalletChoiceController;

#if DASHPAY
@property (nullable, nonatomic, strong) NSURL *deferredDeeplink;
#endif

@end

@implementation DWInitialViewController

#pragma mark - Life Cycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

#if SNAPSHOT
    DWDemoAppRootViewController *controller = [[DWDemoAppRootViewController alloc] init];
    [self transitionToController:controller];
#else
    if ([self shouldDisplayOnboarding]) {
        DWOnboardingViewController *onboarding = [DWOnboardingViewController controller];
        onboarding.delegate = self;
        [self transitionToController:onboarding];
    }
    else {
        DWAppRootViewController *rootController = [self createRootController];
        [self transitionToController:rootController];
        self.rootController = rootController;
    }
#endif /* SNAPSHOT */
}

#pragma mark - Public

- (void)setLaunchingAsDeferredController {
    self.launchingWasDeferred = YES;
    [self.rootController setLaunchingAsDeferredController];
}

#if DASHPAY
- (void)handleDeeplink:(NSURL *)url {
    if (self.rootController) {
        [self.rootController handleDeeplink:url];
    }
    else {
        self.deferredDeeplink = url;
    }
}
#endif

- (void)handleURL:(NSURL *)url {
    [self.rootController handleURL:url];
}

#pragma mark - DWOnboardingViewControllerDelegate

- (void)onboardingViewControllerDidFinish:(DWOnboardingViewController *)controller {
    [self onboardingDidFinish];

    [self presentReinstallWalletChoiceFromController:controller];
}

- (void)presentReinstallWalletChoiceFromController:(UIViewController *)controller {
    self.reinstallWalletChoiceController = controller;

    // Reinstall detection must use the coordinator's strict, set-wide
    // inventory. The old Boolean presence check treated a Keychain read error
    // as "no wallet" and could skip the Keep/Delete All prompt entirely.
    __weak typeof(self) weakSelf = self;
    [DWKeychainWalletRecoveryCoordinator
        presentReinstallKeepOrDeleteChoiceFrom:controller
                                    completion:^(BOOL keep) {
                                        typeof(self) strongSelf = weakSelf;
                                        if (strongSelf == nil) {
                                            return;
                                        }
                                        if (!keep) {
                                            [strongSelf presentReinstallSupportWipeFromController:controller];
                                            return;
                                        }
                                        strongSelf.reinstallWalletChoiceController = nil;
                                        [strongSelf transitionToAppRoot];
                                    }];
}

- (void)presentReinstallSupportWipeFromController:(UIViewController *)host {
    DWRecoverViewController *controller = [[DWRecoverViewController alloc] init];
    controller.action = DWRecoverAction_SupportWipe;
    controller.delegate = self;
    UIBarButtonItem *cancelButton =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(reinstallSupportWipeCancelAction:)];
    controller.navigationItem.rightBarButtonItem = cancelButton;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:navigationController animated:YES completion:nil];
}

- (void)reinstallSupportWipeCancelAction:(id)sender {
    UIViewController *host = self.reinstallWalletChoiceController;
    if (host == nil) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [host dismissViewControllerAnimated:YES
                             completion:^{
                                 typeof(self) strongSelf = weakSelf;
                                 if (strongSelf != nil) {
                                     [strongSelf presentReinstallWalletChoiceFromController:host];
                                 }
                             }];
}

#pragma mark - DWRecoverViewControllerDelegate

- (void)recoverViewControllerDidWipe:(DWRecoverViewController *)controller {
    NSAssert(controller.action == DWRecoverAction_SupportWipe, @"Only support wipe is presented during reinstall");
    UIViewController *host = self.reinstallWalletChoiceController;
    self.reinstallWalletChoiceController = nil;
    if (host == nil) {
        [self transitionToAppRoot];
        return;
    }
    [host dismissViewControllerAnimated:YES
                             completion:^{
                                 [self transitionToAppRoot];
                             }];
}

- (void)recoverViewControllerDidRecoverWallet:(DWRecoverViewController *)controller
                               recoverCommand:(DWRecoverWalletCommand *)recoverCommand {
    NSAssert(NO, @"Support wipe never recovers a wallet");
    [self reinstallSupportWipeCancelAction:nil];
}

- (void)transitionToAppRoot {
    DWAppRootViewController *rootController = [self createRootController];
    [rootController setLaunchingAsDeferredController]; // always deferred after onboarding
    [self transitionToController:rootController];
    self.rootController = rootController;
}

#pragma mark - Private

- (BOOL)shouldDisplayOnboarding {
    // The carousel is a new-user intro. An upgrader whose DashSync wallet
    // is pending migration skips it: the root controller's migration hold
    // presents their wallet (behind the lock screen) directly, instead of
    // marketing playing while the wallet is milliseconds from appearing.
    // The reinstall case (SDK wallet material with wiped defaults) keeps
    // the carousel — its Keep/Delete prompt is wired to the carousel's
    // completion.
    if ([DWSwiftDashSDKKeyMigrator legacyWalletMaterialPendingMigration]) {
        return NO;
    }
    return [DWGlobalOptions sharedInstance].shouldDisplayOnboarding;
}

- (void)onboardingDidFinish {
    [DWGlobalOptions sharedInstance].shouldDisplayOnboarding = NO;
}

- (DWAppRootViewController *)createRootController {
    DWAppRootViewController *controller = [[DWAppRootViewController alloc] init];
    if (self.launchingWasDeferred) {
        [controller setLaunchingAsDeferredController];
    }

#if DASHPAY
    if (self.deferredDeeplink) {
        [controller handleDeeplink:self.deferredDeeplink];
        self.deferredDeeplink = nil;
    }
#endif

    return controller;
}

@end

NS_ASSUME_NONNULL_END
