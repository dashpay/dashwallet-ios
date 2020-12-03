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

#import "DWHomeViewController.h"

#import "DWBalanceDisplayOptionsProtocol.h"
#import "DWDashPaySetupFlowController.h"
#import "DWEnvironment.h"
#import "DWHomeView.h"
#import "DWHomeViewController+DWBackupReminder.h"
#import "DWHomeViewController+DWJailbreakCheck.h"
#import "DWHomeViewController+DWShortcuts.h"
#import "DWModalUserProfileViewController.h"
#import "DWNavigationController.h"
#import "DWNotificationsViewController.h"
#import "DWShortcutAction.h"
#import "DWTxDetailPopupViewController.h"
#import "DWUserProfileViewController.h"
#import "DWWindow.h"
#import "UIViewController+DWTxFilter.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController () <DWHomeViewDelegate, DWShortcutsActionDelegate, DWTxDetailPopupViewControllerDelegate>

@property (strong, nonatomic) DWHomeView *view;

@end

@implementation DWHomeViewController

@dynamic view;
@synthesize model = _model;

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)loadView {
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWHomeView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.delegate = self;
    self.view.shortcutsDelegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSParameterAssert(self.model);

    [self setupView];
    [self performJailbreakCheck];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    BOOL upgrading = [self.model performOnSetupUpgrades];
    if (!upgrading) {
        // since these both methods might display modals, don't allow running them simultaneously
        [self showWalletBackupReminderIfNeeded];
    }

    [self.model registerForPushNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.model.balanceDisplayOptions hideBalanceIfNeeded];
}

#pragma mark - DWHomeViewDelegate

- (void)homeView:(DWHomeView *)homeView showTxFilter:(UIView *)sender {
    [self showTxFilterWithSender:sender displayModeProvider:self.model shouldShowRewards:YES];
}

- (void)homeView:(DWHomeView *)homeView profileButtonAction:(UIControl *)sender {
    DWNotificationsViewController *controller = [[DWNotificationsViewController alloc] initWithPayModel:self.payModel dataProvider:self.dataProvider];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)homeView:(DWHomeView *)homeView didSelectTransaction:(DSTransaction *)transaction {
    id<DWTransactionListDataProviderProtocol> dataProvider = [self.model getDataProvider];
    DWTxDetailPopupViewController *controller =
        [[DWTxDetailPopupViewController alloc] initWithTransaction:transaction
                                                      dataProvider:dataProvider];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)homeView:(DWHomeView *)homeView openUserProfile:(id<DWDPBasicUserItem>)userItem {
    DWUserProfileViewController *profileController =
        [[DWUserProfileViewController alloc] initWithItem:userItem
                                                 payModel:self.payModel
                                             dataProvider:self.dataProvider
                                       shouldSkipUpdating:NO
                                        shownAfterPayment:NO];
    [self.navigationController pushViewController:profileController animated:YES];
}

- (void)homeViewShowDashPayRegistrationFlow:(DWHomeView *)homeView {
    DWDashPaySetupFlowController *controller = [[DWDashPaySetupFlowController alloc]
        initWithDashPayModel:self.model.dashPayModel];
    controller.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - DWTxDetailPopupViewControllerDelegate

- (void)txDetailPopupViewController:(DWTxDetailPopupViewController *)controller openUserItem:(id<DWDPBasicUserItem>)userItem {
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self homeView:self.view openUserProfile:userItem];
                                   }];
}

#pragma mark - DWShortcutsActionDelegate

- (void)shortcutsView:(UIView *)view didSelectAction:(DWShortcutAction *)action sender:(UIView *)sender {
    [self performActionForShortcut:action sender:sender];
}

#pragma mark - Private

- (void)payViewControllerDidHidePaymentResultToContact:(nullable id<DWDPBasicUserItem>)contact {
    if (!contact) {
        return;
    }

    DWModalUserProfileViewController *profile =
        [[DWModalUserProfileViewController alloc] initWithItem:contact
                                                      payModel:self.payModel
                                                  dataProvider:self.dataProvider];
    [self presentViewController:profile animated:YES completion:nil];
}

- (id<DWPayModelProtocol>)payModel {
    return self.model.payModel;
}

- (id<DWTransactionListDataProviderProtocol>)dataProvider {
    return [self.model getDataProvider];
}

- (void)setupView {
    UIImage *logoImage = nil;
    CGFloat logoHeight;
    if ([DWEnvironment sharedInstance].currentChain.chainType == DSChainType_TestNet) {
        logoImage = [UIImage imageNamed:@"dash_logo_testnet"];
        logoHeight = 40.0;
    }
    else {
        logoImage = [UIImage imageNamed:@"dash_logo_template"];
        logoHeight = 23.0;
    }
    NSParameterAssert(logoImage);
    UIImageView *imageView = [[UIImageView alloc] initWithImage:logoImage];
    imageView.tintColor = [UIColor whiteColor];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    const CGRect frame = CGRectMake(0.0, 0.0, 89.0, logoHeight);
    imageView.frame = frame;

    UIView *contentView = [[UIView alloc] initWithFrame:frame];
    [contentView addSubview:imageView];

    self.navigationItem.titleView = contentView;

    self.view.model = self.model;
}

@end

NS_ASSUME_NONNULL_END
