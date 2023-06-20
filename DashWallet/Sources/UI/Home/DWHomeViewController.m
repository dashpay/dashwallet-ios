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

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWHomeModel.h"
#import "DWHomeViewController+DWBackupReminder.h"
#import "DWHomeViewController+DWJailbreakCheck.h"
#import "DWHomeViewController+DWShortcuts.h"
#import "DWWindow.h"
#import "UIViewController+DWTxFilter.h"
#import "UIWindow+DSUtils.h"
#import "dashwallet-Swift.h"

#if DASHPAY
#import "DWNotificationsViewController.h"
#import "DWModalUserProfileViewController.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController () <DWHomeViewDelegate, DWShortcutsActionDelegate, TxReclassifyTransactionsInfoViewControllerDelegate>

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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.navigationController.navigationBar applyOpaqueAppearanceWith:[UIColor dw_dashNavigationBlueColor] shadowColor:[UIColor clearColor]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    BOOL upgrading = [self.model performOnSetupUpgrades];
    if (!upgrading) {
        // since these both methods might display modals, don't allow running them simultaneously
        [self showWalletBackupReminderIfNeeded];
    }

    [self.model registerForPushNotifications];
    [self showReclassifyYourTransactionsIfPossibleWithTransaction:self.model.allDataSource.items.firstObject];
    [self.model checkCrowdNodeState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.view hideBalanceIfNeeded];
}

#pragma mark - DWHomeViewDelegate

- (void)homeView:(DWHomeView *)homeView showTxFilter:(UIView *)sender {
    [self showTxFilterWithSender:sender displayModeProvider:self.model shouldShowRewards:YES];
}

- (void)homeView:(DWHomeView *)homeView showSyncingStatus:(UIView *)sender {
    DWSyncingAlertViewController *controller = [[DWSyncingAlertViewController alloc] init];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)homeView:(DWHomeView *)homeView profileButtonAction:(UIControl *)sender {
#if DASHPAY
    DWNotificationsViewController *controller = [[DWNotificationsViewController alloc] initWithPayModel:self.payModel dataProvider:self.dataProvider];
    [self.navigationController pushViewController:controller animated:YES];
#endif
}

- (void)homeView:(DWHomeView *)homeView didSelectTransaction:(DSTransaction *)transaction {
    [self presentTransactionDetails:transaction];
}

- (void)homeView:(DWHomeView *)homeView showCrowdNodeTxs:(NSArray<DSTransaction *> *)transactions {
    CNCreateAccountTxDetailsViewController *controller = [[CNCreateAccountTxDetailsViewController alloc] initWithTransactions:transactions];

    DWNavigationController *nvc = [[DWNavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:nvc animated:YES completion:nil];
}

- (void)homeViewShowDashPayRegistrationFlow:(DWHomeView *)homeView {
    DWShortcutAction *action = [DWShortcutAction actionWithType:DWShortcutActionTypeCreateUsername];
    [self performActionForShortcut:action sender:homeView];
}

- (void)homeView:(DWHomeView *)homeView showReclassifyYourTransactionsFlowWithTransaction:(DSTransaction *)transaction {
    [self showReclassifyYourTransactionsIfPossibleWithTransaction:transaction];
}

#pragma mark - TxReclassifyTransactionsInfoViewControllerDelegate

- (void)txReclassifyTransactionsFlowDidClosedWithUnderstandingWithController:(TxReclassifyTransactionsInfoViewController *)controller transaction:(DSTransaction *)transaction {
    [self presentTransactionDetails:transaction];
}
#pragma mark - DWShortcutsActionDelegate

- (void)shortcutsView:(UIView *)view didSelectAction:(DWShortcutAction *)action sender:(UIView *)sender {
    [self performActionForShortcut:action sender:sender];
}

#pragma mark - Private

#if DASHPAY
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
#endif

- (id<DWPayModelProtocol>)payModel {
    return self.model.payModel;
}

- (id<DWTransactionListDataProviderProtocol>)dataProvider {
    return [self.model getDataProvider];
}

- (void)setupView {
    UIImage *logoImage = nil;
    CGFloat logoHeight;
    if ([DWEnvironment sharedInstance].currentChain.chainType.tag == ChainType_TestNet) {
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

- (void)showReclassifyYourTransactionsIfPossibleWithTransaction:(DSTransaction *)transaction {
    if (self.presentedViewController) {
        return;
    }

    if (self.model.isAllowedToShowReclassifyYourTransactions) {
        TxReclassifyTransactionsInfoViewController *vc = [TxReclassifyTransactionsInfoViewController controller];
        vc.delegate = self;
        vc.transaction = transaction;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:vc animated:YES completion:nil];
        });
        [DWGlobalOptions sharedInstance].shouldDisplayReclassifyYourTransactionsFlow = NO;
    }
}

- (void)presentTransactionDetails:(DSTransaction *)transaction {
    DWTxDetailModel *model = [[DWTxDetailModel alloc] initWithTransaction:transaction];
    DWTxDetailViewController *controller = [[DWTxDetailViewController alloc] initWithModel:model];

    DWNavigationController *nvc = [[DWNavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:nvc animated:YES completion:nil];
}



@end

NS_ASSUME_NONNULL_END
