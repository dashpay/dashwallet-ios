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
#import "NSAttributedString+DWHighlightText.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const ACCESSORY_SIZE = {26.0, 26.0};

@interface DWLocalCurrencyTableViewCell ()

@property (readonly, strong, nonatomic) UIImageView *iconImageView;
@property (readonly, strong, nonatomic) UILabel *codeLabel;
@property (readonly, strong, nonatomic) UILabel *nameLabel;
@property (readonly, strong, nonatomic) UILabel *priceLabel;
@property (readonly, nonatomic, strong) UIImageView *accessoryImageView;

@property (nullable, nonatomic, strong) id<DWCurrencyItem> model;
@property (nullable, nonatomic, copy) NSString *searchQuery;

@end

@implementation DWLocalCurrencyTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *contentView = self.contentView;

        UIImageView *iconImageView = [[UIImageView alloc] init];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:iconImageView];
        _iconImageView = iconImageView;

        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        nameLabel.textColor = [UIColor dw_darkTitleColor];
        nameLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        nameLabel.adjustsFontForContentSizeCategory = YES;
        nameLabel.minimumScaleFactor = 0.5;
        nameLabel.adjustsFontSizeToFitWidth = YES;
        [nameLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisVertical];
        [contentView addSubview:nameLabel];
        _nameLabel = nameLabel;

        UILabel *priceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
        priceLabel.textColor = [UIColor dw_quaternaryTextColor];
        priceLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        priceLabel.adjustsFontForContentSizeCategory = YES;
        priceLabel.minimumScaleFactor = 0.5;
        priceLabel.adjustsFontSizeToFitWidth = YES;
        [priceLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];
        [contentView addSubview:priceLabel];
        _priceLabel = priceLabel;

        UILabel *codeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        codeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        codeLabel.textColor = [UIColor dw_quaternaryTextColor];
        codeLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        codeLabel.textAlignment = NSTextAlignmentRight;
        codeLabel.adjustsFontForContentSizeCategory = YES;
        codeLabel.minimumScaleFactor = 0.5;
        codeLabel.adjustsFontSizeToFitWidth = YES;
        [codeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisVertical];
        [codeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisHorizontal];
        [codeLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 30
                                     forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:codeLabel];
        _codeLabel = codeLabel;


        UIImage *image = [UIImage imageNamed:@"icon_checkbox"];
        UIImage *highlightedImage = [UIImage imageNamed:@"icon_checkbox_checked"];
        NSParameterAssert(image);
        NSParameterAssert(highlightedImage);
        UIImageView *accessoryImageView = [[UIImageView alloc] initWithImage:image highlightedImage:highlightedImage];
        accessoryImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:accessoryImageView];
        _accessoryImageView = accessoryImageView;

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = 10;

        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
            [iconImageView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                        constant:margin],
            [iconImageView.widthAnchor constraintEqualToConstant:30],
            [iconImageView.heightAnchor constraintEqualToConstant:30],

            [nameLabel.leadingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor
                                                    constant:padding],
            [nameLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                constant:padding],

            [priceLabel.leadingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor
                                                     constant:padding],
            [priceLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:priceLabel.bottomAnchor
                                                     constant:padding],

            [codeLabel.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
            [codeLabel.leadingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor
                                                    constant:padding],

            [accessoryImageView.leadingAnchor constraintEqualToAnchor:codeLabel.trailingAnchor
                                                             constant:padding],
            [accessoryImageView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                              constant:-margin],
            [accessoryImageView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
            [accessoryImageView.widthAnchor constraintEqualToConstant:ACCESSORY_SIZE.width],
            [accessoryImageView.heightAnchor constraintEqualToConstant:ACCESSORY_SIZE.height],
        ]];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(contentSizeCategoryDidChangeNotification)
                                   name:UIContentSizeCategoryDidChangeNotification
                                 object:nil];
    }

    return self;
}

- (void)configureWithModel:(id<DWCurrencyItem>)model
                  selected:(BOOL)selected
               searchQuery:(nullable NSString *)searchQuery {
    self.model = model;
    self.searchQuery = searchQuery;

    self.priceLabel.text = model.priceString;
    self.accessoryImageView.highlighted = selected;

    [self reloadAttributedData];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

#pragma mark - Private

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

- (void)reloadAttributedData {
    NSString *highlightedText = self.searchQuery;
    UIColor *highlightedTextColor = [UIColor dw_dashBlueColor];

    if (self.model.flagName) {
        self.iconImageView.image = [UIImage imageNamed:self.model.flagName];
    }
    else {
        self.iconImageView.image = nil;
    }

    UIFont *codeFont = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    UIColor *codeColor = [UIColor dw_quaternaryTextColor];
    self.codeLabel.attributedText = [NSAttributedString attributedText:self.model.code
                                                                  font:codeFont
                                                             textColor:codeColor
                                                       highlightedText:highlightedText
                                                  highlightedTextColor:highlightedTextColor];

    UIFont *nameFont = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
    UIColor *nameColor = [UIColor dw_darkTitleColor];
    self.nameLabel.attributedText = [NSAttributedString attributedText:self.model.name
                                                                  font:nameFont
                                                             textColor:nameColor
                                                       highlightedText:highlightedText
                                                  highlightedTextColor:highlightedTextColor];
}

@end

NS_ASSUME_NONNULL_END
