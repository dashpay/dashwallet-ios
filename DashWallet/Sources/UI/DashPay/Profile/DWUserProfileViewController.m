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

#import "DWUserProfileViewController.h"

#import "DWDPBasicCell.h"
#import "DWDPTxItem.h"
#import "DWFilterHeaderView.h"
#import "DWInfoPopupViewController.h"
#import "DWNetworkErrorViewController.h"
#import "DWStretchyHeaderListCollectionLayout.h"
#import "DWTxDetailPopupViewController.h"
#import "DWUIKit.h"
#import "DWUserProfileContactActionsCell.h"
#import "DWUserProfileHeaderView.h"
#import "DWUserProfileModel.h"
#import "DWUserProfileNavigationTitleView.h"
#import "DWUserProfileSendRequestCell.h"
#import "UICollectionView+DWDPItemDequeue.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const FILTER_PADDING = 15.0; // same as horizontal padding for itemView inside DWDPBasicCell

@interface DWUserProfileViewController () <UICollectionViewDataSource,
                                           UICollectionViewDelegate,
                                           UICollectionViewDelegateFlowLayout,
                                           DWUserProfileModelDelegate,
                                           DWUserProfileHeaderViewDelegate,
                                           DWUserProfileContactActionsCellDelegate,
                                           DWUserProfileSendRequestCellDelegate,
                                           DWFilterHeaderViewDelegate>

@property (readonly, nonatomic, strong) DWUserProfileModel *model;

@property (readonly, nonatomic, strong) UIView *topOverscrollView;
@property (null_resettable, nonatomic, strong) UICollectionView *collectionView;
@property (nullable, nonatomic, weak) DWUserProfileHeaderView *headerView;

@property (null_resettable, nonatomic, strong) DWFilterHeaderView *measuringFilterHeaderView;
@property (null_resettable, nonatomic, strong) DWUserProfileHeaderView *measuringProfileHeaderView;

@property (null_resettable, nonatomic, strong) DWUserProfileSendRequestCell *measuringSendCell;
@property (null_resettable, nonatomic, strong) DWUserProfileContactActionsCell *measuringActionsCell;
@property (null_resettable, nonatomic, strong) DWDPBasicCell *measuringBasicCell;

@property (nonatomic, assign) DWHomeTxDisplayMode displayMode;
@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileViewController

- (instancetype)initWithItem:(id<DWDPBasicUserItem>)item
                    payModel:(id<DWPayModelProtocol>)payModel
                dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    return [self initWithItem:item payModel:payModel dataProvider:dataProvider shouldSkipUpdating:NO shownAfterPayment:NO];
}

- (instancetype)initWithItem:(id<DWDPBasicUserItem>)item
                    payModel:(id<DWPayModelProtocol>)payModel
                dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider
          shouldSkipUpdating:(BOOL)shouldSkipUpdating
           shownAfterPayment:(BOOL)shownAfterPayment {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = [[DWUserProfileModel alloc] initWithItem:item
                                           txDataProvider:dataProvider];
        _model.context = self;
        _model.delegate = self;
        _model.shownAfterPayment = shownAfterPayment;
        if (shouldSkipUpdating) {
            [_model skipUpdating];
        }
        else {
            [_model update];
        }

        self.payModel = payModel;
        self.dataProvider = dataProvider;

        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    DWUserProfileNavigationTitleView *titleView = [[DWUserProfileNavigationTitleView alloc] initWithFrame:CGRectZero];
    [titleView updateWithIdentity:self.model.item.identity];
    CGSize titleSize = [titleView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    titleView.frame = CGRectMake(0, 0, titleSize.width, titleSize.height);
    self.navigationItem.titleView = titleView;

    [self.view addSubview:self.collectionView];
    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.collectionView.trailingAnchor],
        [self.view.safeAreaLayoutGuide.bottomAnchor constraintEqualToAnchor:self.collectionView.bottomAnchor],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGSize size = self.view.bounds.size;
    self.topOverscrollView.frame = CGRectMake(0.0, -size.height, size.width, size.height);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.collectionView setNeedsLayout];
    [self.collectionView layoutIfNeeded];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.collectionView flashScrollIndicators];
}

- (id<DWDPBasicUserItem>)contactItem {
    return self.model.item;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 2;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (section == 0) {
        const BOOL shouldDisplayActions = [self.model shouldShowActions];
        return shouldDisplayActions ? 1 : 0;
    }
    else {
        return self.model.dataSource.count;
    }
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        DWUserProfileHeaderView *headerView = (DWUserProfileHeaderView *)[collectionView
            dequeueReusableSupplementaryViewOfKind:kind
                               withReuseIdentifier:DWUserProfileHeaderView.dw_reuseIdentifier
                                      forIndexPath:indexPath];
        headerView.model = self.model;
        headerView.delegate = self;
        self.headerView = headerView;
        return headerView;
    }
    else {
        DWFilterHeaderView *headerView = (DWFilterHeaderView *)[collectionView
            dequeueReusableSupplementaryViewOfKind:kind
                               withReuseIdentifier:DWFilterHeaderView.dw_reuseIdentifier
                                      forIndexPath:indexPath];
        headerView.padding = FILTER_PADDING;
        headerView.infoButton.hidden = (self.model.friendshipStatus == DSIdentityFriendshipStatus_Friends);
        headerView.titleLabel.text = NSLocalizedString(@"Activity", nil);
        headerView.delegate = self;
        [headerView.filterButton setTitle:[self titleForFilterButton] forState:UIControlStateNormal];
        return headerView;
    }
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DWListCollectionLayout *layout = (DWListCollectionLayout *)collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:DWListCollectionLayout.class], @"Invalid layout");
    const CGFloat contentWidth = layout.contentWidth;

    if (indexPath.section == 0) {
        if ([self.model shouldShowSendRequestAction]) {
            DWUserProfileSendRequestCell *cell = [collectionView
                dequeueReusableCellWithReuseIdentifier:DWUserProfileSendRequestCell.dw_reuseIdentifier
                                          forIndexPath:indexPath];
            cell.contentWidth = contentWidth;
            cell.model = self.model;
            cell.delegate = self;
            return cell;
        }
        DWUserProfileContactActionsCell *cell = [collectionView
            dequeueReusableCellWithReuseIdentifier:DWUserProfileContactActionsCell.dw_reuseIdentifier
                                      forIndexPath:indexPath];
        cell.contentWidth = contentWidth;
        cell.model = self.model;
        cell.delegate = self;
        return cell;
    }
    else {
        id<DWDPBasicItem> item = [self itemAtIndexPath:indexPath];

        DWDPBasicCell *cell = [collectionView dw_dequeueReusableCellForItem:item atIndexPath:indexPath];
        cell.contentWidth = contentWidth;
        cell.itemView.avatarHidden = YES;
        cell.backgroundStyle = DWDPBasicCellBackgroundStyle_GrayOnGray;
        cell.item = item;
        return cell;
    }
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section {
    DWListCollectionLayout *layout = (DWListCollectionLayout *)collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:DWListCollectionLayout.class], @"Invalid layout");
    const CGFloat contentWidth = layout.contentWidth;

    if (section == 1 && self.model.dataSource.count == 0) {
        return CGSizeZero;
    }

    UIView *measuringView = section == 0 ? self.measuringProfileHeaderView : self.measuringFilterHeaderView;
    measuringView.frame = CGRectMake(0, 0, contentWidth, 300);
    CGSize size = [measuringView systemLayoutSizeFittingSize:CGSizeMake(contentWidth, UILayoutFittingCompressedSize.height)
                               withHorizontalFittingPriority:UILayoutPriorityRequired
                                     verticalFittingPriority:UILayoutPriorityFittingSizeLevel];

    return size;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    DWListCollectionLayout *layout = (DWListCollectionLayout *)collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:DWListCollectionLayout.class], @"Invalid layout");
    const CGFloat contentWidth = layout.contentWidth;

    UICollectionViewCell *measuringCell = nil;
    if (indexPath.section == 0) {
        if ([self.model shouldShowSendRequestAction]) {
            DWUserProfileSendRequestCell *cell = self.measuringSendCell;
            cell.contentWidth = contentWidth;
            cell.model = self.model;
            measuringCell = cell;
        }
        DWUserProfileContactActionsCell *cell = self.measuringActionsCell;
        cell.contentWidth = contentWidth;
        cell.model = self.model;
        measuringCell = cell;
    }
    else {
        id<DWDPBasicItem> item = [self itemAtIndexPath:indexPath];

        DWDPBasicCell *cell = self.measuringBasicCell;
        cell.contentWidth = contentWidth;
        cell.itemView.avatarHidden = YES;
        cell.backgroundStyle = DWDPBasicCellBackgroundStyle_GrayOnGray;
        cell.item = item;
        measuringCell = cell;
    }

    measuringCell.frame = CGRectMake(0, 0, contentWidth, 300);
    CGSize size = [measuringCell systemLayoutSizeFittingSize:CGSizeMake(contentWidth, UILayoutFittingCompressedSize.height)
                               withHorizontalFittingPriority:UILayoutPriorityRequired
                                     verticalFittingPriority:UILayoutPriorityFittingSizeLevel];

    return size;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    if (indexPath.section != 1) {
        return;
    }

    id<DWDPBasicItem> item = [self itemAtIndexPath:indexPath];
    if (![item conformsToProtocol:@protocol(DWDPTxItem)]) {
        return;
    }

    DSTransaction *transaction = ((id<DWDPTxItem>)item).transaction;
    id<DWTransactionListDataProviderProtocol> dataProvider = self.dataProvider;
    DWTxDetailPopupViewController *controller =
        [[DWTxDetailPopupViewController alloc] initWithTransaction:transaction
                                                      dataProvider:dataProvider];
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    const CGFloat contentOffsetY = scrollView.contentOffset.y;
    const CGFloat headerHeight = CGRectGetHeight(self.headerView.bounds);
    const float percent = headerHeight > 0.0 ? contentOffsetY / headerHeight : 0.0;

    [self.headerView setScrollingPercent:percent];

    DWUserProfileNavigationTitleView *titleView = (DWUserProfileNavigationTitleView *)self.navigationItem.titleView;
    NSAssert([titleView isKindOfClass:DWUserProfileNavigationTitleView.class], @"Invalid titleView");
    [titleView setScrollingPercent:percent];
}

#pragma mark - DWUserProfileModelDelegate

- (void)userProfileModelDidUpdate:(DWUserProfileModel *)model {
    [self.collectionView reloadData];

    if (model.state == DWUserProfileModelState_Error) {
        DWNetworkErrorViewController *controller = [[DWNetworkErrorViewController alloc] initWithType:DWErrorDescriptionType_Profile];
        [self presentViewController:controller animated:YES completion:nil];
    }
}

#pragma mark - DWUserProfileHeaderViewDelegate

- (void)userProfileHeaderView:(DWUserProfileHeaderView *)view actionButtonAction:(UIButton *)sender {
    if ([self.model shouldShowSendRequestAction]) {
        [self sendContactRequest];
        return;
    }

    const BOOL canPay = self.model.friendshipStatus == DSIdentityFriendshipStatus_Incoming ||
                        self.model.friendshipStatus == DSIdentityFriendshipStatus_Friends;
    NSParameterAssert(canPay);
    if (canPay) {
        [self performPayToUser:self.model.item];
    }
}

#pragma mark - DWUserProfileSendRequestCellDelegate

- (void)userProfileSendRequestCell:(DWUserProfileSendRequestCell *)cell sendRequestButtonAction:(UIButton *)sender {
    [self sendContactRequest];
}

#pragma mark - DWUserProfileContactActionsCellDelegate

- (void)userProfileContactActionsCell:(DWUserProfileContactActionsCell *)cell mainButtonAction:(UIButton *)sender {
    const BOOL canAcceptRequest = self.model.friendshipStatus == DSIdentityFriendshipStatus_Incoming;
    NSParameterAssert(canAcceptRequest);
    if (canAcceptRequest) {
        [self.model acceptContactRequest];
    }
}

- (void)userProfileContactActionsCell:(DWUserProfileContactActionsCell *)cell secondaryButtonAction:(UIButton *)sender {
    // TODO: DP decline request
}

#pragma mark - DWFilterHeaderViewDelegate

- (void)filterHeaderView:(DWFilterHeaderView *)view filterButtonAction:(UIView *)sender {
    [self
        showTxFilterWithDisplayModeCallback:^(DWHomeTxDisplayMode mode) {
            self.displayMode = mode;
        }
                          shouldShowRewards:NO];
}

- (void)filterHeaderView:(DWFilterHeaderView *)view infoButtonAction:(UIView *)sender {
    CGPoint offset = [self.view.window convertRect:sender.frame fromView:sender.superview].origin;
    DWInfoPopupViewController *controller =
        [[DWInfoPopupViewController alloc] initWithText:NSLocalizedString(@"Payments made directly to addresses won’t be retained in activity.", nil)
                                                 offset:offset];
    controller.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    controller.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - DWTxDetailFullscreenViewControllerDelegate

// TODO: DashPay
//- (void)detailFullscreenViewControllerDidFinish:(DWTxDetailsViewController *)controller {
//     if (self.model.shouldAcceptIncomingAfterPayment) {
//         [self.model acceptContactRequest];
//     }
//
//     [super detailFullscreenViewControllerDidFinish:controller];
// }

#pragma mark - Private

- (void)sendContactRequest {
    const BOOL canSendRequest = self.model.friendshipStatus == DSIdentityFriendshipStatus_None;
    if (canSendRequest) {
        [self.model sendContactRequest:^(BOOL success) {
            if (!success) {
                DWNetworkErrorViewController *controller = [[DWNetworkErrorViewController alloc] initWithType:DWErrorDescriptionType_SendContactRequest];
                [self presentViewController:controller animated:YES completion:nil];
            }
        }];
    }
}

- (id<DWDPBasicItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    NSAssert(indexPath.section > 0, @"Section 0 is empty and should not have any data items");
    NSIndexPath *dataIndexPath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    id<DWDPBasicItem> item = [self.model.dataSource itemAtIndexPath:dataIndexPath];
    return item;
}

- (UICollectionView *)collectionView {
    if (_collectionView == nil) {
        UIView *topOverscrollView = [[UIView alloc] initWithFrame:CGRectZero];
        topOverscrollView.backgroundColor = [UIColor dw_backgroundColor];
        _topOverscrollView = topOverscrollView;

        DWStretchyHeaderListCollectionLayout *layout = [[DWStretchyHeaderListCollectionLayout alloc] init];

        UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:UIScreen.mainScreen.bounds
                                                              collectionViewLayout:layout];
        collectionView.translatesAutoresizingMaskIntoConstraints = NO;
        collectionView.dataSource = self;
        collectionView.delegate = self;
        collectionView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        collectionView.alwaysBounceVertical = YES;

        [collectionView dw_registerDPItemCells];

        [collectionView registerClass:DWUserProfileContactActionsCell.class
            forCellWithReuseIdentifier:DWUserProfileContactActionsCell.dw_reuseIdentifier];
        [collectionView registerClass:DWUserProfileSendRequestCell.class
            forCellWithReuseIdentifier:DWUserProfileSendRequestCell.dw_reuseIdentifier];

        [collectionView registerClass:DWUserProfileHeaderView.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:DWUserProfileHeaderView.dw_reuseIdentifier];
        [collectionView registerClass:DWFilterHeaderView.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:DWFilterHeaderView.dw_reuseIdentifier];

        [collectionView addSubview:topOverscrollView];
        _collectionView = collectionView;
    }
    return _collectionView;
}

- (DWUserProfileHeaderView *)measuringProfileHeaderView {
    if (_measuringProfileHeaderView == nil) {
        _measuringProfileHeaderView = [[DWUserProfileHeaderView alloc] initWithFrame:CGRectZero];
    }
    _measuringProfileHeaderView.model = self.model;
    return _measuringProfileHeaderView;
}

- (DWFilterHeaderView *)measuringFilterHeaderView {
    if (_measuringFilterHeaderView == nil) {
        _measuringFilterHeaderView = [[DWFilterHeaderView alloc] initWithFrame:CGRectZero];
        _measuringFilterHeaderView.padding = FILTER_PADDING;
        _measuringFilterHeaderView.titleLabel.text = NSLocalizedString(@"Activity", nil);
    }
    [_measuringFilterHeaderView.filterButton setTitle:[self titleForFilterButton] forState:UIControlStateNormal];
    return _measuringFilterHeaderView;
}

- (DWUserProfileSendRequestCell *)measuringSendCell {
    if (_measuringSendCell == nil) {
        _measuringSendCell = [[DWUserProfileSendRequestCell alloc] initWithFrame:CGRectZero];
    }
    return _measuringSendCell;
}

- (DWUserProfileContactActionsCell *)measuringActionsCell {
    if (_measuringActionsCell == nil) {
        _measuringActionsCell = [[DWUserProfileContactActionsCell alloc] initWithFrame:CGRectZero];
    }
    return _measuringActionsCell;
}

- (DWDPBasicCell *)measuringBasicCell {
    if (_measuringBasicCell == nil) {
        _measuringBasicCell = [[DWDPBasicCell alloc] initWithFrame:CGRectZero];
    }
    return _measuringBasicCell;
}

- (NSString *)titleForFilterButton {
    switch (self.displayMode) {
        case DWHomeTxDisplayModeAll:
            return NSLocalizedString(@"All", nil);
        case DWHomeTxDisplayModeReceived:
            return NSLocalizedString(@"Received", nil);
        case DWHomeTxDisplayModeSent:
            return NSLocalizedString(@"Sent", nil);
        case DWHomeTxDisplayModeRewards:
            NSAssert(NO, @"Not implemented here");
            return nil;
    }
}

@end
