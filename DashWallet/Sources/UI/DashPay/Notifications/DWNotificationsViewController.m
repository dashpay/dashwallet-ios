//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWNotificationsViewController.h"

#import "DWDPBasicCell.h"
#import "DWDPNewIncomingRequestItem.h"
#import "DWDashPayConstants.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWListCollectionLayout.h"
#import "DWNoNotificationsCell.h"
#import "DWNotificationsInvitationCell.h"
#import "DWNotificationsModel.h"
#import "DWSendInviteFlowController.h"
#import "DWTitleActionHeaderView.h"
#import "DWUIKit.h"
#import "DWUserProfileViewController.h"
#import "UICollectionView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const NotificationsInvitationMessageHiddenKey = @"NotificationsInvitationMessageHiddenKey";

@interface DWNotificationsViewController () <DWNotificationsModelDelegate, DWDPNewIncomingRequestItemDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, DWNotificationsInvitationCellDelegate, DWSendInviteFlowControllerDelegate>

@property (readonly, nonatomic, strong) id<DWPayModelProtocol> payModel;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;

@property (null_resettable, nonatomic, strong) DWNotificationsModel *model;
@property (null_resettable, nonatomic, strong) UICollectionView *collectionView;
@property (null_resettable, nonatomic, strong) DWTitleActionHeaderView *measuringHeaderView;
@property (null_resettable, nonatomic, strong) DWNotificationsInvitationCell *measuringInvitationView;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsViewController

- (instancetype)initWithPayModel:(id<DWPayModelProtocol>)payModel
                    dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _payModel = payModel;
        _dataProvider = dataProvider;

        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (BOOL)invitationMessageHidden {
    if ([DWGlobalOptions sharedInstance].dpInvitationFlowEnabled == NO) {
        return YES;
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    const uint64_t balanceValue = wallet.balance;
    BOOL isEnoughBalance = balanceValue > DWDP_MIN_BALANCE_TO_CREATE_INVITE;
    if (!isEnoughBalance) {
        return YES;
    }

    return [[NSUserDefaults standardUserDefaults] boolForKey:NotificationsInvitationMessageHiddenKey];
}

- (void)setInvitationMessageHidden:(BOOL)isHidden {
    [[NSUserDefaults standardUserDefaults] setBool:isHidden forKey:NotificationsInvitationMessageHiddenKey];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self updateTitle];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.view addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.collectionView.trailingAnchor],
        [self.view.safeAreaLayoutGuide.bottomAnchor constraintEqualToAnchor:self.collectionView.bottomAnchor],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [DWGlobalOptions sharedInstance].shouldShowInvitationsBadge = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (self.isMovingFromParentViewController) {
        [self.model saveMostRecentViewedNotificationDate];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 3;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    DWNotificationsData *data = self.model.data;
    if (section == 0) {
        if ([self invitationMessageHidden]) {
            return 0;
        }
        else {
            return 1;
        }
    }
    else if (section == 1) {
        if (data.unreadItems.count == 0) {
            return 1; // empty state
        }
        else {
            return data.unreadItems.count;
        }
    }
    else { // 2
        return data.oldItems.count;
    }
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DWListCollectionLayout *layout = (DWListCollectionLayout *)collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:DWListCollectionLayout.class], @"Invalid layout");
    const CGFloat contentWidth = layout.contentWidth;

    if (indexPath.section == 0) {
        DWNotificationsInvitationCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:DWNotificationsInvitationCell.dw_reuseIdentifier forIndexPath:indexPath];
        cell.contentWidth = contentWidth;
        cell.delegate = self;
        return cell;
    }

    if (indexPath.section == 1 && self.model.data.unreadItems.count == 0) {
        DWNoNotificationsCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:DWNoNotificationsCell.dw_reuseIdentifier
                                                                                forIndexPath:indexPath];
        cell.contentWidth = contentWidth;
        return cell;
    }

    id<DWDPBasicUserItem> item = [self itemAtIndexPath:indexPath];

    DWDPBasicCell *cell = [collectionView dw_dequeueReusableCellForItem:item atIndexPath:indexPath];
    if (indexPath.section == 1) {
        cell.backgroundStyle = DWDPBasicCellBackgroundStyle_WhiteOnGray;
    }
    else {
        cell.backgroundStyle = DWDPBasicCellBackgroundStyle_GrayOnGray;
    }
    cell.contentWidth = contentWidth;
    cell.delegate = self;
    cell.item = item;
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        DWSendInviteFlowController *controller = [[DWSendInviteFlowController alloc] init];
        controller.delegate = self;
        [self presentViewController:controller animated:YES completion:nil];

        return;
    }

    id<DWDPBasicUserItem> item = [self itemAtIndexPath:indexPath];
    DWUserProfileViewController *profileController =
        [[DWUserProfileViewController alloc] initWithItem:item
                                                 payModel:self.payModel
                                             dataProvider:self.dataProvider
                                       shouldSkipUpdating:YES
                                        shownAfterPayment:NO];
    [self.navigationController pushViewController:profileController animated:YES];
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    const NSInteger section = indexPath.section;
    // hide Earlier section header if it's empty

    if (section == 0) {
        return [[UICollectionReusableView alloc] init];
    }

    if (section == 2 && [collectionView numberOfItemsInSection:section] == 0) {
        return [[UICollectionReusableView alloc] init];
    }

    DWTitleActionHeaderView *view = (DWTitleActionHeaderView *)[collectionView
        dequeueReusableSupplementaryViewOfKind:kind
                           withReuseIdentifier:DWTitleActionHeaderView.dw_reuseIdentifier
                                  forIndexPath:indexPath];
    view.titleLabel.text = [self titleForSection:section];
    view.actionButton.hidden = YES;
    return view;
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && self.model.data.unreadItems.count > 0) { // unread items
        id<DWDPNotificationItem> item = [self itemAtIndexPath:indexPath];
        [self.model markNotificationAsRead:item];
    }
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return CGSizeZero;
    }

    // hide Earlier section header if it's empty
    if (section == 2 && [collectionView numberOfItemsInSection:section] == 0) {
        return CGSizeZero;
    }

    DWListCollectionLayout *layout = (DWListCollectionLayout *)collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:DWListCollectionLayout.class], @"Invalid layout");
    const CGFloat contentWidth = layout.contentWidth;

    self.measuringHeaderView.titleLabel.text = [self titleForSection:section];
    self.measuringHeaderView.frame = CGRectMake(0, 0, contentWidth, 300);
    CGSize size = [self.measuringHeaderView systemLayoutSizeFittingSize:CGSizeMake(contentWidth, UILayoutFittingExpandedSize.height)
                                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel];

    return size;
}

#pragma mark - DWSendInviteFlowControllerDelegate

- (void)sendInviteFlowControllerDidFinish:(DWSendInviteFlowController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - DWNotificationsModelDelegate

- (void)notificationsModelDidUpdate:(DWNotificationsModel *)model {
    [self.collectionView reloadData];
    [self updateTitle];
}

#pragma mark - DWDPNewIncomingRequestItemDelegate

- (void)acceptIncomingRequest:(id<DWDPBasicUserItem>)item {
    [self.model acceptContactRequest:item];
}

- (void)declineIncomingRequest:(id<DWDPBasicUserItem>)item {
    [self.model declineContactRequest:item];
}

#pragma mark - DWNotificationsInvitationCellDelegate

- (void)notificationsInvitationCellCloseAction:(DWNotificationsInvitationCell *)cell {
    [self setInvitationMessageHidden:YES];

    [self.collectionView reloadData];
}

#pragma mark - Private

- (UICollectionView *)collectionView {
    if (_collectionView == nil) {
        DWListCollectionLayout *layout = [[DWListCollectionLayout alloc] init];

        UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:UIScreen.mainScreen.bounds
                                                              collectionViewLayout:layout];
        collectionView.translatesAutoresizingMaskIntoConstraints = NO;
        collectionView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        collectionView.delegate = self;
        collectionView.dataSource = self;
        collectionView.alwaysBounceVertical = YES;
        [collectionView dw_registerDPItemCells];
        [collectionView registerClass:DWNoNotificationsCell.class
            forCellWithReuseIdentifier:DWNoNotificationsCell.dw_reuseIdentifier];
        [collectionView registerClass:DWTitleActionHeaderView.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:DWTitleActionHeaderView.dw_reuseIdentifier];
        [collectionView registerClass:DWNotificationsInvitationCell.class
            forCellWithReuseIdentifier:DWNotificationsInvitationCell.dw_reuseIdentifier];

        _collectionView = collectionView;
    }
    return _collectionView;
}

- (DWNotificationsModel *)model {
    if (!_model) {
        _model = [[DWNotificationsModel alloc] init];
        _model.delegate = self;
        _model.context = self;
    }
    return _model;
}

- (DWTitleActionHeaderView *)measuringHeaderView {
    if (_measuringHeaderView == nil) {
        DWTitleActionHeaderView *view = [[DWTitleActionHeaderView alloc] initWithFrame:CGRectZero];
        view.translatesAutoresizingMaskIntoConstraints = NO;
        view.actionButton.hidden = YES;
        _measuringHeaderView = view;
    }
    return _measuringHeaderView;
}

- (DWNotificationsInvitationCell *)measuringInvitationView {
    if (_measuringInvitationView == nil) {
        DWNotificationsInvitationCell *view = [[DWNotificationsInvitationCell alloc] initWithFrame:CGRectZero];
        view.translatesAutoresizingMaskIntoConstraints = NO;
        _measuringInvitationView = view;
    }
    return _measuringInvitationView;
}

- (void)updateTitle {
    const NSUInteger unreadCount = self.model.data.unreadItems.count;
    NSString *title = NSLocalizedString(@"Notifications", nil);
    if (unreadCount > 0) {
        self.title = [NSString stringWithFormat:@"%@ (%ld)", title, unreadCount];
    }
    else {
        self.title = title;
    }
}

- (id<DWDPBasicUserItem, DWDPNotificationItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    DWNotificationsData *data = self.model.data;
    NSArray<id<DWDPBasicUserItem, DWDPNotificationItem>> *items = indexPath.section == 1 ? data.unreadItems : data.oldItems;
    return items[indexPath.row];
}

- (NSString *)titleForSection:(NSInteger)section {
    if (section == 1) {
        return NSLocalizedString(@"New", @"(List of) New (notifications)");
    }
    else {
        return NSLocalizedString(@"Earlier", @"(List of notifications happened) Earlier (some time ago)");
    }
}

@end
