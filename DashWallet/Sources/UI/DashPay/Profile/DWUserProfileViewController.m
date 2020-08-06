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
#import "DWStretchyHeaderListCollectionLayout.h"
#import "DWTxDetailPopupViewController.h"
#import "DWUIKit.h"
#import "DWUserProfileContactActionsCell.h"
#import "DWUserProfileHeaderView.h"
#import "DWUserProfileModel.h"
#import "DWUserProfileNavigationTitleView.h"
#import "DWUserProfileSendRequestCell.h"
#import "UICollectionView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileViewController () <UICollectionViewDataSource,
                                           UICollectionViewDelegate,
                                           UICollectionViewDelegateFlowLayout,
                                           DWUserProfileModelDelegate,
                                           DWUserProfileHeaderViewDelegate,
                                           DWUserProfileContactActionsCellDelegate,
                                           DWUserProfileSendRequestCellDelegate>

@property (readonly, nonatomic, strong) DWUserProfileModel *model;

@property (null_resettable, nonatomic, strong) UICollectionView *collectionView;
@property (nullable, nonatomic, weak) DWUserProfileHeaderView *headerView;

@property (null_resettable, nonatomic, strong) DWUserProfileHeaderView *measuringHeaderView;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileViewController

- (instancetype)initWithItem:(id<DWDPBasicUserItem>)item
                    payModel:(id<DWPayModelProtocol>)payModel
                dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    return [self initWithItem:item payModel:payModel dataProvider:dataProvider shouldSkipUpdating:NO];
}

- (instancetype)initWithItem:(id<DWDPBasicUserItem>)item
                    payModel:(id<DWPayModelProtocol>)payModel
                dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider
          shouldSkipUpdating:(BOOL)shouldSkipUpdating {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = [[DWUserProfileModel alloc] initWithItem:item txDataProvider:dataProvider];
        _model.delegate = self;
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

- (DWNavigationBarAppearance)navigationBarAppearance {
    return DWNavigationBarAppearanceWhite;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    DWUserProfileNavigationTitleView *titleView = [[DWUserProfileNavigationTitleView alloc] initWithFrame:CGRectZero];
    [titleView updateWithUsername:self.model.username];
    CGSize titleSize = [titleView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    titleView.frame = CGRectMake(0, 0, titleSize.width, titleSize.height);
    self.navigationItem.titleView = titleView;

    [self.view addSubview:self.collectionView];
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
        const BOOL shouldDisplayActions = [self shouldShowActions];
        return shouldDisplayActions ? 1 : 0;
    }
    else {
        return self.model.dataSource.count;
    }
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0) {
        return [[UICollectionReusableView alloc] initWithFrame:CGRectZero];
    }

    DWUserProfileHeaderView *headerView = (DWUserProfileHeaderView *)[collectionView
        dequeueReusableSupplementaryViewOfKind:kind
                           withReuseIdentifier:DWUserProfileHeaderView.dw_reuseIdentifier
                                  forIndexPath:indexPath];
    headerView.model = self.model;
    headerView.delegate = self;
    self.headerView = headerView;
    return headerView;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DWListCollectionLayout *layout = (DWListCollectionLayout *)collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:DWListCollectionLayout.class], @"Invalid layout");
    const CGFloat contentWidth = layout.contentWidth;

    if (indexPath.section == 0) {
        if ([self shouldShowSendRequestAction]) {
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
        cell.displayItemBackgroundView = NO;
        cell.item = item;
        return cell;
    }
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section {
    if (section != 0) {
        return CGSizeZero;
    }

    DWListCollectionLayout *layout = (DWListCollectionLayout *)collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:DWListCollectionLayout.class], @"Invalid layout");
    const CGFloat contentWidth = layout.contentWidth;

    UIView *measuringView = self.measuringHeaderView;
    measuringView.frame = CGRectMake(0, 0, contentWidth, 300);
    CGSize size = [measuringView systemLayoutSizeFittingSize:CGSizeMake(contentWidth, UILayoutFittingCompressedSize.height)
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
}

#pragma mark - DWUserProfileHeaderViewDelegate

- (void)userProfileHeaderView:(DWUserProfileHeaderView *)view actionButtonAction:(UIButton *)sender {
    const BOOL canPay = self.model.friendshipStatus == DSBlockchainIdentityFriendshipStatus_Incoming ||
                        self.model.friendshipStatus == DSBlockchainIdentityFriendshipStatus_Friends;
    NSParameterAssert(canPay);
    if (canPay) {
        [self performPayToUser:self.model.item];
    }
}

#pragma mark - DWUserProfileSendRequestCellDelegate

- (void)userProfileSendRequestCell:(DWUserProfileSendRequestCell *)cell sendRequestButtonAction:(UIButton *)sender {
    const BOOL canSendRequest = self.model.friendshipStatus == DSBlockchainIdentityFriendshipStatus_None;
    NSParameterAssert(canSendRequest);
    if (canSendRequest) {
        [self.model sendContactRequest];
    }
}

#pragma mark - DWUserProfileContactActionsCellDelegate

- (void)userProfileContactActionsCell:(DWUserProfileContactActionsCell *)cell mainButtonAction:(UIButton *)sender {
    const BOOL canAcceptRequest = self.model.friendshipStatus == DSBlockchainIdentityFriendshipStatus_Incoming;
    NSParameterAssert(canAcceptRequest);
    if (canAcceptRequest) {
        [self.model acceptContactRequest];
    }
}

- (void)userProfileContactActionsCell:(DWUserProfileContactActionsCell *)cell secondaryButtonAction:(UIButton *)sender {
    // TODO: DP decline request
}

#pragma mark - Private

- (BOOL)shouldShowActions {
    if (self.model.state != DWUserProfileModelState_Done) {
        return NO;
    }

    const DSBlockchainIdentityFriendshipStatus status = self.model.friendshipStatus;
    return (status == DSBlockchainIdentityFriendshipStatus_Incoming ||
            status == DSBlockchainIdentityFriendshipStatus_None ||
            status == DSBlockchainIdentityFriendshipStatus_Outgoing);
}

- (BOOL)shouldShowSendRequestAction {
    NSParameterAssert(self.model.state == DWUserProfileModelState_Done);

    const DSBlockchainIdentityFriendshipStatus status = self.model.friendshipStatus;
    return (status == DSBlockchainIdentityFriendshipStatus_None ||
            status == DSBlockchainIdentityFriendshipStatus_Outgoing);
}

- (BOOL)shouldShowAcceptDeclineRequestAction {
    NSParameterAssert(self.model.state == DWUserProfileModelState_Done);

    const DSBlockchainIdentityFriendshipStatus status = self.model.friendshipStatus;
    return status == DSBlockchainIdentityFriendshipStatus_Incoming;
}

- (id<DWDPBasicItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    NSAssert(indexPath.section > 0, @"Section 0 is empty and should not have any data items");
    NSIndexPath *dataIndexPath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    id<DWDPBasicItem> item = [self.model.dataSource itemAtIndexPath:dataIndexPath];
    return item;
}

- (UICollectionView *)collectionView {
    if (_collectionView == nil) {
        DWStretchyHeaderListCollectionLayout *layout = [[DWStretchyHeaderListCollectionLayout alloc] init];

        UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:UIScreen.mainScreen.bounds
                                                              collectionViewLayout:layout];
        collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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

        _collectionView = collectionView;
    }
    return _collectionView;
}

- (DWUserProfileHeaderView *)measuringHeaderView {
    if (_measuringHeaderView == nil) {
        _measuringHeaderView = [[DWUserProfileHeaderView alloc] initWithFrame:CGRectZero];
    }
    _measuringHeaderView.model = self.model;
    return _measuringHeaderView;
}

@end
