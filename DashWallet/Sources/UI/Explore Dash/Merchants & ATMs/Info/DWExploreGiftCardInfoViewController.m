//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

#import "DWExploreGiftCardInfoViewController.h"
#import "DWUIKit.h"

@interface DWExploreGiftCardInfoViewController ()

@end

@implementation DWExploreGiftCardInfoViewController

- (void)configureHierarchy {
    [super configureHierarchy];

    UIStackView *contentView = [UIStackView new];
    contentView.axis = UILayoutConstraintAxisVertical;
    contentView.spacing = 30;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    // contentView.distribution = UIStackViewDistributionEqualSpacing;
    [self.view addSubview:contentView];

    UIStackView *topStackView = [UIStackView new];
    topStackView.axis = UILayoutConstraintAxisVertical;
    topStackView.spacing = 10;
    topStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addArrangedSubview:topStackView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle1];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    titleLabel.text = NSLocalizedString(@"How to Use a Gift Card", nil);
    [topStackView addArrangedSubview:titleLabel];

    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.textColor = [UIColor labelColor];
    descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.numberOfLines = 0;
    descLabel.text = NSLocalizedString(@"Not all of the stores accept DASH directly, but you can buy a gift card with your Dash.", nil);
    [topStackView addArrangedSubview:descLabel];

    NSArray<NSString *> *titles = @[ NSLocalizedString(@"Find a merchant.", nil),
                                     NSLocalizedString(@"Buy a gift card with Dash.", nil),
                                     NSLocalizedString(@"Redeem your gift card online within seconds or at the cashier.", nil) ];
    NSArray<NSString *> *icons = @[ @"image.explore.dash.wts.map",
                                    @"image.explore.dash.wts.card.blue",
                                    @"image.explore.dash.wts.lighting" ];
    size_t itemCount = 3;

    for (size_t i = 0; i < itemCount; i++) {
        NSString *title = titles[i];
        UIImage *icon = [UIImage imageNamed:icons[i]];
        UIView *item = [self itemViewFor:title image:icon];
        [contentView addArrangedSubview:item];
    }

    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor
                                              constant:74],
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                  constant:30],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                   constant:-30],

    ]];
}

- (UIView *)itemViewFor:(NSString *)title image:(UIImage *)image {
    UIStackView *itemStackView = [UIStackView new];
    itemStackView.axis = UILayoutConstraintAxisHorizontal;
    itemStackView.spacing = 10;
    itemStackView.translatesAutoresizingMaskIntoConstraints = NO;
    itemStackView.alignment = UIStackViewAlignmentFirstBaseline;

    UIImageView *iconImageView = [[UIImageView alloc] initWithImage:image];
    iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    iconImageView.contentMode = UIViewContentModeCenter;
    [itemStackView addArrangedSubview:iconImageView];

    UILabel *itemTitleLabel = [[UILabel alloc] init];
    itemTitleLabel.text = title;
    itemTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    itemTitleLabel.textColor = [UIColor labelColor]; // always white
    itemTitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    itemTitleLabel.textAlignment = NSTextAlignmentLeft;
    itemTitleLabel.numberOfLines = 0;
    [itemStackView addArrangedSubview:itemTitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconImageView.widthAnchor constraintEqualToConstant:50],
        [iconImageView.centerYAnchor constraintEqualToAnchor:itemTitleLabel.topAnchor
                                                    constant:10],
    ]];

    return itemStackView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

@end
