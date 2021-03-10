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

#import "DWInvitationMessageView.h"

#import "DSBlockchainIdentity+DWDisplayName.h"
#import "DWEnvironment.h"
#import "DWSuccessInvitationView.h"
#import "DWUIKit.h"

@implementation DWInvitationMessageView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        DWSuccessInvitationView *iconView = [[DWSuccessInvitationView alloc] initWithFrame:CGRectZero];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:iconView];

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.textColor = [UIColor dw_dashBlueColor];
        title.text = NSLocalizedString(@"Join Now", nil);
        title.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
        title.textAlignment = NSTextAlignmentCenter;
        title.numberOfLines = 0;
        [self addSubview:title];

        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.textColor = [UIColor dw_darkTitleColor];
        subtitle.textAlignment = NSTextAlignmentCenter;
        subtitle.numberOfLines = 0;
        [self addSubview:subtitle];

        [NSLayoutConstraint activateConstraints:@[
            [iconView.topAnchor constraintEqualToAnchor:self.topAnchor
                                               constant:32.0],
            [iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [title.topAnchor constraintEqualToAnchor:iconView.bottomAnchor
                                            constant:28],
            [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                constant:16],
            [self.trailingAnchor constraintEqualToAnchor:title.trailingAnchor
                                                constant:16],

            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                               constant:16],
            [subtitle.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                   constant:16],
            [self.trailingAnchor constraintEqualToAnchor:subtitle.trailingAnchor
                                                constant:16],

            [self.bottomAnchor constraintEqualToAnchor:subtitle.bottomAnchor
                                              constant:32.0],
        ]];

        // Setup
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
        iconView.blockchainIdentity = myBlockchainIdentity;

        NSMutableAttributedString *desc = [[NSMutableAttributedString alloc] init];
        [desc beginEditing];

        NSString *name = [myBlockchainIdentity dw_displayNameOrUsername];
        NSString *text = [NSString stringWithFormat:NSLocalizedString(@"You have been invited by %@. Start using Dash cryptocurrency.", nil), name];

        [desc appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleBody]}]];
        NSRange range = [text rangeOfString:name];
        if (range.location != NSNotFound) {
            [desc setAttributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline]} range:range];
        }

        [desc endEditing];
        subtitle.attributedText = desc;
    }
    return self;
}

@end
