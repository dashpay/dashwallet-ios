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

#import "DWSeedPhraseView.h"

#import "DWSeedPhraseModel.h"
#import "DWSeedWordCollectionCell.h"
#import "KTCenterFlowLayout.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const CELL_ID = @"DWSeedWordCollectionCell";

static CGFloat const LINE_SPACING = 0.0;
static CGFloat const INTERITEM_SPACING = 16.0;

static CGFloat const TITLE_COLLECTION_PADDING = 20.0;

@interface DWSeedPhraseView () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UICollectionView *collectionView;

@property (nonatomic, strong) DWSeedWordCollectionCell *sizingCell;

@end

@implementation DWSeedPhraseView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.backgroundColor = self.backgroundColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
    titleLabel.textColor = [UIColor dw_darkTitleColor];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.numberOfLines = 0;
    [self addSubview:titleLabel];
    self.titleLabel = titleLabel;

    self.sizingCell = [[DWSeedWordCollectionCell alloc] initWithFrame:CGRectZero];

    KTCenterFlowLayout *flowLayout = [[KTCenterFlowLayout alloc] init];
    flowLayout.scrollDirection = UICollectionViewScrollDirectionVertical;
    flowLayout.minimumLineSpacing = LINE_SPACING;
    flowLayout.minimumInteritemSpacing = INTERITEM_SPACING;
    flowLayout.sectionInset = UIEdgeInsetsZero;

    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                                          collectionViewLayout:flowLayout];
    collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    collectionView.backgroundColor = [UIColor dw_backgroundColor];
    collectionView.dataSource = self;
    collectionView.delegate = self;
    [collectionView registerClass:DWSeedWordCollectionCell.class forCellWithReuseIdentifier:CELL_ID];
    [self addSubview:collectionView];
    self.collectionView = collectionView;

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [collectionView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                 constant:TITLE_COLLECTION_PADDING],
        [collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [collectionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (!CGSizeEqualToSize(self.bounds.size, [self intrinsicContentSize])) {
        [self invalidateIntrinsicContentSize];
    }
}

- (CGSize)intrinsicContentSize {
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.titleLabel.intrinsicContentSize.height +
                     TITLE_COLLECTION_PADDING +
                     self.collectionView.contentSize.height;
    return CGSizeMake(width, height);
}

- (void)setModel:(nullable DWSeedPhraseModel *)model {
    _model = model;
    self.titleLabel.text = model.title;

    [self reloadData];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.model.words.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DWSeedWordCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CELL_ID forIndexPath:indexPath];
    NSAssert([cell isKindOfClass:DWSeedWordCollectionCell.class], @"Invalid cell class");

    NSString *word = self.model.words[indexPath.row];
    cell.text = word;

    return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewFlowLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *word = self.model.words[indexPath.row];
    CGSize size = [DWSeedWordCollectionCell sizeForText:word maxWidth:CGRectGetWidth(collectionView.bounds)];

    return size;
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self reloadData];
}

#pragma mark - Private

- (void)reloadData {
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];

    // invalidate content size when reloadData completed
    [self.collectionView
        performBatchUpdates:^{
        }
        completion:^(BOOL finished) {
            [self invalidateIntrinsicContentSize];
        }];
}

@end

NS_ASSUME_NONNULL_END
