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

#import "DWInvitationSuggestionView.h"

#import "DWActionButton.h"
#import "DWUIKit.h"

@implementation DWInvitationSuggestionView

@synthesize inviteButton = _inviteButton;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *orLabel = [[UILabel alloc] init];
        orLabel.translatesAutoresizingMaskIntoConstraints = NO;
        orLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
        orLabel.textColor = [UIColor dw_tertiaryTextColor];
        orLabel.textAlignment = NSTextAlignmentCenter;
        orLabel.text = NSLocalizedString(@"or", nil);
        orLabel.adjustsFontForContentSizeCategory = YES;

        UIImageView *inviteImageView = [[UIImageView alloc] init];
        inviteImageView.translatesAutoresizingMaskIntoConstraints = NO;
        inviteImageView.image = [UIImage imageNamed:@"menu_invite"];
        inviteImageView.contentMode = UIViewContentModeCenter;

        DWActionButton *inviteButton = [[DWActionButton alloc] init];
        inviteButton.translatesAutoresizingMaskIntoConstraints = NO;
        inviteButton.inverted = YES;
        [inviteButton setTitle:NSLocalizedString(@"Invite Someone to join the Dash Network", nil) forState:UIControlStateNormal];

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
            orLabel, inviteImageView, inviteButton
        ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.spacing = 4;
        [self addSubview:stackView];

        [NSLayoutConstraint activateConstraints:@[
            [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor],

            [inviteButton.heightAnchor constraintEqualToConstant:44],
        ]];

        _inviteButton = inviteButton;
    }
    return self;
}

@end
