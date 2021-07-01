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

#import "DWSyncingHeaderView.h"

#import "DWButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSyncingHeaderView ()

@property (strong, nonatomic) UIButton *syncingButton;

@end

NS_ASSUME_NONNULL_END

@implementation DWSyncingHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        titleLabel.text = NSLocalizedString(@"History", nil);
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        [titleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh + 1
                                      forAxis:UILayoutConstraintAxisHorizontal];
        [self addSubview:titleLabel];

        DWButton *syncingButton = [[DWButton alloc] init];
        syncingButton.translatesAutoresizingMaskIntoConstraints = NO;
        syncingButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        [syncingButton setTitleColor:[UIColor dw_darkTitleColor] forState:UIControlStateNormal];
        [syncingButton setContentHuggingPriority:UILayoutPriorityDefaultHigh - 1
                                         forAxis:UILayoutConstraintAxisHorizontal];
        [syncingButton setContentCompressionResistancePriority:UILayoutPriorityRequired - 1
                                                       forAxis:UILayoutConstraintAxisHorizontal];
        [syncingButton addTarget:self action:@selector(syncingButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:syncingButton];
        _syncingButton = syncingButton;

        UIButton *filterButton = [UIButton buttonWithType:UIButtonTypeCustom];
        filterButton.translatesAutoresizingMaskIntoConstraints = NO;
        [filterButton setImage:[UIImage imageNamed:@"icon_filter_button"] forState:UIControlStateNormal];
        [filterButton addTarget:self action:@selector(filterButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:filterButton];


        const CGFloat padding = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor
                                                 constant:padding],
            [self.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                              constant:padding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:padding],

            [syncingButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:syncingButton.bottomAnchor],
            [syncingButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [syncingButton.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                        constant:8.0],
            [syncingButton.heightAnchor constraintEqualToConstant:44.0],

            [filterButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:filterButton.bottomAnchor],
            [filterButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [filterButton.leadingAnchor constraintEqualToAnchor:syncingButton.trailingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:filterButton.trailingAnchor
                                                constant:10.0],
            [filterButton.heightAnchor constraintEqualToConstant:44.0],
            [filterButton.widthAnchor constraintEqualToConstant:44.0],
        ]];
    }
    return self;
}

- (void)setProgress:(float)progress {
    NSString *percentString = [NSString stringWithFormat:@"%0.1f%%", progress * 100.0];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];

    NSAttributedString *str1 = [[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@ ", NSLocalizedString(@"Syncing", nil)]
            attributes:@{
                NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleBody],
            }];
    [result appendAttributedString:str1];

    NSAttributedString *str2 = [[NSAttributedString alloc]
        initWithString:percentString
            attributes:@{
                NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline],
            }];
    [result appendAttributedString:str2];

    [result endEditing];

    [self.syncingButton setAttributedTitle:result forState:UIControlStateNormal];
    self.syncingButton.hidden = self.syncState != DWSyncModelState_Syncing;
}

- (void)filterButtonAction:(UIButton *)sender {
    [self.delegate syncingHeaderView:self filterButtonAction:sender];
}

- (void)syncingButtonAction:(UIButton *)sender {
    [self.delegate syncingHeaderView:self syncingButtonAction:sender];
}

@end
