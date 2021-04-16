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

#import "DWCreateInvitationButton.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWCreateInvitationButton ()
@end

NS_ASSUME_NONNULL_END

@implementation DWCreateInvitationButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor dw_backgroundColor];
        contentView.layer.cornerRadius = 8;
        contentView.layer.masksToBounds = YES;
        contentView.userInteractionEnabled = NO;
        [self addSubview:contentView];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_create_invitation"]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.userInteractionEnabled = NO;
        [contentView addSubview:icon];

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.textColor = [UIColor dw_darkTitleColor];
        title.numberOfLines = 0;
        title.adjustsFontForContentSizeCategory = YES;
        title.userInteractionEnabled = NO;
        [contentView addSubview:title];

        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
        [text appendAttributedString:
                  [[NSAttributedString alloc] initWithString:
                                                  NSLocalizedString(@"Create a new invitation", nil)
                                                  attributes:@{
                                                      NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote],
                                                      NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
                                                  }]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [text appendAttributedString:
                  [[NSAttributedString alloc] initWithString:
                                                  NSLocalizedString(@"Invite your friends and family to join the Dash Network.", nil)
                                                  attributes:@{
                                                      NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1],
                                                      NSForegroundColorAttributeName : [UIColor dw_tertiaryTextColor],
                                                  }]];
        title.attributedText = text;

        [title setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [contentView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        CGFloat const padding = 20;
        [NSLayoutConstraint dw_activate:@[
            [contentView pinEdges:self],

            [icon.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                               constant:padding],
            [icon.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
            [icon pinSize:CGSizeMake(37, 37)],

            [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor
                                                constant:padding],
            [title.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                            constant:padding],
            [contentView.trailingAnchor constraintEqualToAnchor:title.trailingAnchor
                                                       constant:padding],
            [contentView.bottomAnchor constraintEqualToAnchor:title.bottomAnchor
                                                     constant:padding],
        ]];
    }
    return self;
}

@end
