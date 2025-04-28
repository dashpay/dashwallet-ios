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

#import "DWUserProfileContactActionsCell.h"

#import "DWUIKit.h"
#import "DWUserProfileModel.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const BUTTON_HEIGHT = 38.0;

@interface DWUserProfileContactActionsCell ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UIButton *mainButton;
@property (readonly, nonatomic, strong) UIButton *secondaryButton;
@property (readonly, nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;

@property (nullable, nonatomic, strong) NSLayoutConstraint *contentWidthConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileContactActionsCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = self.backgroundColor;
        [self.contentView addSubview:contentView];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = self.backgroundColor;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.numberOfLines = 0;
        [contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        DWActionButton *mainButton = [[DWActionButton alloc] init];
        mainButton.translatesAutoresizingMaskIntoConstraints = NO;
        mainButton.tintColor = [UIColor dw_greenColor];
        [mainButton addTarget:self action:@selector(mainButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        _mainButton = mainButton;

        DWActionButton *secondaryButton = [[DWActionButton alloc] init];
        secondaryButton.translatesAutoresizingMaskIntoConstraints = NO;
        secondaryButton.tintColor = [UIColor dw_quaternaryTextColor];
        [mainButton addTarget:self action:@selector(secondaryButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        _secondaryButton = secondaryButton;

        UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
        activityIndicatorView.color = [UIColor dw_dashBlueColor];
        activityIndicatorView.hidesWhenStopped = NO;
        [activityIndicatorView startAnimating];
        _activityIndicatorView = activityIndicatorView;

        UIStackView *actionsStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ mainButton, secondaryButton, activityIndicatorView ]];
        actionsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        actionsStackView.axis = UILayoutConstraintAxisHorizontal;
        actionsStackView.spacing = 10.0;
        actionsStackView.alignment = UIStackViewAlignmentCenter;

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ actionsStackView ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.alignment = UIStackViewAlignmentCenter;
        [contentView addSubview:stackView];

        UIView *separatorView = [[UIView alloc] init];
        separatorView.translatesAutoresizingMaskIntoConstraints = NO;
        separatorView.backgroundColor = [UIColor dw_separatorLineColor];
        [contentView addSubview:separatorView];

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;

        [titleLabel setContentHuggingPriority:UILayoutPriorityRequired - 1
                                      forAxis:UILayoutConstraintAxisVertical];
        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 2
                                                    forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:16.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

            [stackView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                constant:12.0],
            [stackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],

            [actionsStackView.heightAnchor constraintEqualToConstant:BUTTON_HEIGHT],
            [mainButton.heightAnchor constraintEqualToConstant:BUTTON_HEIGHT],
            [secondaryButton.heightAnchor constraintEqualToConstant:BUTTON_HEIGHT],

            [separatorView.topAnchor constraintEqualToAnchor:stackView.bottomAnchor
                                                    constant:20.0],
            [separatorView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:separatorView.trailingAnchor],
            [separatorView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
            [separatorView.heightAnchor constraintEqualToConstant:1.0],

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
    [self invalidateIntrinsicContentSize];
}

- (void)setModel:(DWUserProfileModel *)model {
    _model = model;

    [self configureForIncomingStatus];

    [self updateState:self.model.acceptRequestState];

    [self invalidateIntrinsicContentSize];
}

- (void)prepareForReuse {
    [super prepareForReuse];

    [self.activityIndicatorView startAnimating];
}

#pragma mark - Private

- (void)configureForIncomingStatus {
    NSMutableAttributedString *mutableTitle = [[NSMutableAttributedString alloc] init];

    NSAttributedString *username = [[NSAttributedString alloc] initWithString:self.model.username ? self.model.username : @"<Fetching Contact>"
                                                                   attributes:@{
                                                                       NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline],
                                                                   }];
    NSAttributedString *description = [[NSAttributedString alloc]
        initWithString:NSLocalizedString(@"has requested to be your friend", @"Username has requested to be your friend")
            attributes:@{
                NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleBody],
            }];

    [mutableTitle beginEditing];
    [mutableTitle appendAttributedString:username];
    [mutableTitle appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    [mutableTitle appendAttributedString:description];
    [mutableTitle endEditing];

    self.titleLabel.attributedText = mutableTitle;
    [self.mainButton setTitle:NSLocalizedString(@"Accept", nil) forState:UIControlStateNormal];
    [self.secondaryButton setTitle:NSLocalizedString(@"Ignore", nil) forState:UIControlStateNormal];
}

- (void)mainButtonAction:(UIButton *)sender {
    [self.delegate userProfileContactActionsCell:self mainButtonAction:sender];
}

- (void)secondaryButtonAction:(UIButton *)sender {
    [self.delegate userProfileContactActionsCell:self secondaryButtonAction:sender];
}

// request state is used
- (void)updateState:(DWUserProfileModelState)state {
    switch (state) {
        case DWUserProfileModelState_None:
        case DWUserProfileModelState_Error:
            self.mainButton.hidden = NO;
            self.secondaryButton.hidden = NO;
            self.activityIndicatorView.hidden = YES;

            break;
        case DWUserProfileModelState_Loading:
            self.mainButton.hidden = YES;
            self.secondaryButton.hidden = YES;
            self.activityIndicatorView.hidden = NO;

            break;
        case DWUserProfileModelState_Done:
            self.mainButton.hidden = YES;
            self.secondaryButton.hidden = YES;
            self.activityIndicatorView.hidden = YES;

            break;
    }
}

@end
