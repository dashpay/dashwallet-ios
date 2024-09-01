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

#import <DashSync/DashSync.h>

#import "DWAboutModel.h"
#import "DWExploreTestnetViewController.h"
#import "DWGlobalOptions.h"
#import "DWMainMenuContentView.h"
#import "DWMainMenuModel.h"
#import "DWSecurityMenuViewController.h"
#import "SFSafariViewController+DashWallet.h"
#import "dashwallet-Swift.h"

#ifdef DASHPAY
#import "DWUserProfileModalQRViewController.h"
#import "DWInvitationHistoryViewController.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface DWMainMenuViewController () <DWMainMenuContentViewDelegate,
                                        DWToolsMenuViewControllerDelegate,
                                        DWSettingsMenuViewControllerDelegate,
                                        DWExploreTestnetViewControllerDelegate,
                                        DWRootEditProfileViewControllerDelegate>

@property (nonatomic, strong) DWMainMenuContentView *view;
@property (nonatomic, strong) id<DWReceiveModelProtocol> receiveModel;
#if DASHPAY
@property (nonatomic, strong) id<DWDashPayReadyProtocol> dashPayReady;
@property (nonatomic, strong) id<DWDashPayProtocol> dashPayModel;
@property (nonatomic, strong) DWCurrentUserProfileModel *userProfileModel;
#endif

@end

@implementation DWMainMenuViewController

@dynamic view;

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = NSLocalizedString(@"More", nil);
    }
    return self;
}

#if DASHPAY
- (instancetype)initWithDashPayModel:(id<DWDashPayProtocol>)dashPayModel
                        receiveModel:(id<DWReceiveModelProtocol>)receiveModel
                        dashPayReady:(id<DWDashPayReadyProtocol>)dashPayReady
                    userProfileModel:(DWCurrentUserProfileModel *)userProfileModel {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _receiveModel = receiveModel;
        _dashPayReady = dashPayReady;
        _dashPayModel = dashPayModel;
        _userProfileModel = userProfileModel;

        self.title = NSLocalizedString(@"More", nil);
    }
    return self;
}
#endif

- (void)loadView {
    const CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWMainMenuContentView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.delegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
#if DASHPAY
    self.view.userModel = self.userProfileModel;
    self.view.dashPayReady = self.dashPayReady;
#endif
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    
#ifdef DASHPAY
    BOOL invitationsEnabled = ([DWGlobalOptions sharedInstance].dpInvitationFlowEnabled && (self.userProfileModel.blockchainIdentity != nil));
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL isVotingEnabled = [VotingPrefsWrapper getIsEnabled] && now < VotingConstants.votingEndTime;
    self.view.model = [[DWMainMenuModel alloc] initWithInvitesEnabled:invitationsEnabled votingEnabled:isVotingEnabled];
    [self.view updateUserHeader];
#else
    self.view.model = [[DWMainMenuModel alloc] initWithInvitesEnabled:NO votingEnabled:NO];
#endif
    
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWMainMenuContentViewDelegate

- (void)mainMenuContentView:(DWMainMenuContentView *)view didSelectMenuItem:(id<DWMainMenuItem>)item {
    switch (item.type) {
        case DWMainMenuItemType_BuySellDash: {
            [[DSAuthenticationManager sharedInstance]
                      authenticateWithPrompt:nil
                usingBiometricAuthentication:[DWGlobalOptions sharedInstance].biometricAuthEnabled
                              alertIfLockout:YES
                                  completion:^(BOOL authenticated, BOOL usedBiometrics, BOOL cancelled) {
                                      if (authenticated) {
                                          BuySellPortalViewController *controller = [BuySellPortalViewController controller];
                                          controller.hidesBottomBarWhenPushed = true;
                                          [self.navigationController pushViewController:controller animated:YES];
                                      }
                                  }];

            break;
        }
        case DWMainMenuItemType_Explore: {
            DWExploreTestnetViewController *controller = [[DWExploreTestnetViewController alloc] init];
            controller.delegate = self;
            DWNavigationController *nvc = [[DWNavigationController alloc] initWithRootViewController:controller];
            [self presentViewController:nvc animated:YES completion:nil];

            break;
        }
        case DWMainMenuItemType_Security: {
            DWSecurityMenuViewController *controller = [[DWSecurityMenuViewController alloc] init];
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
#if DASHPAY
        case DWMainMenuItemType_Invite: {
            DWInvitationHistoryViewController *controller = [[DWInvitationHistoryViewController alloc] init];
            controller.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:controller animated:YES];
            break;
        }
        case DWMainMenuItemType_Voting: {
            UsernameVotingViewController *controller = [UsernameVotingViewController controller];
            controller.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:controller animated:YES];
            break;
        }
#endif
    }
}

#if DASHPAY
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
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL isVotingEnabled = [VotingPrefsWrapper getIsEnabled] && now < VotingConstants.votingEndTime;
    
    if (isVotingEnabled) {
        UIViewController *controller = [RequestUsernameVMObjcWrapper getRootVCWith:^(BOOL result) {
            if (result) {
                [self.view dw_showInfoHUDWithText:NSLocalizedString(@"Username was successfully requested", @"Usernames") offsetForNavBar:YES];
            } else {
                [self.view dw_showInfoHUDWithText:NSLocalizedString(@"Your request was cancelled", @"Usernames") offsetForNavBar:YES];
            }
        }];
        
        controller.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:controller animated:YES];
    } else {
        DWDashPaySetupFlowController *controller =
            [[DWDashPaySetupFlowController alloc]
                initWithDashPayModel:self.dashPayModel
                       invitationURL:nil
                     definedUsername:nil];
        controller.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:controller animated:YES completion:nil];
    }
}
#endif

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

#pragma mark - DWExploreTestnetViewControllerDelegate
- (void)exploreTestnetViewControllerShowSendPayment:(DWExploreTestnetViewController *)controller {
    [self.delegate showPaymentsControllerWithActivePage:DWPaymentsViewControllerIndex_Pay];
}

- (void)exploreTestnetViewControllerShowReceivePayment:(DWExploreTestnetViewController *)controller {
    [self.delegate showPaymentsControllerWithActivePage:DWPaymentsViewControllerIndex_Receive];
}

#pragma mark - DWRootEditProfileViewControllerDelegate

#if DASHPAY
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
#endif

@end

NS_ASSUME_NONNULL_END
