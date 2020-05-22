//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWUserDetailsCell.h"

#import <DashSync/DSTransaction.h>

#import "DWActionButton.h"
#import "DWDPAvatarView.h"
#import "DWUIKit.h"
#import "NSAttributedString+DWHighlightText.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserDetailsCell ()

@property (strong, nonatomic) IBOutlet DWDPAvatarView *avatarView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *subtitleLabel;
@property (strong, nonatomic) IBOutlet UIView *rightActionView;
@property (nullable, nonatomic, weak) UIView *actionView;

@property (nullable, nonatomic, strong) id<DWUserDetails> userDetails;
@property (nullable, nonatomic, copy) NSString *highlightedText;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserDetailsCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.avatarView.small = YES;
    self.avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    self.subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(contentSizeCategoryDidChangeNotification)
                               name:UIContentSizeCategoryDidChangeNotification
                             object:nil];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

- (void)setUserDetails:(id<DWUserDetails>)userDetails highlightedText:(nullable NSString *)highlightedText {
    self.userDetails = userDetails;
    self.highlightedText = highlightedText;

    self.avatarView.username = userDetails.username;
    [self reloadAttributedData];

    [self.actionView removeFromSuperview];
    UIView *actionView = nil;
    switch (userDetails.displayingType) {
        case DWUserDetailsDisplayingType_FromSearch: {
            break;
        }
        case DWUserDetailsDisplayingType_Contact: {
            NSAssert(NO, @"DWUserDetailsDisplayingType_Contact is not supported");

            break;
        }
        case DWUserDetailsDisplayingType_IncomingRequest: {
            actionView = [self createContactRequestActionsView];
            [self.rightActionView addSubview:actionView];
            self.actionView = actionView;

            break;
        }
        case DWUserDetailsDisplayingType_OutgoingRequest: {
            actionView = [self createContactRequestStatusView];
            [self.rightActionView addSubview:actionView];
            self.actionView = actionView;

            break;
        }
    }

    if (actionView) {
        [NSLayoutConstraint activateConstraints:@[
            [actionView.topAnchor constraintEqualToAnchor:self.rightActionView.topAnchor],
            [actionView.bottomAnchor constraintEqualToAnchor:self.rightActionView.bottomAnchor],
            [actionView.trailingAnchor constraintEqualToAnchor:self.rightActionView.trailingAnchor],
            [actionView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.rightActionView.leadingAnchor],
        ]];
    }
}

#pragma mark - Actions

- (void)acceptButtonAction {
    [self.delegate userDetailsCell:self didAcceptContact:self.userDetails];
}

- (void)declineButtonAction {
    [self.delegate userDetailsCell:self didDeclineContact:self.userDetails];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    UIColor *highlightedTextColor = [UIColor dw_darkBlueColor];
    self.titleLabel.attributedText = [NSAttributedString
              attributedText:self.userDetails.username
                        font:[UIFont dw_fontForTextStyle:UIFontTextStyleCaption1]
                   textColor:[UIColor dw_darkTitleColor]
             highlightedText:self.highlightedText
        highlightedTextColor:highlightedTextColor];
    if (self.userDetails.displayName.length > 0) {
        self.subtitleLabel.hidden = NO;
        self.subtitleLabel.attributedText = [NSAttributedString
                  attributedText:self.userDetails.displayName
                            font:[UIFont dw_fontForTextStyle:UIFontTextStyleCaption2]
                       textColor:[UIColor dw_tertiaryTextColor]
                 highlightedText:self.highlightedText
            highlightedTextColor:highlightedTextColor];
    }
    else {
        self.subtitleLabel.hidden = YES;
        self.subtitleLabel.attributedText = nil;
    }
}

- (UIView *)createContactRequestActionsView {
    DWActionButton *acceptButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
    acceptButton.translatesAutoresizingMaskIntoConstraints = NO;
    acceptButton.small = YES;
    [acceptButton setTitle:NSLocalizedString(@"Accept", nil) forState:UIControlStateNormal];
    [acceptButton addTarget:self
                     action:@selector(acceptButtonAction)
           forControlEvents:UIControlEventTouchUpInside];

    // TODO: refactor into DWGrayActionButton or generalize DWBlueActionButton
    UIButton *declineButton = [UIButton buttonWithType:UIButtonTypeCustom];
    declineButton.translatesAutoresizingMaskIntoConstraints = NO;
    declineButton.backgroundColor = [UIColor dw_declineButtonColor];
    declineButton.layer.cornerRadius = 8.0;
    [declineButton setImage:[UIImage imageNamed:@"icon_decline"] forState:UIControlStateNormal];
    [declineButton addTarget:self
                      action:@selector(declineButtonAction)
            forControlEvents:UIControlEventTouchUpInside];


    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ acceptButton, declineButton ]];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.spacing = 10.0;
    stackView.alignment = UIStackViewAlignmentCenter;

    [NSLayoutConstraint activateConstraints:@[
        [acceptButton.heightAnchor constraintEqualToConstant:30.0],
        [declineButton.heightAnchor constraintEqualToConstant:30.0],
        [declineButton.widthAnchor constraintEqualToConstant:30.0],
    ]];

    return stackView;
}

- (UILabel *)createContactRequestStatusView {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = [UIColor dw_tertiaryTextColor];
    label.textAlignment = NSTextAlignmentRight;
    // TODO: get from contact model
    label.text = @"Pending";
    return label;
}

@end
