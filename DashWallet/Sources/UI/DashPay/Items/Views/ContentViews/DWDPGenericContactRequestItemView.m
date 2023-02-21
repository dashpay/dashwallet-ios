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

#import "DWDPGenericContactRequestItemView.h"

#import "DWActionButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPGenericContactRequestItemView ()

@property (readonly, nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;
@property (readonly, nonatomic, strong) UIImageView *statusImageView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPGenericContactRequestItemView

@synthesize acceptButton = _acceptButton;
@synthesize declineButton = _declineButton;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup_contactRequestItemView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup_contactRequestItemView];
    }
    return self;
}

- (void)setup_contactRequestItemView {
    DWActionButton *acceptButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
    acceptButton.translatesAutoresizingMaskIntoConstraints = NO;
    acceptButton.small = YES;
    [acceptButton setTitle:NSLocalizedString(@"Accept", nil) forState:UIControlStateNormal];
    [self.accessoryView addSubview:acceptButton];
    _acceptButton = acceptButton;

    DWActionButton *declineButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
    declineButton.translatesAutoresizingMaskIntoConstraints = NO;
    declineButton.accentColor = [UIColor dw_declineButtonColor];
    [declineButton setImage:[UIImage imageNamed:@"icon_decline"] forState:UIControlStateNormal];
    [self.accessoryView addSubview:declineButton];
    _declineButton = declineButton;

    UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    activityIndicatorView.color = [UIColor dw_tertiaryTextColor];
    [self.accessoryView addSubview:activityIndicatorView];
    _activityIndicatorView = activityIndicatorView;

    UIImageView *statusImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    statusImageView.translatesAutoresizingMaskIntoConstraints = NO;
    statusImageView.contentMode = UIViewContentModeCenter;
    statusImageView.image = [UIImage imageNamed:@"dp_established_contact"];
    [self.accessoryView addSubview:statusImageView];
    _statusImageView = statusImageView;

    const CGFloat buttonHeight = 30.0;
    const CGFloat spacing = 10.0;

    [statusImageView setContentCompressionResistancePriority:UILayoutPriorityRequired - 10 forAxis:UILayoutConstraintAxisHorizontal];
    [statusImageView setContentCompressionResistancePriority:UILayoutPriorityRequired - 10 forAxis:UILayoutConstraintAxisVertical];

    NSLayoutConstraint *acceptTopConstraint = [acceptButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.accessoryView.topAnchor];
    acceptTopConstraint.priority = UILayoutPriorityRequired - 20;
    NSLayoutConstraint *acceptBottomConstraint = [self.accessoryView.bottomAnchor constraintGreaterThanOrEqualToAnchor:acceptButton.bottomAnchor];
    acceptBottomConstraint.priority = UILayoutPriorityRequired - 19;
    NSLayoutConstraint *declineTopConstraint = [declineButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.accessoryView.topAnchor];
    declineTopConstraint.priority = UILayoutPriorityRequired - 18;
    NSLayoutConstraint *declineBottomConstraint = [self.accessoryView.bottomAnchor constraintGreaterThanOrEqualToAnchor:declineButton.bottomAnchor];
    declineBottomConstraint.priority = UILayoutPriorityRequired - 17;

    [NSLayoutConstraint activateConstraints:@[
        acceptTopConstraint,
        [acceptButton.leadingAnchor constraintEqualToAnchor:self.accessoryView.leadingAnchor],
        acceptBottomConstraint,
        [acceptButton.centerYAnchor constraintEqualToAnchor:self.accessoryView.centerYAnchor],
        [acceptButton.heightAnchor constraintEqualToConstant:buttonHeight],

        declineTopConstraint,
        [declineButton.leadingAnchor constraintEqualToAnchor:acceptButton.trailingAnchor
                                                    constant:spacing],
        [self.accessoryView.trailingAnchor constraintEqualToAnchor:declineButton.trailingAnchor],
        declineBottomConstraint,
        [declineButton.centerYAnchor constraintEqualToAnchor:self.accessoryView.centerYAnchor],
        [declineButton.heightAnchor constraintEqualToConstant:buttonHeight],
        [declineButton.widthAnchor constraintEqualToConstant:buttonHeight],

        [self.accessoryView.trailingAnchor constraintEqualToAnchor:activityIndicatorView.trailingAnchor],
        [activityIndicatorView.centerYAnchor constraintEqualToAnchor:self.accessoryView.centerYAnchor],

        [statusImageView.topAnchor constraintEqualToAnchor:self.accessoryView.topAnchor],
        [self.accessoryView.trailingAnchor constraintEqualToAnchor:statusImageView.trailingAnchor],
        [self.accessoryView.bottomAnchor constraintEqualToAnchor:statusImageView.bottomAnchor],
    ]];
}

- (void)setRequestState:(DWDPNewIncomingRequestItemState)requestState {
    _requestState = requestState;

    switch (requestState) {
        case DWDPNewIncomingRequestItemState_Ready:
            [self setReadyState];
            break;
        case DWDPNewIncomingRequestItemState_Processing:
            [self setProcessingState];
            break;
        case DWDPNewIncomingRequestItemState_Accepted:
            [self setAcceptedState];
            break;
        case DWDPNewIncomingRequestItemState_Declined:
            [self setDeclinedState];
            break;
        case DWDPNewIncomingRequestItemState_Failed:
            [self setFailedState];
            break;
    }
}

- (void)setReadyState {
    self.acceptButton.hidden = NO;
    self.declineButton.hidden = NO;

    self.statusImageView.hidden = YES;

    [self.activityIndicatorView stopAnimating];
}

- (void)setProcessingState {
    [self.activityIndicatorView startAnimating];

    self.acceptButton.hidden = YES;
    self.declineButton.hidden = YES;

    self.statusImageView.hidden = YES;
}

- (void)setAcceptedState {
    [self.activityIndicatorView stopAnimating];

    self.acceptButton.hidden = YES;
    self.declineButton.hidden = YES;

    self.statusImageView.hidden = NO;
}

- (void)setDeclinedState {
    // TODO: DP impl
    [self setAcceptedState];
}

- (void)setFailedState {
    // TODO: DP impl
    [self setReadyState];
}

@end
