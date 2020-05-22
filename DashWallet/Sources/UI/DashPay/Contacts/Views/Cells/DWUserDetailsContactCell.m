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

#import "DWUserDetailsContactCell.h"

#import "DWDPAvatarView.h"
#import "DWUIKit.h"
#import "NSAttributedString+DWHighlightText.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const AVATAR_SIZE = 36.0;

@interface DWUserDetailsContactCell ()

@property (readonly, nonatomic, strong) DWDPAvatarView *avatarView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *subtitleLabel;

@property (nullable, nonatomic, strong) id<DWUserDetails> userDetails;
@property (nullable, nonatomic, copy) NSString *highlightedText;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserDetailsContactCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        self.contentView.backgroundColor = self.backgroundColor;

        DWDPAvatarView *avatarView = [[DWDPAvatarView alloc] initWithFrame:CGRectZero];
        avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        avatarView.small = YES;
        avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
        [self.contentView addSubview:avatarView];
        _avatarView = avatarView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = self.backgroundColor;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.numberOfLines = 0;
        [self.contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.backgroundColor = self.backgroundColor;
        subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];
        subtitleLabel.adjustsFontForContentSizeCategory = YES;
        subtitleLabel.textColor = [UIColor dw_tertiaryTextColor];
        subtitleLabel.numberOfLines = 0;
        [self.contentView addSubview:subtitleLabel];
        _subtitleLabel = subtitleLabel;

        [titleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [subtitleLabel setContentHuggingPriority:UILayoutPriorityRequired - 1 forAxis:UILayoutConstraintAxisVertical];

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
        const CGFloat padding = 16.0 + 5.0;
        const CGFloat spacing = 10.0;
        const CGFloat avatarPadding = 15.0;
        const CGFloat rightPadding = 16.0;

        [NSLayoutConstraint activateConstraints:@[
            [avatarView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor
                                                     constant:avatarPadding],
            [avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [avatarView.widthAnchor constraintEqualToConstant:AVATAR_SIZE],
            [avatarView.heightAnchor constraintEqualToConstant:AVATAR_SIZE],

            [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                 constant:padding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor
                                                     constant:spacing],
            [guide.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                 constant:rightPadding],

            [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor
                                                        constant:spacing],
            [guide.trailingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor
                                                 constant:rightPadding],
            [self.contentView.bottomAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor
                                                          constant:padding],
        ]];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(contentSizeCategoryDidChangeNotification)
                                   name:UIContentSizeCategoryDidChangeNotification
                                 object:nil];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

- (void)setUserDetails:(id<DWUserDetails>)userDetails highlightedText:(nullable NSString *)highlightedText {
    self.userDetails = userDetails;
    self.highlightedText = highlightedText;

    NSAssert(userDetails.displayingType == DWUserDetailsDisplayingType_Contact,
             @"Displaying type other than contact is not supported");

    self.avatarView.username = userDetails.username;

    [self reloadAttributedData];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    UIColor *highlightedTextColor = [UIColor dw_darkBlueColor];
    NSAttributedString *usernameAttributedString = [NSAttributedString
              attributedText:self.userDetails.username
                        font:[UIFont dw_fontForTextStyle:UIFontTextStyleCaption1]
                   textColor:[UIColor dw_darkTitleColor]
             highlightedText:self.highlightedText
        highlightedTextColor:highlightedTextColor];
    if (self.userDetails.displayName.length > 0) {
        self.titleLabel.attributedText = [NSAttributedString
                  attributedText:self.userDetails.displayName
                            font:[UIFont dw_fontForTextStyle:UIFontTextStyleCaption2]
                       textColor:[UIColor dw_tertiaryTextColor]
                 highlightedText:self.highlightedText
            highlightedTextColor:highlightedTextColor];
        self.subtitleLabel.attributedText = usernameAttributedString;
    }
    else {
        self.titleLabel.attributedText = usernameAttributedString;
        self.subtitleLabel.attributedText = nil;
    }
}

@end
