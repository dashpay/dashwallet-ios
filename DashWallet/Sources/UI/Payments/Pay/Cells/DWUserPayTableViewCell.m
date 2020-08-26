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

#import "DWUserPayTableViewCell.h"

#import "DWFrequentContactsDataSource.h"
#import "DWPayOptionModel.h"
#import "DWUIKit.h"
#import "DWVerticalContactCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserPayTableViewCell () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (strong, nonatomic) IBOutlet UIImageView *iconImageView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UIImageView *arrowAccessoryImageView;
@property (strong, nonatomic) IBOutlet UIView *usersView;
@property (strong, nonatomic) IBOutlet UICollectionView *usersCollectionView;

@property (nullable, nonatomic, strong) DWFrequentContactsDataSource *dataSource;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserPayTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.iconImageView.image = [UIImage imageNamed:@"pay_user"];
    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    self.titleLabel.text = NSLocalizedString(@"Send to", nil);
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    self.descriptionLabel.text = NSLocalizedString(@"A person in your contacts", nil);
    self.descriptionLabel.textColor = [UIColor dw_darkTitleColor];

    self.usersCollectionView.delegate = self;
    self.usersCollectionView.dataSource = self;

    NSString *cellId = DWVerticalContactCell.dw_reuseIdentifier;
    UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
    NSParameterAssert(nib);
    [self.usersCollectionView registerNib:nib forCellWithReuseIdentifier:cellId];

    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.usersCollectionView.collectionViewLayout;
    layout.itemSize = CGSizeMake(84.0, 84.0);
    layout.minimumLineSpacing = 4.0;
    layout.minimumInteritemSpacing = 4.0;
    layout.sectionInset = UIEdgeInsetsZero;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)setModel:(DWPayOptionModel *)model {
    _model = model;

    NSAssert(model.details == nil || [model.details isKindOfClass:DWFrequentContactsDataSource.class], @"Unsupported type");
    self.dataSource = model.details;

    if (self.dataSource == nil || self.dataSource.items.count == 0) {
        self.usersView.hidden = YES;
        self.arrowAccessoryImageView.hidden = YES;
    }
    else {
        self.usersView.hidden = NO;
        self.arrowAccessoryImageView.hidden = NO;
        [self.usersCollectionView reloadData];
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(nonnull UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.dataSource.items.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    id<DWDPBasicUserItem> item = self.dataSource.items[indexPath.row];

    DWVerticalContactCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:DWVerticalContactCell.dw_reuseIdentifier forIndexPath:indexPath];
    cell.userItem = item;

    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    id<DWDPBasicUserItem> item = self.dataSource.items[indexPath.row];
    [self.delegate userPayTableViewCell:self didSelectUserItem:item];
}


@end
