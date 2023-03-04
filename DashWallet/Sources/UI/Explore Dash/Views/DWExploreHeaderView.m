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

CGFloat const kExploreHeaderViewHeight = 351.0f;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_darkBlueColor];
        self.spacing = 4;
        self.axis = UILayoutConstraintAxisVertical;
        self.distribution = UIStackViewDistributionFillProportionally;

        UIImageView *iconImageView = [[UIImageView alloc] init];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [self addArrangedSubview:iconImageView];

        _iconImageView = iconImageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.textColor = [UIColor whiteColor]; // always white
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleLargeTitle];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.numberOfLines = 0;
        titleLabel.minimumScaleFactor = 0.4;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        [self addArrangedSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *descLabel = [[UILabel alloc] init];
        descLabel.translatesAutoresizingMaskIntoConstraints = NO;
        descLabel.textColor = [UIColor whiteColor]; // always white
        descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        descLabel.textAlignment = NSTextAlignmentCenter;
        descLabel.numberOfLines = 0;
        descLabel.adjustsFontSizeToFitWidth = YES;
        descLabel.minimumScaleFactor = 0.4;
        [self addArrangedSubview:descLabel];
        _descLabel = descLabel;

        [iconImageView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisVertical];
        [descLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.heightAnchor constraintLessThanOrEqualToConstant:250.0],
            [descLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:15.0],
            [descLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                     constant:-15.0],
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
