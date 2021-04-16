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

#import "DWInvitationTableViewCell.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWInvitationTableViewCell ()

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *subtitleLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWInvitationTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        self.contentView.backgroundColor = self.backgroundColor;

        UIImageView *icon = [[UIImageView alloc] init];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.userInteractionEnabled = NO;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:icon];
        _iconImageView = icon;

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.textColor = [UIColor dw_darkTitleColor];
        title.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        title.numberOfLines = 0;
        title.adjustsFontForContentSizeCategory = YES;
        title.userInteractionEnabled = NO;
        [self.contentView addSubview:title];
        _titleLabel = title;

        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.textColor = [UIColor dw_tertiaryTextColor];
        subtitle.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        subtitle.numberOfLines = 0;
        subtitle.adjustsFontForContentSizeCategory = YES;
        subtitle.userInteractionEnabled = NO;
        [self.contentView addSubview:subtitle];
        _subtitleLabel = subtitle;

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_disclosure_indicator"]];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:chevron];

        [title setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [subtitle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        CGFloat const padding = 20;
        UIEdgeInsets const insets = UIEdgeInsetsMake(padding, padding, padding, padding);
        [NSLayoutConstraint dw_activate:@[
            [icon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                               constant:16 + padding],
            [icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [icon pinSize:CGSizeMake(37, 37)],

            [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor
                                                constant:padding],
            [title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                            constant:padding],

            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor],
            [subtitle.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor
                                                   constant:padding],
            [self.contentView.bottomAnchor constraintEqualToAnchor:subtitle.bottomAnchor
                                                          constant:padding],

            [chevron.leadingAnchor constraintEqualToAnchor:title.trailingAnchor
                                                  constant:padding],
            [chevron.leadingAnchor constraintEqualToAnchor:subtitle.trailingAnchor
                                                  constant:padding],
            [self.contentView.trailingAnchor constraintEqualToAnchor:chevron.trailingAnchor
                                                            constant:padding],
            [chevron pinSize:CGSizeMake(10, 19)],
            [chevron.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self.contentView dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)setItem:(id<DWInvitationItem>)item {
    _item = item;

    UIImage *icon = [UIImage imageNamed:item.isRegistered ? @"icon_invitation_read" : @"icon_invitation_unread"];
    self.iconImageView.image = icon;
    self.titleLabel.text = item.title;
    self.subtitleLabel.text = item.subtitle;
}

@end
