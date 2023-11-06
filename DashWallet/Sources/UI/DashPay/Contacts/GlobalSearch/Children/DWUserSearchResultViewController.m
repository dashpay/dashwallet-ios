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

#import "DWUserSearchResultViewController.h"

#import "DWUIKit.h"

#import "DWDPBasicCell.h"
#import "DWDPNewIncomingRequestItem.h"
#import "DWListCollectionLayout.h"
#import "UICollectionView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserSearchResultViewController () <DWDPNewIncomingRequestItemDelegate, UICollectionViewDataSource, UICollectionViewDelegate>

@property (null_resettable, nonatomic, strong) UICollectionView *collectionView;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchResultViewController

- (void)setItems:(NSArray<id<DWDPBasicUserItem>> *)items {
    _items = [items copy];

    [self.collectionView reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.view addSubview:self.collectionView];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(nonnull UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DWListCollectionLayout *layout = (DWListCollectionLayout *)collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:DWListCollectionLayout.class], @"Invalid layout");
    const CGFloat contentWidth = layout.contentWidth;

    id<DWDPBasicUserItem> item = self.items[indexPath.row];

    DWDPBasicCell *cell = [collectionView dw_dequeueReusableCellForItem:item atIndexPath:indexPath];
    cell.contentWidth = contentWidth;
    cell.backgroundStyle = DWDPBasicCellBackgroundStyle_WhiteOnGray;
    cell.delegate = self;
    [cell setItem:item highlightedText:self.searchQuery];

    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    [self.delegate userSearchResultViewController:self willDisplayItemAtIndex:indexPath.row];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self.collectionView deselectItemAtIndexPath:indexPath animated:YES];

    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    [self.delegate userSearchResultViewController:self didSelectItemAtIndex:indexPath.row cell:cell];
}

#pragma mark - DWDPNewIncomingRequestItemDelegate

- (void)acceptIncomingRequest:(id<DWDPBasicUserItem>)item {
    [self.delegate userSearchResultViewController:self acceptContactRequest:item];
}

- (void)declineIncomingRequest:(id<DWDPBasicUserItem>)item {
    [self.delegate userSearchResultViewController:self declineContactRequest:item];
}

#pragma mark - Private

- (UICollectionView *)collectionView {
    if (_collectionView == nil) {
        DWListCollectionLayout *layout = [[DWListCollectionLayout alloc] init];

        UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:UIScreen.mainScreen.bounds
                                                              collectionViewLayout:layout];
        collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        collectionView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        collectionView.delegate = self;
        collectionView.dataSource = self;
        collectionView.alwaysBounceVertical = YES;
        [collectionView dw_registerDPItemCells];

        _collectionView = collectionView;
    }
    return _collectionView;
}

@end
