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

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;

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

        UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
        activityIndicatorView.color = [UIColor dw_darkTitleColor];
        [self addSubview:activityIndicatorView];
        _activityIndicatorView = activityIndicatorView;

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

            [activityIndicatorView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [activityIndicatorView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor
                                                     constant:5.0],
            [self.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
        ]];

        [self mvvm_observe:DW_KEYPATH(self, rule.validationResult)
                      with:^(typeof(self) self, NSNumber *value) {
                          [self setValidationResult:self.rule.validationResult];
                      }];
    }
    return self;
}

- (void)setValidationResult:(DWUsernameValidationRuleResult)validationResult {
    self.titleLabel.text = self.rule.title;

    switch (validationResult) {
        case DWUsernameValidationRuleResultEmpty:
            self.hidden = NO;
            self.iconImageView.image = nil;
            self.iconImageView.tintColor = nil;
            self.titleLabel.textColor = [UIColor dw_darkTitleColor];
            [self.activityIndicatorView stopAnimating];
            break;
        case DWUsernameValidationRuleResultLoading:
            self.hidden = NO;
            self.iconImageView.image = nil;
            self.iconImageView.tintColor = nil;
            self.titleLabel.textColor = [UIColor dw_darkTitleColor];
            [self.activityIndicatorView startAnimating];
            break;
        case DWUsernameValidationRuleResultValid:
            self.hidden = NO;
            self.iconImageView.image = [UIImage imageNamed:@"validation_checkmark"];
            self.iconImageView.tintColor = [UIColor dw_greenColor];
            self.titleLabel.textColor = [UIColor dw_darkTitleColor];
            [self.activityIndicatorView stopAnimating];
            break;
        case DWUsernameValidationRuleResultInvalid:
            self.hidden = NO;
            self.iconImageView.image = [UIImage imageNamed:@"validation_cross"];
            self.iconImageView.tintColor = nil;
            self.titleLabel.textColor = [UIColor dw_darkTitleColor];
            [self.activityIndicatorView stopAnimating];
            break;
        case DWUsernameValidationRuleResultInvalidCritical:
        case DWUsernameValidationRuleResultError:
            self.hidden = NO;
            self.iconImageView.image = [UIImage imageNamed:@"validation_cross"];
            self.iconImageView.tintColor = nil;
            self.titleLabel.textColor = [UIColor dw_redColor];
            [self.activityIndicatorView stopAnimating];
            break;
        case DWUsernameValidationRuleResultHidden:
            self.hidden = YES;
            self.iconImageView.image = nil;
            self.iconImageView.tintColor = nil;
            self.titleLabel.textColor = [UIColor dw_darkTitleColor];
            [self.activityIndicatorView stopAnimating];
            break;
    }
}

@end
