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

#import "DWUIKit.h"

@implementation DWExploreTestnetContentsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_darkBlueColor];

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor dw_backgroundColor];
        contentView.layer.cornerRadius = 8.0;
        contentView.layer.masksToBounds = YES;
        contentView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner; // TL | TR
        [self addSubview:contentView];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.text = NSLocalizedString(@"How do I get Test Dash?", nil);
        titleLabel.numberOfLines = 0;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        [contentView addSubview:titleLabel];

        UILabel *descLabel = [[UILabel alloc] init];
        descLabel.translatesAutoresizingMaskIntoConstraints = NO;
        descLabel.textColor = [UIColor dw_darkTitleColor];
        descLabel.text = NSLocalizedString(@"Test Dash is free and can be obtained from what is called a faucet.\nCopy an address from the Receive screen of your wallet and click on the button bellow to get your Dash.", nil);
        descLabel.numberOfLines = 0;
        descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        [contentView addSubview:descLabel];

        [titleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [descLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        CGFloat padding = 16.0;
        CGFloat spacing = 4.0;
        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:30],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:padding],
            [contentView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                       constant:padding],

            [descLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                constant:spacing],
            [descLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                    constant:padding],
            [contentView.trailingAnchor constraintEqualToAnchor:descLabel.trailingAnchor
                                                       constant:padding],
            [contentView.bottomAnchor constraintEqualToAnchor:descLabel.bottomAnchor
                                                     constant:padding],
        ]];
    }
    return self;
}

@end
