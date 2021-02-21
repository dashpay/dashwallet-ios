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

#import "DPAlertChildContentsView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DPAlertChildContentsView ()

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *descriptionLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DPAlertChildContentsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIImageView *iconImageView = [[UIImageView alloc] init];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeCenter;
        [self addSubview:iconImageView];
        _iconImageView = iconImageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.numberOfLines = 0;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *descLabel = [[UILabel alloc] init];
        descLabel.translatesAutoresizingMaskIntoConstraints = NO;
        descLabel.textAlignment = NSTextAlignmentCenter;
        descLabel.numberOfLines = 0;
        descLabel.textColor = [UIColor dw_secondaryTextColor];
        descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        descLabel.adjustsFontForContentSizeCategory = YES;
        _descriptionLabel = descLabel;

        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];
        [descLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [iconImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:iconImageView.bottomAnchor
                                                 constant:16.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

            [descLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                constant:16.0],
            [descLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:descLabel.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:descLabel.bottomAnchor],
        ]];
    }
    return self;
}

- (UIImage *)icon {
    return self.iconImageView.image;
}

- (void)setIcon:(UIImage *)icon {
    self.iconImageView.image = icon;
}

- (NSString *)title {
    return self.titleLabel.text;
}

- (void)setTitle:(NSString *)title {
    self.titleLabel.text = title;
}

- (NSString *)desc {
    return self.descriptionLabel.text;
}

- (void)setDesc:(NSString *)desc {
    self.descriptionLabel.text = desc;
}

@end
