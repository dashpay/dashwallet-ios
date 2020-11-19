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

#import "DWAvatarExternalSourceView.h"

#import "DWActionButton.h"
#import "DWBorderedActionButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const IconSize = {24.0, 24.0};
static CGFloat const ButtonHeight = 39.0;

@interface DWAvatarExternalSourceView () <UITextFieldDelegate>

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *subtitleLabel;
@property (readonly, nonatomic, strong) UITextField *textField;
@property (readonly, nonatomic, strong) UILabel *descLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWAvatarExternalSourceView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UIImageView *iconImageView = [[UIImageView alloc] init];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:iconImageView];
        _iconImageView = iconImageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.numberOfLines = 0;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textAlignment = NSTextAlignmentCenter;
        subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        subtitleLabel.textColor = [UIColor dw_secondaryTextColor];
        [self addSubview:subtitleLabel];
        _subtitleLabel = subtitleLabel;

        UITextField *textField = [[UITextField alloc] init];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.delegate = self;
        textField.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        textField.textColor = [UIColor dw_darkTitleColor];
        textField.layer.borderColor = [UIColor dw_separatorLineColor].CGColor;
        textField.layer.cornerRadius = 8.0;
        textField.layer.masksToBounds = YES;
        textField.layer.borderWidth = 1.0;
        textField.textAlignment = NSTextAlignmentCenter;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        [self addSubview:textField];
        _textField = textField;

        UILabel *descLabel = [[UILabel alloc] init];
        descLabel.translatesAutoresizingMaskIntoConstraints = NO;
        descLabel.numberOfLines = 0;
        descLabel.textAlignment = NSTextAlignmentCenter;
        descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
        descLabel.textColor = [UIColor dw_secondaryTextColor];
        [self addSubview:descLabel];
        _descLabel = descLabel;

        DWActionButton *okButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        okButton.translatesAutoresizingMaskIntoConstraints = NO;
        okButton.usedOnDarkBackground = NO;
        okButton.small = YES;
        okButton.inverted = NO;
        [okButton setTitle:NSLocalizedString(@"OK", nil) forState:UIControlStateNormal];
        [okButton addTarget:self
                      action:@selector(okButtonAction)
            forControlEvents:UIControlEventTouchUpInside];

        DWBorderedActionButton *cancelButton = [[DWBorderedActionButton alloc] initWithFrame:CGRectZero];
        cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        [cancelButton setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];
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
        [descLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 3 forAxis:UILayoutConstraintAxisVertical];


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

            [textField.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor
                                                constant:16.0],
            [textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:16.0],
            [self.trailingAnchor constraintEqualToAnchor:textField.trailingAnchor
                                                constant:16.0],
            [textField.heightAnchor constraintEqualToConstant:52.0],

            [descLabel.topAnchor constraintEqualToAnchor:textField.bottomAnchor
                                                constant:16.0],
            [descLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:8.0],
            [self.trailingAnchor constraintEqualToAnchor:descLabel.trailingAnchor
                                                constant:8.0],

            [stackView.topAnchor constraintEqualToAnchor:descLabel.bottomAnchor
                                                constant:56.0],
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

- (NSString *)input {
    return self.textField.text;
}

- (void)setConfig:(DWAvatarExternalSourceConfig *)config {
    _config = config;

    self.iconImageView.image = config.icon;
    self.titleLabel.text = config.title;
    self.subtitleLabel.text = config.subtitle;
    self.descLabel.text = config.desc;
    self.textField.placeholder = config.placeholder;
    self.textField.keyboardType = config.keyboardType;
}

- (void)showError:(NSString *)error {
    self.subtitleLabel.text = error;
    self.subtitleLabel.textColor = [UIColor dw_redColor];
}

- (void)showSubtitle {
    self.subtitleLabel.text = self.config.subtitle;
    self.subtitleLabel.textColor = [UIColor dw_secondaryTextColor];
}

- (void)activateTextField {
    [self.textField becomeFirstResponder];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    self.textField.layer.borderColor = [UIColor dw_separatorLineColor].CGColor;
}

- (void)okButtonAction {
    [self.delegate avatarExternalSourceViewOKAction:self];
}

- (void)cancelButtonAction {
    [self.delegate avatarExternalSourceViewCancelAction:self];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    [self showSubtitle]; // reset error
    return YES;
}

@end
