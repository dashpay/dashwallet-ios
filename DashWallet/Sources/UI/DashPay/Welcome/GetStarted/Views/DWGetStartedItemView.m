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

#import "DWGetStartedItemView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWGetStartedItemView ()

@end

static UIImage *ItemTypeImage(DWGetStartedItemType itemType) {
    switch (itemType) {
        case DWGetStartedItemType_1:
            return [UIImage imageNamed:@"dp_get_started_1"];
        case DWGetStartedItemType_Inactive2:
            return [UIImage imageNamed:@"dp_get_started_2_dim"];
        case DWGetStartedItemType_Active2:
            return [UIImage imageNamed:@"dp_get_started_2"];
        case DWGetStartedItemType_Inactive3:
            return [UIImage imageNamed:@"dp_get_started_3_dim"];
        case DWGetStartedItemType_Active3:
            return [UIImage imageNamed:@"dp_get_started_3"];
    }
}

static NSAttributedString *StepText(DWGetStartedItemType itemType, BOOL completed) {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSUInteger step;
    switch (itemType) {
        case DWGetStartedItemType_1:
            step = 1;
            break;
        case DWGetStartedItemType_Inactive2:
        case DWGetStartedItemType_Active2:
            step = 2;
            break;
        case DWGetStartedItemType_Inactive3:
        case DWGetStartedItemType_Active3:
            step = 3;
            break;
    }
    NSString *prefix = [NSString stringWithFormat:NSLocalizedString(@"Step %ld", @"Step 1"), step];
    NSAttributedString *attPrefix = [[NSAttributedString alloc] initWithString:prefix];
    [result appendAttributedString:attPrefix];
    if (completed) {
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        attachment.image = [UIImage imageNamed:@"dp_get_started_check"];
        attachment.bounds = CGRectMake(0, -4, 16, 16);
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
        [result appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    }

    return result;
}

static NSString *NameText(DWGetStartedItemType itemType) {
    switch (itemType) {
        case DWGetStartedItemType_1:
            return NSLocalizedString(@"Choose Your Username", nil);
        case DWGetStartedItemType_Inactive2:
        case DWGetStartedItemType_Active2:
            return NSLocalizedString(@"Set Your PIN", nil);
        case DWGetStartedItemType_Inactive3:
        case DWGetStartedItemType_Active3:
            return NSLocalizedString(@"Secure Your Wallet", nil);
    }
}

static UIColor *NameColor(DWGetStartedItemType itemType) {
    switch (itemType) {
        case DWGetStartedItemType_1:
            return [UIColor dw_darkTitleColor];
        case DWGetStartedItemType_Inactive2:
            return [UIColor dw_tertiaryTextColor];
        case DWGetStartedItemType_Active2:
            return [UIColor dw_darkTitleColor];
        case DWGetStartedItemType_Inactive3:
            return [UIColor dw_tertiaryTextColor];
        case DWGetStartedItemType_Active3:
            return [UIColor dw_darkTitleColor];
    }
}

NS_ASSUME_NONNULL_END

@implementation DWGetStartedItemView

- (instancetype)initWithItemType:(DWGetStartedItemType)itemType completed:(BOOL)completed {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        UIView *rectView = [[UIView alloc] init];
        rectView.translatesAutoresizingMaskIntoConstraints = NO;
        rectView.backgroundColor = [UIColor dw_backgroundColor];
        rectView.layer.cornerRadius = 8;
        rectView.layer.masksToBounds = YES;
        [self addSubview:rectView];

        UIImageView *icon = [[UIImageView alloc] initWithImage:ItemTypeImage(itemType)];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.contentMode = UIViewContentModeCenter;
        [rectView addSubview:icon];

        UIView *container = [[UIView alloc] init];
        container.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:container];

        UILabel *stepLabel = [[UILabel alloc] init];
        stepLabel.translatesAutoresizingMaskIntoConstraints = NO;
        stepLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
        stepLabel.textColor = [UIColor dw_tertiaryTextColor];
        stepLabel.attributedText = StepText(itemType, completed);
        [container addSubview:stepLabel];

        UILabel *nameLabel = [[UILabel alloc] init];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        nameLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        nameLabel.textColor = NameColor(itemType);
        nameLabel.adjustsFontForContentSizeCategory = YES;
        nameLabel.numberOfLines = 0;
        nameLabel.text = NameText(itemType);
        [container addSubview:nameLabel];

        [NSLayoutConstraint activateConstraints:@[
            [rectView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [rectView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [rectView.widthAnchor constraintEqualToConstant:60],
            [rectView.heightAnchor constraintEqualToConstant:60],
            [rectView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:rectView.bottomAnchor],

            [icon.topAnchor constraintEqualToAnchor:rectView.topAnchor],
            [icon.leadingAnchor constraintEqualToAnchor:rectView.leadingAnchor],
            [rectView.trailingAnchor constraintEqualToAnchor:icon.trailingAnchor],
            [rectView.bottomAnchor constraintEqualToAnchor:icon.bottomAnchor],

            [stepLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
            [stepLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [container.trailingAnchor constraintEqualToAnchor:stepLabel.trailingAnchor],

            [nameLabel.topAnchor constraintEqualToAnchor:stepLabel.bottomAnchor],
            [nameLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [container.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
            [container.bottomAnchor constraintEqualToAnchor:nameLabel.bottomAnchor],

            [container.leadingAnchor constraintEqualToAnchor:rectView.trailingAnchor
                                                    constant:12.0],
            [self.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [container.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [container.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:container.bottomAnchor],
        ]];
    }
    return self;
}

@end
