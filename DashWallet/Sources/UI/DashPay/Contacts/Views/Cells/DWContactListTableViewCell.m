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

#import "DWContactListTableViewCell.h"

#import <DashSync/DSTransaction.h>

#import "DWActionButton.h"
#import "DWDPAvatarView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactListTableViewCell ()

@property (strong, nonatomic) IBOutlet DWDPAvatarView *avatarView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *subtitleLabel;
@property (strong, nonatomic) IBOutlet UIView *rightActionView;
@property (nullable, nonatomic, weak) UIView *actionView;

@end

@implementation DWContactListTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.avatarView.small = YES;
    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    self.subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)setContact:(nullable id<DWContactItem>)contact {
    _contact = contact;

    [self.actionView removeFromSuperview];

    self.avatarView.username = contact.username;
    self.titleLabel.text = contact.username;

    UIView *actionView = nil;
    switch (contact.displayType) {
        case DWContactItemDisplayType_Search: {
            self.subtitleLabel.text = nil;

            break;
        }
        case DWContactItemDisplayType_Contact: {
            self.subtitleLabel.text = contact.tagline;

            break;
        }
        case DWContactItemDisplayType_IncomingRequest: {
            self.subtitleLabel.text = contact.dateString;

            // TODO: this is less performant, refactor into separate cell class
            actionView = [self createContactRequestActionsView];
            [self.rightActionView addSubview:actionView];
            self.actionView = actionView;

            break;
        }
        case DWContactItemDisplayType_OutgoingRequest: {
            self.subtitleLabel.text = contact.dateString;

            // TODO: this is less performant, refactor into separate cell class
            actionView = [self createContactRequestStatusView];
            [self.rightActionView addSubview:actionView];
            self.actionView = actionView;

            break;
        }
    }
    self.subtitleLabel.hidden = (self.subtitleLabel.text.length == 0);

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
    [self.delegate contactListTableViewCell:self didAcceptContact:self.contact];
}

- (void)declineButtonAction {
    [self.delegate contactListTableViewCell:self didDeclineContact:self.contact];
}

#pragma mark - Private

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

NS_ASSUME_NONNULL_END
