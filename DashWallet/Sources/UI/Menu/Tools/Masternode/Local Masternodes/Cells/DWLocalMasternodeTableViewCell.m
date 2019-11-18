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

#import "DWLocalMasternodeTableViewCell.h"

#import "DWSharedUIConstants.h"
#import "DWUIKit.h"
#import "NSAttributedString+DWHighlightText.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const ACCESSORY_SIZE = {10.0, 19.0};

@interface DWLocalMasternodeTableViewCell ()

@property (readonly, strong, nonatomic) UILabel *nameLabel;
@property (readonly, strong, nonatomic) UILabel *addressLabel;
@property (readonly, strong, nonatomic) UILabel *portLabel;
@property (readonly, nonatomic, strong) UIImageView *accessoryImageView;

@property (nullable, nonatomic, strong) DSLocalMasternode *model;
@property (nullable, nonatomic, copy) NSString *searchQuery;

@end

@implementation DWLocalMasternodeTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *contentView = self.roundedContentView;
        NSParameterAssert(contentView);

        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        nameLabel.backgroundColor = [UIColor dw_backgroundColor];
        nameLabel.textColor = [UIColor dw_darkTitleColor];
        nameLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        nameLabel.adjustsFontForContentSizeCategory = YES;
        nameLabel.minimumScaleFactor = 0.5;
        nameLabel.adjustsFontSizeToFitWidth = YES;
        [nameLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisVertical];
        [nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 30
                                                   forAxis:UILayoutConstraintAxisHorizontal];
        [nameLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 30
                                     forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:nameLabel];
        _nameLabel = nameLabel;

        UILabel *addressLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
        addressLabel.backgroundColor = [UIColor dw_backgroundColor];
        addressLabel.textColor = [UIColor dw_quaternaryTextColor];
        addressLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        addressLabel.adjustsFontForContentSizeCategory = YES;
        addressLabel.minimumScaleFactor = 0.5;
        addressLabel.adjustsFontSizeToFitWidth = YES;
        [addressLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                      forAxis:UILayoutConstraintAxisVertical];
        [addressLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 10
                                                      forAxis:UILayoutConstraintAxisHorizontal];
        [addressLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 20
                                        forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:addressLabel];
        _addressLabel = addressLabel;

        UILabel *portLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        portLabel.translatesAutoresizingMaskIntoConstraints = NO;
        portLabel.backgroundColor = [UIColor dw_backgroundColor];
        portLabel.textAlignment = NSTextAlignmentRight;
        portLabel.textColor = [UIColor dw_secondaryTextColor];
        portLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        portLabel.adjustsFontForContentSizeCategory = YES;
        portLabel.minimumScaleFactor = 0.5;
        portLabel.adjustsFontSizeToFitWidth = YES;
        [portLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisVertical];
        [portLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 20
                                                   forAxis:UILayoutConstraintAxisHorizontal];
        [portLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 10
                                     forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:portLabel];
        portLabel = portLabel;

        UIImage *image = [UIImage imageNamed:@"icon_disclosure_indicator"];
        NSParameterAssert(image);
        UIImageView *accessoryImageView = [[UIImageView alloc] initWithImage:image];
        accessoryImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:accessoryImageView];
        _accessoryImageView = accessoryImageView;

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = DW_FORM_CELL_VERTICAL_PADDING;

        [NSLayoutConstraint activateConstraints:@[
            [nameLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                constant:padding],
            [nameLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                    constant:margin],
            [nameLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                   constant:-padding],

            [addressLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                   constant:padding],
            [addressLabel.leadingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor
                                                       constant:DW_FORM_CELL_SPACING],
            [addressLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                      constant:-padding],

            [portLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                constant:padding],
            [portLabel.leadingAnchor constraintEqualToAnchor:addressLabel.trailingAnchor
                                                    constant:DW_FORM_CELL_SPACING],

            [accessoryImageView.leadingAnchor constraintEqualToAnchor:portLabel.trailingAnchor
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

- (void)configureWithModel:(DSLocalMasternode *)model
               searchQuery:(nullable NSString *)searchQuery {
    self.model = model;
    self.searchQuery = searchQuery;

    self.portLabel.text = model.ipAddressString;

    [self setupObserving];

    [self reloadAttributedData];
}

- (void)setupObserving {
    [self mvvm_observe:DW_KEYPATH(self, model.name)
                  with:^(__typeof(self) self, NSString *value) {
                      self.nameLabel.text = value ?: NSLocalizedString(@"Unnamed", nil);
                  }];
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

    UIFont *codeFont = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    UIColor *codeColor = [UIColor dw_darkTitleColor];
    NSString *name = self.model.name;
    if (!name)
        name = NSLocalizedString(@"Unnamed", nil);
    self.nameLabel.attributedText = [NSAttributedString attributedText:name
                                                                  font:codeFont
                                                             textColor:codeColor
                                                       highlightedText:highlightedText
                                                  highlightedTextColor:highlightedTextColor];

    UIFont *nameFont = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    UIColor *nameColor = [UIColor dw_quaternaryTextColor];
    self.addressLabel.attributedText = [NSAttributedString attributedText:self.model.ipAddressAndIfNonstandardPortString
                                                                     font:nameFont
                                                                textColor:nameColor
                                                          highlightedText:highlightedText
                                                     highlightedTextColor:highlightedTextColor];

    self.portLabel.attributedText = [NSAttributedString attributedText:self.model.portString
                                                                  font:nameFont
                                                             textColor:nameColor
                                                       highlightedText:highlightedText
                                                  highlightedTextColor:highlightedTextColor];
}

@end

NS_ASSUME_NONNULL_END
