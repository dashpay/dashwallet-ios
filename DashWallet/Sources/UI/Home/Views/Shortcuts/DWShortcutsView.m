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

#import "DWShortcutsView.h"

#import "DWShortcutCollectionViewCell.h"
#import "DWShortcutsModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize CellSizeForContentSizeCategory(UIContentSizeCategory contentSizeCategory) {
    if ([contentSizeCategory isEqualToString:UIContentSizeCategoryExtraSmall] ||
        [contentSizeCategory isEqualToString:UIContentSizeCategorySmall] ||
        [contentSizeCategory isEqualToString:UIContentSizeCategoryMedium] ||
        [contentSizeCategory isEqualToString:UIContentSizeCategoryLarge]) {
        return CGSizeMake(79.0, 79.0);
    }
    else if ([contentSizeCategory isEqualToString:UIContentSizeCategoryExtraLarge]) {
        return CGSizeMake(88.0, 88.0);
    }
    else if ([contentSizeCategory isEqualToString:UIContentSizeCategoryExtraExtraLarge]) {
        return CGSizeMake(100.0, 100.0);
    }
    else {
        return CGSizeMake(116.0, 116.0);
    }
}

@interface DWShortcutsView () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (weak, nonatomic) IBOutlet UIView *contentView;
@property (weak, nonatomic) IBOutlet UICollectionView *collectionView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *collectionViewHeightConstraint;

@end

@implementation DWShortcutsView

@synthesize model = _model;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil];
    [self addSubview:self.contentView];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.widthAnchor],
    ]];

    self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    NSString *cellId = DWShortcutCollectionViewCell.dw_reuseIdentifier;
    UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
    NSParameterAssert(nib);
    [self.collectionView registerNib:nib forCellWithReuseIdentifier:cellId];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];

    UIContentSizeCategory contentSizeCategory = [UIApplication sharedApplication].preferredContentSizeCategory;
    [self updateCellSizeForContentSizeCategory:contentSizeCategory initialSetup:YES];
}

- (DWShortcutsModel *)model {
    if (_model == nil) {
        _model = [[DWShortcutsModel alloc] init];
    }

    return _model;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.model.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWShortcutCollectionViewCell.dw_reuseIdentifier;
    DWShortcutCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellId
                                                                                   forIndexPath:indexPath];

    DWShortcutAction *action = self.model.items[indexPath.item];
    cell.model = action;

    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    DWShortcutAction *action = self.model.items[indexPath.item];
    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    [self.actionDelegate shortcutsView:self didSelectAction:action sender:cell];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    UIContentSizeCategory contentSizeCategory = notification.userInfo[UIContentSizeCategoryNewValueKey];
    [self updateCellSizeForContentSizeCategory:contentSizeCategory initialSetup:NO];
}

#pragma mark - Private

- (void)updateCellSizeForContentSizeCategory:(UIContentSizeCategory)contentSizeCategory
                                initialSetup:(BOOL)initialSetup {
    const CGSize cellSize = CellSizeForContentSizeCategory(contentSizeCategory);
    self.collectionViewHeightConstraint.constant = cellSize.height;

    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    NSAssert([layout isKindOfClass:UICollectionViewFlowLayout.class], @"Invalid collection configuration");
    layout.itemSize = cellSize;

    if (!initialSetup) {
        [layout invalidateLayout];
    }

    [self.collectionView reloadData];

    if (!initialSetup) {
        [self.delegate shortcutsViewDidUpdateContentSize:self];
    }
}

@end

NS_ASSUME_NONNULL_END
