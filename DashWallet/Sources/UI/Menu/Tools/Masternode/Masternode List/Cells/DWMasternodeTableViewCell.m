//
//  Created by Sam Westrich
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

#import "DWMasternodeTableViewCell.h"

#import "DWSharedUIConstants.h"
#import "DWUIKit.h"
#import "NSAttributedString+DWHighlightText.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const ACCESSORY_SIZE = {26.0, 26.0};

@interface DWMasternodeTableViewCell ()

@property (readonly, strong, nonatomic) UILabel *addressLabel;
@property (readonly, strong, nonatomic) UILabel *portLabel;
@property (readonly, strong, nonatomic) UILabel *availabilityLabel;
@property (readonly, nonatomic, strong) UIImageView *accessoryImageView;

@property (nullable, nonatomic, strong) DSSimplifiedMasternodeEntry *model;
@property (nullable, nonatomic, copy) NSString *searchQuery;

@end

@implementation DWMasternodeTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *contentView = self.roundedContentView;
        NSParameterAssert(contentView);

        UILabel *addressLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
        addressLabel.backgroundColor = [UIColor dw_backgroundColor];
        addressLabel.textColor = [UIColor dw_darkTitleColor];
        addressLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        addressLabel.adjustsFontForContentSizeCategory = YES;
        addressLabel.minimumScaleFactor = 0.5;
        addressLabel.adjustsFontSizeToFitWidth = YES;
        [addressLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                      forAxis:UILayoutConstraintAxisVertical];
        [addressLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 30
                                                      forAxis:UILayoutConstraintAxisHorizontal];
        [addressLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 30
                                        forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:addressLabel];
        _addressLabel = addressLabel;

        UILabel *portLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        portLabel.translatesAutoresizingMaskIntoConstraints = NO;
        portLabel.backgroundColor = [UIColor dw_backgroundColor];
        portLabel.textColor = [UIColor dw_quaternaryTextColor];
        portLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        portLabel.adjustsFontForContentSizeCategory = YES;
        portLabel.minimumScaleFactor = 0.5;
        portLabel.adjustsFontSizeToFitWidth = YES;
        [portLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisVertical];
        [portLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 10
                                                   forAxis:UILayoutConstraintAxisHorizontal];
        [portLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 20
                                     forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:portLabel];
        _portLabel = portLabel;

        UILabel *availabilityLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        availabilityLabel.translatesAutoresizingMaskIntoConstraints = NO;
        availabilityLabel.backgroundColor = [UIColor dw_backgroundColor];
        availabilityLabel.textAlignment = NSTextAlignmentRight;
        availabilityLabel.textColor = [UIColor dw_secondaryTextColor];
        availabilityLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        availabilityLabel.adjustsFontForContentSizeCategory = YES;
        availabilityLabel.minimumScaleFactor = 0.5;
        availabilityLabel.adjustsFontSizeToFitWidth = YES;
        [availabilityLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                           forAxis:UILayoutConstraintAxisVertical];
        [availabilityLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 20
                                                           forAxis:UILayoutConstraintAxisHorizontal];
        [availabilityLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 10
                                             forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:availabilityLabel];
        _availabilityLabel = availabilityLabel;

        UIImage *image = [UIImage imageNamed:@"icon_checkbox"];
        UIImage *highlightedImage = [UIImage imageNamed:@"icon_checkbox_checked"];
        NSParameterAssert(image);
        NSParameterAssert(highlightedImage);
        UIImageView *accessoryImageView = [[UIImageView alloc] initWithImage:image highlightedImage:highlightedImage];
        accessoryImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:accessoryImageView];
        _accessoryImageView = accessoryImageView;

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = DW_FORM_CELL_VERTICAL_PADDING;

        [NSLayoutConstraint activateConstraints:@[
            [addressLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                   constant:padding],
            [addressLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                       constant:margin],
            [addressLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                      constant:-padding],

            [portLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                constant:padding],
            [portLabel.leadingAnchor constraintEqualToAnchor:addressLabel.trailingAnchor
                                                    constant:DW_FORM_CELL_SPACING],
            [portLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                   constant:-padding],

            [availabilityLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                        constant:padding],
            [availabilityLabel.leadingAnchor constraintEqualToAnchor:portLabel.trailingAnchor
                                                            constant:DW_FORM_CELL_SPACING],

            [accessoryImageView.leadingAnchor constraintEqualToAnchor:availabilityLabel.trailingAnchor
                                                             constant:DW_FORM_CELL_SPACING],
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

- (void)configureWithModel:(DSSimplifiedMasternodeEntry *)model
                  selected:(BOOL)selected
               searchQuery:(nullable NSString *)searchQuery {
    self.model = model;
    self.searchQuery = searchQuery;

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

    UIFont *addressFont = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    UIColor *addressColor = [UIColor dw_darkTitleColor];
    self.addressLabel.attributedText = [NSAttributedString attributedText:self.model.ipAddressString
                                                                     font:addressFont
                                                                textColor:addressColor
                                                          highlightedText:highlightedText
                                                     highlightedTextColor:highlightedTextColor];

    UIFont *portFont = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    UIColor *portColor = [UIColor dw_quaternaryTextColor];
    self.portLabel.attributedText = [NSAttributedString attributedText:self.model.portString
                                                                  font:portFont
                                                             textColor:portColor
                                                       highlightedText:highlightedText
                                                  highlightedTextColor:highlightedTextColor];

    UIFont *availabilityFont = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    UIColor *availabilityColor = [UIColor dw_secondaryTextColor];
    self.availabilityLabel.attributedText = [NSAttributedString attributedText:self.model.validString
                                                                          font:availabilityFont
                                                                     textColor:availabilityColor
                                                               highlightedText:highlightedText
                                                          highlightedTextColor:highlightedTextColor];
}

@end

NS_ASSUME_NONNULL_END
