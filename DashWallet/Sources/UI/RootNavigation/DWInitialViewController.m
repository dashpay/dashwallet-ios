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

#import <DashSync/DashSync.h>

#import "DWAppRootViewController.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWOnboardingViewController.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"
#import "dashwallet-Swift.h"

#if SNAPSHOT
#import "DWDemoAppRootViewController.h"
#endif /* SNAPSHOT */

NS_ASSUME_NONNULL_BEGIN

@interface DWInitialViewController () <DWOnboardingViewControllerDelegate>

@property (nonatomic, assign) BOOL launchingWasDeferred;
@property (nullable, nonatomic, strong) DWAppRootViewController *rootController;

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

    // Reinstall detection: if wallet keychain material survived the wipe
    // (DashSync's registration or the SDK mnemonic — `hasWallet` unions both)
    // while UserDefaults didn't, the default transition to
    // `DWAppRootViewController` would jump straight to the wallet home
    // without ever asking the user. Gate the transition behind a Keep/Delete
    // prompt, mirroring the SwiftExampleApp orphan-mnemonic UX. (Delete
    // clears the SDK keychain too, via DWWillWipeWalletNotification → wiper;
    // Keep rides the KeyMigrator re-run until C6-C makes it first-class.)
    if (!DWWalletEnvironment.hasWallet) {
        [self transitionToAppRoot];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [DWKeychainWalletRecoveryCoordinator
        presentReinstallKeepOrDeleteChoiceFrom:controller
                                    completion:^(BOOL keep) {
                                        typeof(self) strongSelf = weakSelf;
                                        if (strongSelf == nil) {
                                            return;
                                        }
                                        if (!keep) {
                                            [strongSelf deleteRecoveredWalletThenTransitionFromController:controller];
                                            return;
                                        }
                                        [strongSelf transitionToAppRoot];
                                    }];
}

- (void)deleteRecoveredWalletThenTransitionFromController:(UIViewController *)controller {
    [controller.view dw_showProgressHUDWithMessage:NSLocalizedString(@"Deleting Wallet…", nil)];

    __weak typeof(self) weakSelf = self;
    // `PlatformWalletManager.deleteWallet` is synchronous and blocks the main
    // thread. Give UIKit enough time to commit the HUD's first frame before
    // starting the wipe; a zero-delay main-queue dispatch can still run before
    // the current render pass and leave the user staring at a frozen screen.
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC));
    dispatch_after(startTime, dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        // This synchronously removes the PIN and posts
        // DWWillWipeWalletNotification. The SDK observer performs its Keychain /
        // runtime deletion asynchronously, so entering app root immediately can
        // observe a stale wallet and present a PIN screen after the PIN is gone.
        [[DWEnvironment sharedInstance] clearAllWalletsAndRemovePin:YES];

        [DWSwiftDashSDKWalletWiper waitForPendingWipeWithCompletion:^(BOOL wipeSucceeded) {
            typeof(self) completedSelf = weakSelf;
            if (completedSelf == nil) {
                return;
            }
            [controller.view dw_hideProgressHUD];
            if (!wipeSucceeded) {
                [completedSelf presentRecoveredWalletDeleteFailureFromController:controller];
                return;
            }
            [completedSelf transitionToAppRoot];
        }];
    });
}

- (void)presentRecoveredWalletDeleteFailureFromController:(UIViewController *)controller {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Couldn’t Delete Wallet", nil)
                                            message:NSLocalizedString(@"The wallet is still stored on this device. Please try again.", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Retry", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_Nonnull action) {
                                                typeof(self) strongSelf = weakSelf;
                                                if (strongSelf != nil) {
                                                    [strongSelf deleteRecoveredWalletThenTransitionFromController:controller];
                                                }
                                            }]];
    [controller presentViewController:alert animated:YES completion:nil];
}

- (void)transitionToAppRoot {
    DWAppRootViewController *rootController = [self createRootController];
    [rootController setLaunchingAsDeferredController]; // always deferred after onboarding
    [self transitionToController:rootController];
    self.rootController = rootController;
}

#pragma mark - Private

- (BOOL)shouldDisplayOnboarding {
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
