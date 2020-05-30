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

    const CGFloat buttonHeight = 30.0;
    const CGFloat spacing = 10.0;

    [NSLayoutConstraint activateConstraints:@[
        [acceptButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.accessoryView.topAnchor],
        [acceptButton.leadingAnchor constraintEqualToAnchor:self.accessoryView.leadingAnchor],
        [self.accessoryView.bottomAnchor constraintGreaterThanOrEqualToAnchor:acceptButton.bottomAnchor],
        [acceptButton.centerYAnchor constraintEqualToAnchor:self.accessoryView.centerYAnchor],
        [acceptButton.heightAnchor constraintEqualToConstant:buttonHeight],

        [declineButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.accessoryView.topAnchor],
        [declineButton.leadingAnchor constraintEqualToAnchor:acceptButton.trailingAnchor
                                                    constant:spacing],
        [self.accessoryView.trailingAnchor constraintEqualToAnchor:declineButton.trailingAnchor],
        [self.accessoryView.bottomAnchor constraintGreaterThanOrEqualToAnchor:declineButton.bottomAnchor],
        [declineButton.centerYAnchor constraintEqualToAnchor:self.accessoryView.centerYAnchor],
        [declineButton.heightAnchor constraintEqualToConstant:buttonHeight],
        [declineButton.widthAnchor constraintEqualToConstant:buttonHeight],
    ]];
}

@end
