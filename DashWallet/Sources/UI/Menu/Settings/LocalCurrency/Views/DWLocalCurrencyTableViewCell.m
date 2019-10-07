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

#import "DWLocalCurrencyTableViewCell.h"

#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const ACCESSORY_SIZE = {26.0, 26.0};

@interface DWLocalCurrencyTableViewCell ()

@property (readonly, strong, nonatomic) UILabel *codeLabel;
@property (readonly, strong, nonatomic) UILabel *nameLabel;
@property (readonly, strong, nonatomic) UILabel *priceLabel;
@property (readonly, nonatomic, strong) UIImageView *accessoryImageView;

@end

@implementation DWLocalCurrencyTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *contentView = self.roundedContentView;
        NSParameterAssert(contentView);

        UILabel *codeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        codeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        codeLabel.backgroundColor = [UIColor dw_backgroundColor];
        codeLabel.textColor = [UIColor dw_darkTitleColor];
        codeLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        codeLabel.adjustsFontForContentSizeCategory = YES;
        codeLabel.minimumScaleFactor = 0.5;
        codeLabel.adjustsFontSizeToFitWidth = YES;
        [codeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisVertical];
        [codeLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 30
                                                   forAxis:UILayoutConstraintAxisHorizontal];
        [codeLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 30
                                     forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:codeLabel];
        _codeLabel = codeLabel;

        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        nameLabel.backgroundColor = [UIColor dw_backgroundColor];
        nameLabel.textColor = [UIColor dw_quaternaryTextColor];
        nameLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        nameLabel.adjustsFontForContentSizeCategory = YES;
        nameLabel.minimumScaleFactor = 0.5;
        nameLabel.adjustsFontSizeToFitWidth = YES;
        [nameLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisVertical];
        [nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 10
                                                   forAxis:UILayoutConstraintAxisHorizontal];
        [nameLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 20
                                     forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:nameLabel];
        _nameLabel = nameLabel;

        UILabel *priceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
        priceLabel.backgroundColor = [UIColor dw_backgroundColor];
        priceLabel.textAlignment = NSTextAlignmentRight;
        priceLabel.textColor = [UIColor dw_secondaryTextColor];
        priceLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        priceLabel.adjustsFontForContentSizeCategory = YES;
        priceLabel.minimumScaleFactor = 0.5;
        priceLabel.adjustsFontSizeToFitWidth = YES;
        [priceLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];
        [priceLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 20
                                                    forAxis:UILayoutConstraintAxisHorizontal];
        [priceLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 10
                                      forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:priceLabel];
        _priceLabel = priceLabel;

        UIImage *image = [UIImage imageNamed:@"icon_checkbox"];
        UIImage *highlightedImage = [UIImage imageNamed:@"icon_checkbox_checked"];
        NSParameterAssert(image);
        NSParameterAssert(highlightedImage);
        UIImageView *accessoryImageView = [[UIImageView alloc] initWithImage:image highlightedImage:highlightedImage];
        accessoryImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:accessoryImageView];
        _accessoryImageView = accessoryImageView;

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = DW_FORM_CELL_VERTICAL_PADDING; // TODO should be less to fit 70pt

        [NSLayoutConstraint activateConstraints:@[
            [codeLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                constant:padding],
            [codeLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                    constant:margin],
            [codeLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                   constant:-padding],

            [nameLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                constant:padding],
            [nameLabel.leadingAnchor constraintEqualToAnchor:codeLabel.trailingAnchor
                                                    constant:DW_FORM_CELL_SPACING],
            [nameLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                   constant:-padding],

            [priceLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:padding],
            [priceLabel.leadingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor
                                                     constant:DW_FORM_CELL_SPACING],

            [accessoryImageView.leadingAnchor constraintEqualToAnchor:priceLabel.trailingAnchor
                                                             constant:DW_FORM_CELL_SPACING],
            [accessoryImageView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                              constant:-margin],
            [accessoryImageView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
            [accessoryImageView.widthAnchor constraintEqualToConstant:ACCESSORY_SIZE.width],
            [accessoryImageView.heightAnchor constraintEqualToConstant:ACCESSORY_SIZE.height],
        ]];
    }

    return self;
}

- (void)configureWithModel:(id<DWCurrencyItem>)model selected:(BOOL)selected {
    self.codeLabel.text = model.code;
    self.nameLabel.text = model.name;
    self.priceLabel.text = model.priceString;

    self.accessoryImageView.highlighted = selected;
}

@end

NS_ASSUME_NONNULL_END
