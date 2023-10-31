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

#import "DWNoNotificationsCell.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNoNotificationsCell ()

@property (nullable, nonatomic, strong) NSLayoutConstraint *contentWidthConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWNoNotificationsCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        self.contentView.backgroundColor = self.backgroundColor;

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:contentView];

        UIImage *image = [UIImage imageNamed:@"dp_no_notifications"];
        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:image];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [contentView addSubview:iconImageView];

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.backgroundColor = self.backgroundColor;
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.textColor = [UIColor dw_tertiaryTextColor];
        label.text = NSLocalizedString(@"There are no new notifications", nil);
        [contentView addSubview:label];

        [iconImageView setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                       forAxis:UILayoutConstraintAxisVertical];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired
                                               forAxis:UILayoutConstraintAxisVertical];
        [iconImageView setContentHuggingPriority:UILayoutPriorityRequired
                                         forAxis:UILayoutConstraintAxisVertical];
        [label setContentHuggingPriority:UILayoutPriorityRequired
                                 forAxis:UILayoutConstraintAxisVertical];

        const CGFloat spacing = 30.0;

        NSLayoutConstraint *heightConstraint = [contentView.heightAnchor constraintLessThanOrEqualToConstant:200];
        heightConstraint.priority = UILayoutPriorityRequired - 1;

        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                      constant:16],
            [self.contentView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                            constant:16],
            heightConstraint,

            [iconImageView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                    constant:spacing],
            [iconImageView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],

            [label.topAnchor constraintEqualToAnchor:iconImageView.bottomAnchor
                                            constant:spacing],
            [label.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:label.bottomAnchor
                                                     constant:spacing],
            [contentView.trailingAnchor constraintEqualToAnchor:label.trailingAnchor],

            (_contentWidthConstraint = [self.contentView.widthAnchor constraintEqualToConstant:200]),
        ]];
    }
    return self;
}

- (CGFloat)contentWidth {
    return self.contentWidthConstraint.constant;
}

- (void)setContentWidth:(CGFloat)contentWidth {
    self.contentWidthConstraint.constant = contentWidth;
}

@end
