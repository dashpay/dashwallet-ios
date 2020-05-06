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

#import "DWEnvironment.h"
#import "DWStretchyHeaderCollectionViewFlowLayout.h"
#import "DWUIKit.h"
#import "DWUserProfileHeaderView.h"
#import "DWUserProfileNavigationTitleView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (readonly, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

@property (null_resettable, nonatomic, strong) UICollectionView *collectionView;
@property (nullable, nonatomic, weak) DWUserProfileHeaderView *headerView;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileViewController

- (instancetype)initWithBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _blockchainIdentity = blockchainIdentity;

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
    [titleView updateWithUsername:self.blockchainIdentity.currentUsername];
    CGSize titleSize = [titleView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    titleView.frame = CGRectMake(0, 0, titleSize.width, titleSize.height);
    self.navigationItem.titleView = titleView;

    [self.view addSubview:self.collectionView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.collectionView flashScrollIndicators];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return 20;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    DWUserProfileHeaderView *headerView = (DWUserProfileHeaderView *)[collectionView
        dequeueReusableSupplementaryViewOfKind:kind
                           withReuseIdentifier:DWUserProfileHeaderView.dw_reuseIdentifier
                                  forIndexPath:indexPath];
    [headerView updateWithUsername:self.blockchainIdentity.currentUsername];
    self.headerView = headerView;
    return headerView;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
    cell.backgroundColor = UIColor.whiteColor;
    return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    // TODO: fix
    return CGSizeMake(CGRectGetWidth(collectionView.bounds) - 20, 44);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section {
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:0 inSection:section];
    UIView *headerView = [self collectionView:collectionView
            viewForSupplementaryElementOfKind:UICollectionElementKindSectionHeader
                                  atIndexPath:indexPath];
    return [headerView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
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

#pragma mark - Private

- (UICollectionView *)collectionView {
    if (_collectionView == nil) {
        DWStretchyHeaderCollectionViewFlowLayout *layout = [[DWStretchyHeaderCollectionViewFlowLayout alloc] init];

        UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:UIScreen.mainScreen.bounds
                                                              collectionViewLayout:layout];
        collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        collectionView.dataSource = self;
        collectionView.delegate = self;
        collectionView.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        // TODO: temp cell
        [collectionView registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"cell"];

        [collectionView registerClass:DWUserProfileHeaderView.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:DWUserProfileHeaderView.dw_reuseIdentifier];

        _collectionView = collectionView;
    }
    return _collectionView;
}
@end
