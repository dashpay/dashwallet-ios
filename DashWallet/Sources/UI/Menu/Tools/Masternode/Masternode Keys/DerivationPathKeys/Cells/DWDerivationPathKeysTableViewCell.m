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

#import "DWDerivationPathKeysTableViewCell.h"

#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDerivationPathKeysTableViewCell ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *detailLabel;

@end

@implementation DWDerivationPathKeysTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *contentView = self.roundedContentView;
        NSParameterAssert(contentView);

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = [UIColor dw_backgroundColor];
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.minimumScaleFactor = 0.5;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];
        [contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        detailLabel.backgroundColor = [UIColor dw_backgroundColor];
        detailLabel.textColor = [UIColor dw_dashBlueColor];
        detailLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        detailLabel.adjustsFontForContentSizeCategory = YES;
        detailLabel.minimumScaleFactor = 0.5;
        detailLabel.adjustsFontSizeToFitWidth = YES;
        [detailLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                     forAxis:UILayoutConstraintAxisVertical];
        [contentView addSubview:detailLabel];
        _detailLabel = detailLabel;

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = DW_FORM_CELL_SPACING;
        const CGFloat spacing = 4.0;

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:padding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:margin],
            [titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                      constant:-margin],

            [detailLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                  constant:spacing],
            [detailLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                      constant:margin],
            [detailLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                       constant:-margin],
            [detailLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                     constant:-padding],
        ]];
    }

    return self;
}

- (void)setItem:(nullable id<DWDerivationPathKeysItem>)item {
    _item = item;

    self.titleLabel.text = item.title;
    self.detailLabel.text = item.detail;
}

@end

NS_ASSUME_NONNULL_END
