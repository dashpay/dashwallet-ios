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

/// Links delivered before the root controller exists (onboarding still on
/// screen), in arrival order; handed to the root at its creation. The
/// newest `DWDeepLinkQueue.capacity`, as the queue itself would keep.
@property (nonatomic, strong) NSMutableArray<NSURL *> *deferredLinks;

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
    // One keychain read decides both the skip and the preference write:
    // the migrator can set its done sentinel between two probes, which
    // would skip the carousel now and still let it play next launch.
    const BOOL legacyMaterialPresent = [DWSwiftDashSDKKeyMigrator legacyWalletMaterialPresent];
    if ([self shouldDisplayOnboardingWithLegacyMaterialPresent:legacyMaterialPresent]) {
        DWOnboardingViewController *onboarding = [DWOnboardingViewController controller];
        onboarding.delegate = self;
        [self transitionToController:onboarding];
    }
    else {
        if (legacyMaterialPresent) {
            // The upgrader's carousel is skipped for good, not merely for
            // this launch: otherwise it would play on the next launch, over
            // the migrated wallet. Written only on a confirmed read of the
            // legacy material — never on a keychain error, which on a fresh
            // install would leave a permanent mark with no wallet behind it.
            [DWGlobalOptions sharedInstance].shouldDisplayOnboarding = NO;
        }
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
    [self handleURL:url];
}
#endif

- (void)handleURL:(NSURL *)url {
    // `application:openURL:` is delivered after `didFinishLaunching` has made
    // the window key, so `viewDidLoad` has normally already built the root
    // controller. What is left is onboarding still holding the screen (the
    // carousel, or a reinstall's Keep/Delete choice) with the root controller
    // not yet in existence. The link waits here, every one of them in order,
    // and joins the root's queue at its creation.
    if (self.rootController) {
        [self.rootController handleURL:url];
    }
    else {
        if (self.deferredLinks == nil) {
            self.deferredLinks = [NSMutableArray array];
        }
        [self.deferredLinks addObject:url];
        if (self.deferredLinks.count > DWDeepLinkQueue.capacity) {
            [self.deferredLinks removeObjectAtIndex:0];
            DWLog(@"LINKS a link kept before the root existed was dropped for a newer one (%lu kept)",
                  (unsigned long)self.deferredLinks.count);
        }
    }
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

- (BOOL)shouldDisplayOnboardingWithLegacyMaterialPresent:(BOOL)legacyMaterialPresent {
    // The carousel is a new-user intro. An upgrader whose DashSync wallet
    // is pending migration skips it: the root controller's migration hold
    // presents their wallet (behind the lock screen) directly, instead of
    // marketing playing while the wallet is milliseconds from appearing.
    // The reinstall case (SDK wallet material with wiped defaults) keeps
    // the carousel — its Keep/Delete prompt is wired to the carousel's
    // completion.
    // `legacyMaterialPresent` is the confirmed read; an unreadable keychain
    // (the pending probe without the present one) also skips, but writes
    // nothing.
    if (legacyMaterialPresent || [DWSwiftDashSDKKeyMigrator legacyWalletMaterialPendingMigration]) {
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

    for (NSURL *url in self.deferredLinks) {
        [controller handleURL:url];
    }
    self.deferredLinks = nil;

    return controller;
}

@end

NS_ASSUME_NONNULL_END
