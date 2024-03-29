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
#import "DWRootEditProfileViewController.h"
#import "DWWindow.h"
#import "UIViewController+DWTxFilter.h"
#import "UIWindow+DSUtils.h"
#import "dashwallet-Swift.h"

#if DASHPAY
#import "DWNotificationsViewController.h"
#import "DWModalUserProfileViewController.h"
#import "DPAlertViewController.h"
#import "DWInvitationSetupState.h"
#import "DWDashPaySetupFlowController.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController () <DWHomeViewDelegate,
                                    DWShortcutsActionDelegate,
                                    TxReclassifyTransactionsInfoViewControllerDelegate,
                                    SyncingActivityMonitorObserver,
                                    DWRootEditProfileViewControllerDelegate>

@property (strong, nonatomic) DWHomeView *view;
#if DASHPAY
@property (strong, nonatomic) DWInvitationSetupState *invitationSetup;
@property (strong, nonatomic) DWDPAvatarView *avatarView;
#endif

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

#if DASHPAY
- (void)handleDeeplink:(NSURL *)url definedUsername:(nullable NSString *)definedUsername {
    if (self.model.dashPayModel.blockchainIdentity != nil) {
        NSString *title = NSLocalizedString(@"Username already found", nil);
        NSString *message = NSLocalizedString(@"You cannot claim this invite since you already have a Dash username", nil);
        DPAlertViewController *alert =
            [[DPAlertViewController alloc] initWithIcon:[UIImage imageNamed:@"icon_invitation_error"]
                                                  title:title
                                            description:message];
        [self presentViewController:alert animated:YES completion:nil];

        return;
    }

    if (SyncingActivityMonitor.shared.state != SyncingActivityMonitorStateSyncDone) {
        DWInvitationSetupState *state = [[DWInvitationSetupState alloc] init];
        state.invitation = url;
        state.chosenUsername = definedUsername;
        _invitationSetup = state;
        [SyncingActivityMonitor.shared addObserver:self];
        
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    [self.model handleDeeplink:url completion:^(BOOL success, NSString *_Nullable errorTitle, NSString *_Nullable errorMessage) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (success) {
            [strongSelf showCreateUsernameWithInvitation:url definedUsername:definedUsername];
        }
        else {
            DPAlertViewController *alert =
                [[DPAlertViewController alloc] initWithIcon:[UIImage imageNamed:@"icon_invitation_error"]
                                                       title:errorTitle
                                                 description:errorMessage];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            }
        }];
}
#endif

#pragma mark - DWHomeViewDelegate

- (void)homeView:(DWHomeView *)homeView showTxFilter:(UIView *)sender {
    [self showTxFilterWithSender:sender displayModeProvider:self.model shouldShowRewards:YES];
}

- (void)homeView:(DWHomeView *)homeView showSyncingStatus:(UIView *)sender {
    DWSyncingAlertViewController *controller = [[DWSyncingAlertViewController alloc] init];
    [self presentViewController:controller animated:YES completion:nil];
}

#if DASHPAY
- (void)homeView:(DWHomeView * _Nonnull)homeView didUpdateProfile:(DSBlockchainIdentity * _Nullable)identity unreadNotifications:(NSUInteger)unreadNotifications {
    
    self.avatarView.blockchainIdentity = identity;
    BOOL hasIdentity = identity != nil;
    BOOL hasNotifications = unreadNotifications > 0;
    self.avatarView.hidden = !hasIdentity;
    [self refreshNotificationBell:hasIdentity hasNotifications:hasNotifications];
}

#endif

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

#pragma mark - SyncingActivityMonitorObserver

- (void)syncingActivityMonitorProgressDidChange:(double)progress {
    // pass
}

- (void)syncingActivityMonitorStateDidChangeWithPreviousState:(SyncingActivityMonitorState)previousState state:(SyncingActivityMonitorState)state {
    
#if DASHPAY
    if (state == SyncingActivityMonitorStateSyncDone) {
        if (_invitationSetup != nil) {
            [self handleDeeplink:_invitationSetup.invitation definedUsername:_invitationSetup.chosenUsername];
            _invitationSetup = nil;
        }
        
        [SyncingActivityMonitor.shared removeObserver:self];
    }
#endif
}

#pragma mark - DWRootEditProfileViewControllerDelegate

#if DASHPAY
- (void)editProfileViewController:(DWRootEditProfileViewController *)controller
                updateDisplayName:(NSString *)rawDisplayName
                          aboutMe:(NSString *)rawAboutMe
                  avatarURLString:(nullable NSString *)avatarURLString {
    [self.model.dashPayModel.userProfile.updateModel updateWithDisplayName:rawDisplayName aboutMe:rawAboutMe avatarURLString:avatarURLString];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)editProfileViewControllerDidCancel:(DWRootEditProfileViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}
#endif

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

- (void)refreshNotificationBell:(BOOL)hasIdentity hasNotifications:(BOOL)hasNotifications {
    if (!hasIdentity) {
        self.navigationItem.rightBarButtonItem = nil;
        return;
    }
    
    UIImage *notificationsImage;
    
    if (hasNotifications) {
        notificationsImage = [UIImage imageNamed:@"icon_bell_active"];
    } else {
        notificationsImage = [UIImage imageNamed:@"icon_bell"];
    }
    
    notificationsImage = [notificationsImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    UIBarButtonItem *notificationButton = [[UIBarButtonItem alloc] initWithImage:notificationsImage style:UIBarButtonItemStylePlain target:self action:@selector(notificationAction)];
    self.navigationItem.rightBarButtonItem = notificationButton;
}

- (void)notificationAction {
    DWNotificationsViewController *controller = [[DWNotificationsViewController alloc] initWithPayModel:self.payModel dataProvider:self.dataProvider];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)profileAction {
    DWRootEditProfileViewController *controller = [[DWRootEditProfileViewController alloc] init];
    controller.delegate = self;
    DWNavigationController *navigation = [[DWNavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
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
    
#if DASHPAY
    DWDPAvatarView *avatarView = [[DWDPAvatarView alloc] initWithFrame:(CGRect){{0.0, 0.0}, CGSizeMake(30.0, 30.0)}];
    avatarView.small = YES;
    avatarView.hidden = YES;
    avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileAction)];
    [avatarView addGestureRecognizer:tapRecognizer];
    _avatarView = avatarView;
    UIBarButtonItem *avatarButton = [[UIBarButtonItem alloc] initWithCustomView:avatarView];
    self.navigationItem.leftBarButtonItem = avatarButton;
#endif

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
