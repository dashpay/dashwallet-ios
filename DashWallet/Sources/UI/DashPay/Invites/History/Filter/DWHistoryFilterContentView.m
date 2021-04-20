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

#import "DWHistoryFilterContentView.h"

#import "DWPressableButton.h"
#import "DWUIKit.h"

@implementation DWHistoryFilterContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;

        UIButton *allButton = [self.class button];
        allButton.tag = DWInvitationHistoryFilter_All;
        [allButton setTitle:@"All" forState:UIControlStateNormal];
        [allButton addTarget:self action:@selector(buttonAction:) forControlEvents:UIControlEventTouchUpInside];

        UIButton *pendingButton = [self.class button];
        pendingButton.tag = DWInvitationHistoryFilter_Pending;
        [pendingButton setTitle:NSLocalizedString(@"Pending", nil) forState:UIControlStateNormal];
        [pendingButton addTarget:self action:@selector(buttonAction:) forControlEvents:UIControlEventTouchUpInside];

        UIButton *claimedButton = [self.class button];
        claimedButton.tag = DWInvitationHistoryFilter_Claimed;
        [claimedButton setTitle:NSLocalizedString(@"Claimed", nil) forState:UIControlStateNormal];
        [claimedButton addTarget:self action:@selector(buttonAction:) forControlEvents:UIControlEventTouchUpInside];

        UIView *separator1 = [[UIView alloc] init];
        separator1.translatesAutoresizingMaskIntoConstraints = NO;
        separator1.backgroundColor = [UIColor dw_separatorLineColor];

        UIView *separator2 = [[UIView alloc] init];
        separator2.translatesAutoresizingMaskIntoConstraints = NO;
        separator2.backgroundColor = [UIColor dw_separatorLineColor];

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ allButton, separator1, pendingButton, separator2, claimedButton ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        [self addSubview:stackView];

        const CGFloat padding = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor
                                                constant:padding],
            [self.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor],

            [claimedButton.heightAnchor constraintGreaterThanOrEqualToConstant:80],
            [allButton.heightAnchor constraintGreaterThanOrEqualToConstant:80],
            [pendingButton.heightAnchor constraintGreaterThanOrEqualToConstant:80],

            [separator1.heightAnchor constraintEqualToConstant:1],
            [separator2.heightAnchor constraintEqualToConstant:1],
        ]];
    }
    return self;
}

- (void)buttonAction:(UIButton *)sender {
    [self.delegate historyFilterView:self didSelectFilter:sender.tag];
}

+ (UIButton *)button {
    DWPressableButton *button = [[DWPressableButton alloc] initWithFrame:CGRectZero];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    button.adjustsImageWhenHighlighted = NO;
    [button setTitleColor:[UIColor dw_darkTitleColor] forState:UIControlStateNormal];
    return button;
}
@end
