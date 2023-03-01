//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWExploreTestnetContentsView.h"

#import "DWEnvironment.h"
#import "DWUIKit.h"

@interface DWCrowdNodeAPYView : UIView

@end

@interface DWExploreTestnetContentsView ()
@end

@implementation DWExploreTestnetContentsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_darkBlueColor];

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        contentView.layer.cornerRadius = 8.0;
        contentView.layer.masksToBounds = YES;
        contentView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner; // TL | TR
        [self addSubview:contentView];

        UIView *subContentView = [[UIView alloc] init];
        subContentView.translatesAutoresizingMaskIntoConstraints = NO;
        subContentView.backgroundColor = [UIColor dw_backgroundColor];
        subContentView.layer.cornerRadius = 8.0;
        subContentView.layer.masksToBounds = YES;
        [contentView addSubview:subContentView];

        UIStackView *buttonsStackView = [UIStackView new];
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        buttonsStackView.spacing = 8;
        buttonsStackView.axis = UILayoutConstraintAxisVertical;
        buttonsStackView.distribution = UIStackViewDistributionEqualSpacing;
        [subContentView addSubview:buttonsStackView];

        __weak typeof(self) weakSelf = self;
        DWExploreTestnetContentsViewCell *merchantsItem = [self itemWithImage:[UIImage imageNamed:@"image.explore.dash.wheretospend"]
                                                                        title:NSLocalizedString(@"Where to Spend?", nil)
                                                                     subtitle:NSLocalizedString(@"Find merchants who accept Dash as payment.", nil)
                                                                       action:^{
                                                                           __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                           if (!strongSelf) {
                                                                               return;
                                                                           }

                                                                           strongSelf.whereToSpendHandler();
                                                                       }];
        [buttonsStackView addArrangedSubview:merchantsItem];

        DWExploreTestnetContentsViewCell *atmItem = [self itemWithImage:[UIImage imageNamed:@"image.explore.dash.atm"]
                                                                  title:NSLocalizedString(@"ATMs", nil)
                                                               subtitle:NSLocalizedString(@"Find where to buy or sell DASH and other cryptocurrencies for cash.", nil)
                                                                 action:^{
                                                                     __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                     if (!strongSelf) {
                                                                         return;
                                                                     }

                                                                     strongSelf.atmHandler();
                                                                 }];
        [buttonsStackView addArrangedSubview:atmItem];

        // TODO: Fix typo in subtitle: should be taps not clicks
        DWExploreTestnetContentsViewCell *cnItem = [self itemWithImage:[UIImage imageNamed:@"image.explore.dash.staking"]
                                                                 title:NSLocalizedString(@"Staking", nil)
                                                              subtitle:NSLocalizedString(@"Easily stake Dash and earn passive income with a few simple clicks.", nil)
                                                                action:^{
                                                                    __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                    if (!strongSelf) {
                                                                        return;
                                                                    }

                                                                    strongSelf.stakingHandler();
                                                                }];
        [cnItem addContent:[[DWCrowdNodeAPYView alloc] initWithFrame:CGRectZero]];
        [buttonsStackView addArrangedSubview:cnItem];

        CGFloat verticalPadding = 10;

        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [subContentView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                     constant:15],
            [subContentView.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor
                                                                  constant:-35],
            [subContentView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                          constant:-15],
            [subContentView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                         constant:15],

            [buttonsStackView.topAnchor constraintEqualToAnchor:subContentView.topAnchor
                                                       constant:verticalPadding],
            [buttonsStackView.bottomAnchor constraintEqualToAnchor:subContentView.bottomAnchor
                                                          constant:-verticalPadding],
            [buttonsStackView.trailingAnchor constraintEqualToAnchor:subContentView.trailingAnchor],
            [buttonsStackView.leadingAnchor constraintEqualToAnchor:subContentView.leadingAnchor],
        ]];
    }
    return self;
}

- (nonnull DWExploreTestnetContentsViewCell *)itemWithImage:(UIImage *)image title:(NSString *)title subtitle:(NSString *)subtitle action:(void (^)(void))action {
    DWExploreTestnetContentsViewCell *item = [[DWExploreTestnetContentsViewCell alloc] initWithFrame:CGRectZero];
    item.translatesAutoresizingMaskIntoConstraints = NO;
    [item setImage:image];
    [item setTitle:title];
    [item setSubtitle:subtitle];
    [item setActionHandler:action];
    return item;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    if (indexPath.row == 0) {
        _whereToSpendHandler();
    }
    else if (indexPath.row == 1) {
        _atmHandler();
    }
    else {
        _stakingHandler();
    }
}

@end

@interface DWExploreTestnetContentsViewCell ()
@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *descLabel;
@property (readonly, nonatomic, strong) UIStackView *contentStack;
@end

@implementation DWExploreTestnetContentsViewCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self configureHierarchy];
    }

    return self;
}

- (void)buttonAction:(UIButton *)sender {
    _actionHandler();
}

- (void)configureHierarchy {
    self.backgroundColor = [UIColor dw_backgroundColor];

    UIStackView *stackView = [UIStackView new];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.spacing = 10;
    stackView.alignment = UIStackViewAlignmentTop;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stackView];

    UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 34, 34)];
    iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    iconImageView.contentMode = UIViewContentModeCenter;
    [stackView addArrangedSubview:iconImageView];
    _iconImageView = iconImageView;

    UIStackView *labelsStackView = [UIStackView new];
    labelsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    labelsStackView.axis = UILayoutConstraintAxisVertical;
    labelsStackView.spacing = 1;
    labelsStackView.alignment = UIStackViewAlignmentLeading;
    [stackView addArrangedSubview:labelsStackView];
    _contentStack = labelsStackView;

    UILabel *titleLabel = [[UILabel alloc] init];
    [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.numberOfLines = 0;
    [labelsStackView addArrangedSubview:titleLabel];
    _titleLabel = titleLabel;

    UILabel *descLabel = [[UILabel alloc] init];
    [descLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.textColor = [UIColor secondaryLabelColor];
    descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    descLabel.textAlignment = NSTextAlignmentLeft;
    descLabel.numberOfLines = 0;
    [labelsStackView addArrangedSubview:descLabel];
    _descLabel = descLabel;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.titleLabel.text = @"";
    [button addTarget:self action:@selector(buttonAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [iconImageView.widthAnchor constraintEqualToConstant:34],
        [iconImageView.heightAnchor constraintEqualToConstant:34],

        [stackView.topAnchor constraintEqualToAnchor:self.topAnchor
                                            constant:12],
        [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                               constant:-12],
        [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                constant:15],
        [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [button.topAnchor constraintEqualToAnchor:self.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
}

- (UIImage *)image {
    return self.iconImageView.image;
}

- (void)setImage:(UIImage *)image {
    self.iconImageView.image = image;
}

- (NSString *)title {
    return self.titleLabel.text;
}

- (void)setTitle:(NSString *)title {
    self.titleLabel.text = title;
}

- (NSString *)subtitle {
    return self.descLabel.text;
}

- (void)setSubtitle:(NSString *)subtitle {
    self.descLabel.text = subtitle;
}

- (void)addContent:(UIView *)view {
    UIView *last = [[_contentStack arrangedSubviews] lastObject];
    [_contentStack setCustomSpacing:10 afterView:last];
    [_contentStack addArrangedSubview:view];
}
@end


@implementation DWCrowdNodeAPYView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addCrowdNodeAPYLabel];
    }

    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 24.0f);
}

- (void)addCrowdNodeAPYLabel {
    UIColor *systemGreen = [UIColor colorWithRed:98.0 / 255.0 green:182.0 / 255.0 blue:125.0 / 255.0 alpha:1.0];

    UIStackView *apyStackView = [UIStackView new];
    apyStackView.translatesAutoresizingMaskIntoConstraints = NO;
    apyStackView.axis = UILayoutConstraintAxisHorizontal;
    apyStackView.spacing = 4;
    apyStackView.backgroundColor = [systemGreen colorWithAlphaComponent:0.1];
    apyStackView.layer.cornerRadius = 6.0;
    apyStackView.layer.masksToBounds = YES;
    apyStackView.layoutMargins = UIEdgeInsetsMake(0, 8, 0, 8);
    apyStackView.layoutMarginsRelativeArrangement = YES;
    [self addSubview:apyStackView];

    UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 14, 14)];
    iconImageView.contentMode = UIViewContentModeCenter;
    [iconImageView setImage:[UIImage imageNamed:@"image.crowdnode.apy"]];
    [apyStackView addArrangedSubview:iconImageView];

    UILabel *apiLabel = [[UILabel alloc] init];
    apiLabel.textColor = systemGreen;
    apiLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    apiLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Current APY = %@", @"Crowdnode"), [self apy]];
    [apyStackView addArrangedSubview:apiLabel];

    [NSLayoutConstraint activateConstraints:@[
        [apyStackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [apyStackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [apyStackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [apyStackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [apyStackView.heightAnchor constraintEqualToConstant:24.0f],
    ]];
}

- (NSString *)apy {
    double apyValue = [DWEnvironment sharedInstance].apy.doubleValue * 0.85;

    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle = NSNumberFormatterPercentStyle;
    numberFormatter.minimumFractionDigits = 0;
    numberFormatter.maximumFractionDigits = 2;
    numberFormatter.multiplier = @(1);
    return [numberFormatter stringFromNumber:@(apyValue)];
}

@end
