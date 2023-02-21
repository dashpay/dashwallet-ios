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

#import "DWUserProfileSendRequestCell.h"

#import "DWActionButton.h"
#import "DWShadowView.h"
#import "DWUIKit.h"
#import "DWUserProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileSendRequestCell ()

@property (readonly, nonatomic, strong) UILabel *textLabel;
@property (readonly, nonatomic, strong) DWActionButton *sendRequestButton;
@property (readonly, nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;

@property (nullable, nonatomic, strong) NSLayoutConstraint *contentWidthConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileSendRequestCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        self.contentView.backgroundColor = self.backgroundColor;

        DWShadowView *shadowView = [[DWShadowView alloc] initWithFrame:CGRectZero];
        shadowView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:shadowView];

        UIView *roundedContentView = [[UIView alloc] initWithFrame:CGRectZero];
        roundedContentView.translatesAutoresizingMaskIntoConstraints = NO;
        roundedContentView.backgroundColor = [UIColor dw_backgroundColor];
        roundedContentView.layer.cornerRadius = 8.0;
        roundedContentView.layer.masksToBounds = YES;
        [shadowView addSubview:roundedContentView];

        UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"dp_friendship"]];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *textLabel = [[UILabel alloc] init];
        textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        textLabel.numberOfLines = 0;
        textLabel.textColor = [UIColor dw_darkTitleColor];
        textLabel.textAlignment = NSTextAlignmentCenter;
        _textLabel = textLabel;

        DWActionButton *sendRequestButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        sendRequestButton.translatesAutoresizingMaskIntoConstraints = NO;
        [sendRequestButton setImage:[UIImage imageNamed:@"dp_send_request"] forState:UIControlStateNormal];
        [sendRequestButton setTitle:NSLocalizedString(@"Send Contact Request", nil) forState:UIControlStateNormal];
        sendRequestButton.inverted = YES;
        [sendRequestButton addTarget:self
                              action:@selector(sendRequestButtonAction:)
                    forControlEvents:UIControlEventTouchUpInside];
        _sendRequestButton = sendRequestButton;

        // fire up activity indicator in advance to fix reuse issue
        UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
        activityIndicatorView.color = [UIColor dw_dashBlueColor];
        [activityIndicatorView startAnimating];
        activityIndicatorView.hidesWhenStopped = NO;
        _activityIndicatorView = activityIndicatorView;

        UIView *separatorView = [[UIView alloc] init];
        separatorView.translatesAutoresizingMaskIntoConstraints = NO;
        separatorView.backgroundColor = [UIColor dw_separatorLineColor];
        [self.contentView addSubview:separatorView];

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ imageView, textLabel, sendRequestButton, activityIndicatorView ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.spacing = 20.0;
        stackView.alignment = UIStackViewAlignmentCenter;
        [self.contentView addSubview:stackView];

        const CGFloat verticalPadding = 5.0;
        const CGFloat itemVerticalPadding = 18.0;
        const CGFloat itemHorizontalPadding = verticalPadding + 10.0;
        const CGFloat separatorTopPadding = itemVerticalPadding * 2;
        const CGFloat stackBottomPadding = itemVerticalPadding + separatorTopPadding;

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [shadowView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                 constant:verticalPadding],
            [shadowView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:shadowView.trailingAnchor],

            [separatorView.topAnchor constraintEqualToAnchor:shadowView.bottomAnchor
                                                    constant:separatorTopPadding],
            [separatorView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:separatorView.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:separatorView.bottomAnchor
                                                          constant:verticalPadding],
            [separatorView.heightAnchor constraintEqualToConstant:1.0],

            [roundedContentView.topAnchor constraintEqualToAnchor:shadowView.topAnchor],
            [roundedContentView.leadingAnchor constraintEqualToAnchor:shadowView.leadingAnchor],
            [shadowView.trailingAnchor constraintEqualToAnchor:roundedContentView.trailingAnchor],
            [shadowView.bottomAnchor constraintEqualToAnchor:roundedContentView.bottomAnchor],

            [stackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                constant:itemVerticalPadding],
            [stackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor
                                                    constant:itemHorizontalPadding],
            [guide.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor
                                                 constant:itemHorizontalPadding],
            [self.contentView.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor
                                                          constant:stackBottomPadding],
            (_contentWidthConstraint = [self.contentView.widthAnchor constraintEqualToConstant:200]),

            [imageView.heightAnchor constraintEqualToConstant:60.0],
            [sendRequestButton.heightAnchor constraintEqualToConstant:40.0],
        ]];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(contentSizeCategoryDidChangeNotification)
                                   name:UIContentSizeCategoryDidChangeNotification
                                 object:nil];
    }
    return self;
}

- (CGFloat)contentWidth {
    return self.contentWidthConstraint.constant;
}

- (void)setContentWidth:(CGFloat)contentWidth {
    self.contentWidthConstraint.constant = contentWidth;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

- (void)prepareForReuse {
    [super prepareForReuse];

    [self.activityIndicatorView startAnimating];
}

- (void)setModel:(DWUserProfileModel *)model {
    _model = model;

    [self reloadAttributedData];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    [self updateState:self.model.requestState];
}

- (void)sendRequestButtonAction:(UIButton *)sender {
    [self.delegate userProfileSendRequestCell:self sendRequestButtonAction:sender];
}

// request state is used
- (void)updateState:(DWUserProfileModelState)state {
    [self updateActions];

    switch (state) {
        case DWUserProfileModelState_None:
            self.activityIndicatorView.hidden = YES;

            break;
        case DWUserProfileModelState_Error:
            self.activityIndicatorView.hidden = YES;

            break;
        case DWUserProfileModelState_Loading:
            self.sendRequestButton.hidden = YES;
            self.activityIndicatorView.hidden = NO;

            break;
        case DWUserProfileModelState_Done:
            self.activityIndicatorView.hidden = YES;

            break;
    }
}

- (void)updateActions {
    const DSBlockchainIdentityFriendshipStatus friendshipStatus = self.model.friendshipStatus;
    switch (friendshipStatus) {
        case DSBlockchainIdentityFriendshipStatus_Unknown:
            self.sendRequestButton.hidden = YES;
            self.textLabel.hidden = YES;
            self.textLabel.attributedText = nil;

            break;
        case DSBlockchainIdentityFriendshipStatus_None: // not a friend nor incoming request
            self.sendRequestButton.hidden = NO;
            self.textLabel.hidden = NO;
            self.textLabel.attributedText = [self notAContactText];

            break;
        case DSBlockchainIdentityFriendshipStatus_Outgoing: // request was sent, pending
            self.sendRequestButton.hidden = YES;
            self.textLabel.hidden = NO;
            self.textLabel.attributedText = [self pendingContactText];

            break;
        case DSBlockchainIdentityFriendshipStatus_Incoming:
        case DSBlockchainIdentityFriendshipStatus_Friends:
            self.sendRequestButton.hidden = YES;
            self.textLabel.hidden = YES;
            self.textLabel.attributedText = nil;

            // cell should be not visible

            break;
    }
}

- (NSAttributedString *)notAContactText {
    if (self.model.username == nil) {
        return nil;
    }

    NSString *full =
        [NSString stringWithFormat:
                      NSLocalizedString(@"Add %@ as your contact to Pay Directly to Username and Retain Mutual Transaction History",
                                        @"Add <username> as your contact..."),
                      self.model.username];

    NSString *emphasized1 =
        NSLocalizedString(@"Pay Directly to Username",
                          @"emphasized text in: Add <username> as your contact to Pay Directly to Username and Retain Mutual Transaction History");
    NSString *emphasized2 =
        NSLocalizedString(@"Retain Mutual Transaction History",
                          @"emphasized text in: Add <username> as your contact to Pay Directly to Username and Retain Mutual Transaction History");

    NSRange range1 = [full rangeOfString:emphasized1];
    NSRange range2 = [full rangeOfString:emphasized2];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:full];

    [result beginEditing];

    [result setAttributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleBody]}
                    range:NSMakeRange(0, full.length)];

    if (range1.location != NSNotFound) {
        [result removeAttribute:NSFontAttributeName range:range1];

        [result setAttributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline]}
                        range:range1];
    }

    if (range2.location != NSNotFound) {
        [result removeAttribute:NSFontAttributeName range:range2];

        [result setAttributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline]}
                        range:range2];
    }

    [result endEditing];

    return [result copy];
}

- (NSAttributedString *)pendingContactText {
    if (self.model.username == nil) {
        return nil;
    }

    NSString *full =
        [NSString stringWithFormat:
                      NSLocalizedString(@"Once %@ accepts your request you can Pay Directly to Username",
                                        @"Once <username> accepts your request..."),
                      self.model.username];

    NSString *emphasized1 =
        NSLocalizedString(@"Pay Directly to Username",
                          @"emphasized text in: Add <username> as your contact to Pay Directly to Username and Retain Mutual Transaction History");

    NSRange range1 = [full rangeOfString:emphasized1];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:full];

    [result beginEditing];

    [result setAttributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleBody]}
                    range:NSMakeRange(0, full.length)];

    if (range1.location != NSNotFound) {
        [result removeAttribute:NSFontAttributeName range:range1];

        [result setAttributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline]}
                        range:range1];
    }

    [result endEditing];

    return [result copy];
}

@end
