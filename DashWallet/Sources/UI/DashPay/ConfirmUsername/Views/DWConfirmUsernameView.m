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

#import "DWConfirmUsernameView.h"

#import "DWCheckbox.h"
#import "DWDashPayConstants.h"
#import "DWUIKit.h"
#import "NSAttributedString+DWBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWConfirmUsernameView ()

@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) DWCheckbox *confirmationCheckbox;

@end

NS_ASSUME_NONNULL_END

@implementation DWConfirmUsernameView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
        infoLabel.numberOfLines = 0;
        infoLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:infoLabel];
        _infoLabel = infoLabel;

        DWCheckbox *confirmationCheckbox = [[DWCheckbox alloc] initWithFrame:CGRectZero];
        confirmationCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
        confirmationCheckbox.title = NSLocalizedString(@"I Accept", nil);
        confirmationCheckbox.backgroundColor = self.backgroundColor;
        [self addSubview:confirmationCheckbox];
        _confirmationCheckbox = confirmationCheckbox;

        const CGFloat padding = 16.0;
        const CGFloat checkboxHeight = 44.0;
        [NSLayoutConstraint activateConstraints:@[
            [infoLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor
                                                    constant:-checkboxHeight],
            [infoLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:infoLabel.trailingAnchor
                                                constant:padding],

            [confirmationCheckbox.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [confirmationCheckbox.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor],
            [confirmationCheckbox.trailingAnchor constraintGreaterThanOrEqualToAnchor:self.trailingAnchor],
            [confirmationCheckbox.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(contentSizeCategoryDidChangeNotification)
                                   name:UIContentSizeCategoryDidChangeNotification
                                 object:nil];

        [self reloadAttributedData];
    }
    return self;
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    UIColor *color = [UIColor dw_darkTitleColor];
    NSAttributedString *amountString = [NSAttributedString
        dw_dashAttributedStringForAmount:DWDP_MIN_BALANCE_TO_CREATE_USERNAME
                               tintColor:color
                                    font:[UIFont dw_fontForTextStyle:UIFontTextStyleHeadline]];
    NSString *text = NSLocalizedString(@"It costs %@ to create your Evolution account.",
                                       @"It costs 0.1 Dash to create your Evolution account.");
    NSArray<NSString *> *split = [text componentsSeparatedByString:@"%@"];
    NSAssert(split.count == 2, @"Invalid localized string");
    if (split.count != 2) {
        self.infoLabel.attributedText = amountString;
        return;
    }

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];

    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleBody],
        NSForegroundColorAttributeName : color,
    };

    NSAttributedString *first = [[NSAttributedString alloc] initWithString:[split.firstObject stringByAppendingString:@" "]
                                                                attributes:attributes];
    [result appendAttributedString:first];

    [result appendAttributedString:amountString];

    NSAttributedString *last = [[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:split.lastObject]
                                                               attributes:attributes];
    [result appendAttributedString:last];

    [result endEditing];

    self.infoLabel.attributedText = result;
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

@end
