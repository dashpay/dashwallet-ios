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

#import "DWExploreContentsView.h"

#import "DWExploreButton.h"
#import "DWUIKit.h"

@implementation DWExploreContentsView

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

        UIView *centerView = [[UIView alloc] init];
        centerView.translatesAutoresizingMaskIntoConstraints = NO;
        centerView.backgroundColor = [UIColor dw_backgroundColor];
        centerView.layer.cornerRadius = 8.0;
        centerView.layer.masksToBounds = YES;
        [contentView addSubview:centerView];

        DWExploreButton *firstButton = [[DWExploreButton alloc] init];
        firstButton.translatesAutoresizingMaskIntoConstraints = NO;
        [firstButton setImage:[UIImage imageNamed:@"explore_item_1"]
                        title:NSLocalizedString(@"Where to Spend?", nil)
                     subtitle:NSLocalizedString(@"Find merchants who accept Dash as payment.", nil)];
        [firstButton addTarget:self action:@selector(spendButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [centerView addSubview:firstButton];

        UIView *separator = [[UIView alloc] init];
        separator.translatesAutoresizingMaskIntoConstraints = NO;
        separator.backgroundColor = [UIColor dw_separatorLineColor];
        [centerView addSubview:separator];

        DWExploreButton *secondButton = [[DWExploreButton alloc] init];
        secondButton.translatesAutoresizingMaskIntoConstraints = NO;
        [secondButton setImage:[UIImage imageNamed:@"explore_item_2"]
                         title:NSLocalizedString(@"ATMs", nil)
                      subtitle:NSLocalizedString(@"Find where to buy or sell DASH and other cryptocurrencies for cash.", nil)];
        [secondButton addTarget:self action:@selector(atmButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [centerView addSubview:secondButton];

        CGFloat padding = 15.0;
        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

            [centerView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:padding],
            [centerView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:padding],
            [contentView.trailingAnchor constraintEqualToAnchor:centerView.trailingAnchor
                                                       constant:padding],
            [contentView.bottomAnchor constraintEqualToAnchor:centerView.bottomAnchor
                                                     constant:padding],

            [firstButton.topAnchor constraintEqualToAnchor:centerView.topAnchor
                                                  constant:10],
            [firstButton.leadingAnchor constraintEqualToAnchor:centerView.leadingAnchor],
            [centerView.trailingAnchor constraintEqualToAnchor:firstButton.trailingAnchor],

            [separator.topAnchor constraintEqualToAnchor:firstButton.bottomAnchor],
            [separator.leadingAnchor constraintEqualToAnchor:centerView.leadingAnchor
                                                    constant:15 + 34 + 10],
            [centerView.trailingAnchor constraintEqualToAnchor:separator.trailingAnchor],
            [separator.heightAnchor constraintEqualToConstant:1],

            [secondButton.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
            [secondButton.leadingAnchor constraintEqualToAnchor:centerView.leadingAnchor],
            [centerView.trailingAnchor constraintEqualToAnchor:secondButton.trailingAnchor],
            [centerView.bottomAnchor constraintEqualToAnchor:secondButton.bottomAnchor
                                                    constant:10],
        ]];
    }
    return self;
}

- (void)spendButtonAction:(UIControl *)sender {
    [self.delegate exploreContentsView:self spendButtonAction:sender];
}

- (void)atmButtonAction:(UIControl *)sender {
    [self.delegate exploreContentsView:self atmButtonAction:sender];
}

@end
