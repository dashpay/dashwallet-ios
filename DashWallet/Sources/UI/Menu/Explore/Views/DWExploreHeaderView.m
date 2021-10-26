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

#import "DWExploreHeaderView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWExploreHeaderView ()

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *descLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWExploreHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_darkBlueColor];

        UIImageView *iconImageView = [[UIImageView alloc] init];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeCenter;
        [self addSubview:iconImageView];
        _iconImageView = iconImageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.textColor = [UIColor whiteColor]; // always white
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleLargeTitle];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.numberOfLines = 0;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *descLabel = [[UILabel alloc] init];
        descLabel.translatesAutoresizingMaskIntoConstraints = NO;
        descLabel.textColor = [UIColor whiteColor]; // always white
        descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        descLabel.textAlignment = NSTextAlignmentCenter;
        descLabel.numberOfLines = 0;
        [self addSubview:descLabel];
        _descLabel = descLabel;

        [iconImageView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [titleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [descLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        CGFloat padding = 16.0;
        CGFloat spacing = 4.0;
        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:iconImageView.bottomAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                constant:padding],

            [descLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                constant:spacing],
            [descLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:descLabel.trailingAnchor
                                                constant:padding],
            [self.bottomAnchor constraintEqualToAnchor:descLabel.bottomAnchor
                                              constant:padding],
        ]];
    }
    return self;
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

@end
