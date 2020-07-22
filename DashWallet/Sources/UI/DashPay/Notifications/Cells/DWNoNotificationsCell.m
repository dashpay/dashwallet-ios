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

        UIImage *image = [UIImage imageNamed:@"dp_no_notifications"];
        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:image];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:iconImageView];

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.backgroundColor = self.backgroundColor;
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.textColor = [UIColor dw_tertiaryTextColor];
        label.text = NSLocalizedString(@"There are no new notifications", nil);
        [self.contentView addSubview:label];

        [iconImageView setContentCompressionResistancePriority:UILayoutPriorityRequired - 1
                                                       forAxis:UILayoutConstraintAxisVertical];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired
                                               forAxis:UILayoutConstraintAxisVertical];

        const CGFloat spacing = 30.0;
        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;

        NSLayoutConstraint *labelIconConstraint = [label.topAnchor constraintGreaterThanOrEqualToAnchor:iconImageView.bottomAnchor
                                                                                               constant:spacing];
        labelIconConstraint.priority = UILayoutPriorityRequired - 2;

        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                    constant:spacing],
            [iconImageView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],

            labelIconConstraint,
            [label.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.bottomAnchor constraintEqualToAnchor:label.bottomAnchor
                                               constant:spacing],
            [guide.trailingAnchor constraintEqualToAnchor:label.trailingAnchor],

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
