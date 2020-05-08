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

#import "DWActionButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const BUTTON_HEIGHT = 38.0;

@interface DWUserProfileContactActionsCell ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;

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

        DWActionButton *mainButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        mainButton.translatesAutoresizingMaskIntoConstraints = NO;
        mainButton.accentColor = [UIColor dw_greenColor];
        mainButton.small = YES;
        _mainButton = mainButton;

        DWActionButton *secondaryButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        secondaryButton.translatesAutoresizingMaskIntoConstraints = NO;
        secondaryButton.accentColor = [UIColor dw_quaternaryTextColor];
        secondaryButton.small = YES;
        _secondaryButton = secondaryButton;

        UIStackView *actionsStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ mainButton, secondaryButton ]];
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

        [titleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:16.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

            [stackView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                constant:12.0],
            [stackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],

            [mainButton.heightAnchor constraintEqualToConstant:BUTTON_HEIGHT],
            [secondaryButton.heightAnchor constraintEqualToConstant:BUTTON_HEIGHT],

            [separatorView.topAnchor constraintEqualToAnchor:stackView.bottomAnchor
                                                    constant:20.0],
            [separatorView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:separatorView.trailingAnchor],
            [separatorView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
            [separatorView.heightAnchor constraintEqualToConstant:1.0],
        ]];
    }
    return self;
}

- (void)configureForIncomingStatus {
    NSParameterAssert(self.username);

    NSMutableAttributedString *mutableTitle = [[NSMutableAttributedString alloc] init];

    NSAttributedString *username = [[NSAttributedString alloc] initWithString:self.username
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
    self.mainButton.hidden = NO;
    self.secondaryButton.hidden = NO;
    [self.mainButton setTitle:NSLocalizedString(@"Accept", nil) forState:UIControlStateNormal];
    [self.secondaryButton setTitle:NSLocalizedString(@"Ignore", nil) forState:UIControlStateNormal];
}

@end
