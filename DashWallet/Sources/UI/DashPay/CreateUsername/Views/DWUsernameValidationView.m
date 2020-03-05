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

#import "DWUsernameValidationView.h"

#import "DWUIKit.h"

static CGFloat const ICON_SIZE = 16.0;

NS_ASSUME_NONNULL_BEGIN

@interface DWUsernameValidationView ()

@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWUsernameValidationView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeCenter;
        [self addSubview:iconImageView];
        _iconImageView = iconImageView;

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = self.backgroundColor;
        titleLabel.numberOfLines = 0;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [iconImageView.widthAnchor constraintEqualToConstant:ICON_SIZE],
            [iconImageView.heightAnchor constraintEqualToConstant:ICON_SIZE],

            [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor
                                                     constant:5.0],
            [self.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
        ]];
    }
    return self;
}

- (NSString *)title {
    return self.titleLabel.text;
}

- (void)setTitle:(NSString *)title {
    self.titleLabel.text = title;
}

- (void)setValidationResult:(DWUsernameValidationRuleResult)validationResult {
    switch (validationResult) {
        case DWUsernameValidationRuleResultEmpty:
            self.hidden = NO;
            self.iconImageView.image = nil;
            self.iconImageView.tintColor = nil;
            break;
        case DWUsernameValidationRuleResultValid:
            self.hidden = NO;
            self.iconImageView.image = [UIImage imageNamed:@"validation_checkmark"];
            self.iconImageView.tintColor = [UIColor dw_darkTitleColor];
            break;
        case DWUsernameValidationRuleResultInvalid:
            self.hidden = NO;
            self.iconImageView.image = [UIImage imageNamed:@"validation_cross"];
            self.iconImageView.tintColor = nil;
            break;
        case DWUsernameValidationRuleResultHidden:
            self.hidden = YES;
            self.iconImageView.image = nil;
            self.iconImageView.tintColor = nil;
            break;
    }
}

@end
