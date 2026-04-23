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

- (void)handleFile:(NSData *)file {
    [self.rootController handleFile:file];
}

#pragma mark - DWOnboardingViewControllerDelegate

- (void)onboardingViewControllerDidFinish:(DWOnboardingViewController *)controller {
    [self onboardingDidFinish];

    // Reinstall detection: if DashSync's keychain survived the wipe but
    // UserDefaults didn't, `chain.hasAWallet` is YES at this exact moment
    // and the default transition to `DWAppRootViewController` would jump
    // straight to the wallet home without ever asking the user. Gate the
    // transition behind a Keep/Delete prompt, mirroring the SwiftExampleApp
    // orphan-mnemonic UX.
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    if (!chain.hasAWallet) {
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
                                            // Posts DWWillWipeWalletNotification, which
                                            // `SwiftDashSDKWalletWiper` observes to clear
                                            // the SwiftDashSDK keychain + runtime state.
                                            [[DWEnvironment sharedInstance] clearAllWalletsAndRemovePin:YES];
                                        }
                                        [strongSelf transitionToAppRoot];
                                    }];
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
