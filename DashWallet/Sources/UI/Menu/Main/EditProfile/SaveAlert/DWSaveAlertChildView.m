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

#import "DWSaveAlertChildView.h"
#import "DWActionButton.h"
#import "DWBorderedActionButton.h"
#import "DWUIKit.h"

static CGFloat const ViewCornerRadius = 8.0;
static CGSize const IconSize = {36.0, 36.0};
static CGFloat const ButtonHeight = 39.0;

NS_ASSUME_NONNULL_BEGIN

@interface DWSaveAlertChildView ()

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *subtitleLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWSaveAlertChildView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UIImageView *iconImageView = [[UIImageView alloc] init];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        iconImageView.image = [UIImage imageNamed:@"icon_exclamation_light"];
        [self addSubview:iconImageView];
        _iconImageView = iconImageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.numberOfLines = 0;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.text = NSLocalizedString(@"Save Changes", nil);
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textAlignment = NSTextAlignmentCenter;
        subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        subtitleLabel.textColor = [UIColor dw_secondaryTextColor];
        subtitleLabel.text = NSLocalizedString(@"Would you like to save the changes you made to your profile?", nil);
        [self addSubview:subtitleLabel];
        _subtitleLabel = subtitleLabel;

        DWActionButton *okButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        okButton.translatesAutoresizingMaskIntoConstraints = NO;
        okButton.usedOnDarkBackground = NO;
        okButton.small = YES;
        okButton.inverted = NO;
        [okButton setTitle:NSLocalizedString(@"Yes", nil) forState:UIControlStateNormal];
        [okButton addTarget:self
                      action:@selector(okButtonAction)
            forControlEvents:UIControlEventTouchUpInside];

        DWBorderedActionButton *cancelButton = [[DWBorderedActionButton alloc] initWithFrame:CGRectZero];
        cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        [cancelButton setTitle:NSLocalizedString(@"No", nil) forState:UIControlStateNormal];
        [cancelButton addTarget:self
                         action:@selector(cancelButtonAction)
               forControlEvents:UIControlEventTouchUpInside];

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ okButton, cancelButton ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisHorizontal;
        stackView.distribution = UIStackViewDistributionFillEqually;
        stackView.spacing = 8.0;
        stackView.alignment = UIStackViewAlignmentCenter;
        [self addSubview:stackView];

        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 1 forAxis:UILayoutConstraintAxisVertical];
        [subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 2 forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [iconImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [iconImageView.widthAnchor constraintEqualToConstant:IconSize.width],
            [iconImageView.heightAnchor constraintEqualToConstant:IconSize.height],

            [titleLabel.topAnchor constraintEqualToAnchor:iconImageView.bottomAnchor
                                                 constant:8.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:8.0],
            [self.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                constant:8.0],

            [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                    constant:16.0],
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                        constant:8.0],
            [self.trailingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor
                                                constant:8.0],

            [stackView.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor
                                                constant:44.0],
            [stackView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor
                                                                 constant:8.0],
            [self.trailingAnchor constraintGreaterThanOrEqualToAnchor:stackView.trailingAnchor
                                                             constant:8.0],
            [self.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor],
            [stackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [okButton.heightAnchor constraintEqualToConstant:ButtonHeight],
            [cancelButton.heightAnchor constraintEqualToConstant:ButtonHeight],
            [stackView.heightAnchor constraintEqualToConstant:ButtonHeight],
        ]];
    }
    return self;
}

- (void)okButtonAction {
    [self.delegate saveAlertChildViewOKAction:self];
}

- (void)cancelButtonAction {
    [self.delegate saveAlertChildViewCancelAction:self];
}

@end
