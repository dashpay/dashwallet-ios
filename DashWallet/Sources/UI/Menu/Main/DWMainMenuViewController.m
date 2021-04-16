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

#import "DWMainMenuViewController.h"

#import "DWAboutModel.h"
#import "DWDashPaySetupFlowController.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWInvitationHistoryViewController.h"
#import "DWMainMenuContentView.h"
#import "DWMainMenuModel.h"
#import "DWNavigationController.h"
#import "DWRootEditProfileViewController.h"
#import "DWSecurityMenuViewController.h"
#import "DWSettingsMenuViewController.h"
#import "DWToolsMenuViewController.h"
#import "DWUpholdViewController.h"
#import "DWUserProfileModalQRViewController.h"
#import "SFSafariViewController+DashWallet.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMainMenuViewController () <DWMainMenuContentViewDelegate,
                                        DWToolsMenuViewControllerDelegate,
                                        DWSettingsMenuViewControllerDelegate,
                                        DWRootEditProfileViewControllerDelegate>

@property (nonatomic, strong) DWMainMenuContentView *view;
@property (nonatomic, strong) id<DWBalanceDisplayOptionsProtocol> balanceDisplayOptions;
@property (nonatomic, strong) id<DWReceiveModelProtocol> receiveModel;
@property (nonatomic, strong) id<DWDashPayReadyProtocol> dashPayReady;
@property (nonatomic, strong) id<DWDashPayProtocol> dashPayModel;
@property (nonatomic, strong) DWCurrentUserProfileModel *userProfileModel;

@end

@implementation DWMainMenuViewController

@dynamic view;

- (instancetype)initWithBalanceDisplayOptions:(id<DWBalanceDisplayOptionsProtocol>)balanceDisplayOptions
                                 receiveModel:(id<DWReceiveModelProtocol>)receiveModel
                                 dashPayReady:(id<DWDashPayReadyProtocol>)dashPayReady
                                 dashPayModel:(id<DWDashPayProtocol>)dashPayModel
                             userProfileModel:(DWCurrentUserProfileModel *)userProfileModel {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _balanceDisplayOptions = balanceDisplayOptions;
        _receiveModel = receiveModel;
        _dashPayReady = dashPayReady;
        _dashPayModel = dashPayModel;
        _userProfileModel = userProfileModel;

        self.title = NSLocalizedString(@"More", nil);
    }
    return self;
}

- (void)loadView {
    const CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWMainMenuContentView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.delegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.userModel = self.userProfileModel;
    self.view.dashPayReady = self.dashPayReady;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    BOOL invitationsEnabled =
        ([DWGlobalOptions sharedInstance].dpInvitationFlowEnabled &&
         (self.userProfileModel.blockchainIdentity != nil));
    self.view.model = [[DWMainMenuModel alloc] initWithInvitesEnabled:invitationsEnabled];

    [self.view updateUserHeader];
}

#pragma mark - DWMainMenuContentViewDelegate

- (void)mainMenuContentView:(DWMainMenuContentView *)view didSelectMenuItem:(id<DWMainMenuItem>)item {
    switch (item.type) {
        case DWMainMenuItemType_BuySellDash: {
            DSChainType chainType = [DWEnvironment sharedInstance].currentChain.chainType;
            if (chainType != DSChainType_MainNet && chainType != DSChainType_TestNet) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Not Available For Devnet", nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil];
                [alert addAction:ok];

                [self presentViewController:alert animated:YES completion:nil];

                return;
            }

            [[DSAuthenticationManager sharedInstance]
                      authenticateWithPrompt:nil
                usingBiometricAuthentication:[DWGlobalOptions sharedInstance].biometricAuthEnabled
                              alertIfLockout:YES
                                  completion:^(BOOL authenticated, BOOL usedBiometrics, BOOL cancelled) {
                                      if (authenticated) {
                                          UIViewController *controller = [DWUpholdViewController controller];
                                          DWNavigationController *navigationController =
                                              [[DWNavigationController alloc] initWithRootViewController:controller];
                                          [self presentViewController:navigationController animated:YES completion:nil];
                                      }
                                  }];

            break;
        }
        case DWMainMenuItemType_Security: {
            DWSecurityMenuViewController *controller = [[DWSecurityMenuViewController alloc] initWithBalanceDisplayOptions:self.balanceDisplayOptions];
            controller.delegate = self.delegate;
            [self.navigationController pushViewController:controller animated:YES];

            break;
        }
        case DWMainMenuItemType_Settings: {
            DWSettingsMenuViewController *controller = [[DWSettingsMenuViewController alloc] init];
            controller.delegate = self;
            [self.navigationController pushViewController:controller animated:YES];

            break;
        }
        case DWMainMenuItemType_Tools: {
            DWToolsMenuViewController *controller = [[DWToolsMenuViewController alloc] init];
            controller.delegate = self;
            [self.navigationController pushViewController:controller animated:YES];

            break;
        }
        case DWMainMenuItemType_Support: {
            NSURL *url = [DWAboutModel supportURL];
            NSParameterAssert(url);
            if (!url) {
                return;
            }

            SFSafariViewController *safariViewController = [SFSafariViewController dw_controllerWithURL:url];
            [self presentViewController:safariViewController animated:YES completion:nil];
            break;
        }
        case DWMainMenuItemType_Invite: {
            DWInvitationHistoryViewController *controller = [[DWInvitationHistoryViewController alloc] init];
            controller.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:controller animated:YES];
            break;
        }
    }
}

- (void)mainMenuContentView:(DWMainMenuContentView *)view showQRAction:(UIButton *)sender {
    DWUserProfileModalQRViewController *controller = [[DWUserProfileModalQRViewController alloc] initWithModel:self.receiveModel];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)mainMenuContentView:(DWMainMenuContentView *)view editProfileAction:(UIButton *)sender {
    DWRootEditProfileViewController *controller = [[DWRootEditProfileViewController alloc] init];
    controller.delegate = self;
    DWNavigationController *navigation = [[DWNavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)mainMenuContentView:(DWMainMenuContentView *)view joinDashPayAction:(UIButton *)sender {
    DWDashPaySetupFlowController *controller = [[DWDashPaySetupFlowController alloc]
        initWithDashPayModel:self.dashPayModel];
    controller.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - DWToolsMenuViewControllerDelegate

- (void)toolsMenuViewControllerImportPrivateKey:(DWToolsMenuViewController *)controller {
    [self.navigationController popToRootViewControllerAnimated:NO];
    [self.delegate mainMenuViewControllerImportPrivateKey:self];
}

#pragma mark - DWSettingsMenuViewControllerDelegate

- (void)settingsMenuViewControllerDidRescanBlockchain:(DWSettingsMenuViewController *)controller {
    [self.navigationController popToRootViewControllerAnimated:NO];
    [self.delegate mainMenuViewControllerOpenHomeScreen:self];
}

#pragma mark - DWRootEditProfileViewControllerDelegate

- (void)editProfileViewController:(DWRootEditProfileViewController *)controller
                updateDisplayName:(NSString *)rawDisplayName
                          aboutMe:(NSString *)rawAboutMe
                  avatarURLString:(nullable NSString *)avatarURLString {
    [self.view.userModel.updateModel updateWithDisplayName:rawDisplayName aboutMe:rawAboutMe avatarURLString:avatarURLString];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)editProfileViewControllerDidCancel:(DWRootEditProfileViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
