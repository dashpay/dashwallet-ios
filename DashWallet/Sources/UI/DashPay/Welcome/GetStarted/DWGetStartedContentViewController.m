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

#import "DWGetStartedContentViewController.h"

#import "DWGetStartedItemView.h"
#import "DWUIKit.h"

@implementation DWGetStartedContentViewController

- (instancetype)initWithPage:(DWGetStartedPage)page {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _page = page;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    titleLabel.textColor = [UIColor dw_secondaryTextColor];
    titleLabel.text = NSLocalizedString(@"Welcome to DashPay", nil);
    titleLabel.numberOfLines = 0;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleLargeTitle];
    subtitleLabel.textColor = [UIColor dw_darkTitleColor];
    subtitleLabel.text = NSLocalizedString(@"Let’s Get Started", nil);
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.adjustsFontForContentSizeCategory = YES;
    [self.view addSubview:subtitleLabel];

    UIView *lineView = [[UIView alloc] init];
    lineView.translatesAutoresizingMaskIntoConstraints = NO;
    lineView.backgroundColor = [UIColor dw_tertiaryTextColor];
    [self.view addSubview:lineView];


    UIView *blueView = [[UIView alloc] init];
    blueView.translatesAutoresizingMaskIntoConstraints = NO;
    blueView.backgroundColor = [UIColor dw_lightBlueColor];
    [self.view addSubview:blueView];

    NSMutableArray<UIView *> *itemViews = [NSMutableArray array];
    NSArray<NSNumber *> *items = [self items];
    NSArray<NSNumber *> *completedItems = [self completedItems];
    for (NSUInteger i = 0; i < 3; i++) {
        NSNumber *item = items[i];
        NSNumber *completed = completedItems[i];

        if (i == 1) {
            blueView.hidden = !completed.boolValue;
        }

        DWGetStartedItemView *itemView =
            [[DWGetStartedItemView alloc] initWithItemType:item.unsignedIntegerValue
                                                 completed:completed.boolValue];
        itemView.translatesAutoresizingMaskIntoConstraints = NO;
        [itemViews addObject:itemView];
    }

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:itemViews];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.spacing = 60;
    stack.axis = UILayoutConstraintAxisVertical;
    [self.view addSubview:stack];

    UIView *parent = self.view;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:parent.topAnchor
                                             constant:44],
        [titleLabel.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [parent.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [parent.trailingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor],

        [stack.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor
                                        constant:40],
        [stack.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [parent.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor],

        [lineView.topAnchor constraintEqualToAnchor:stack.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:lineView.bottomAnchor],
        [lineView.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor
                                               constant:30],
        [lineView.widthAnchor constraintEqualToConstant:3],

        [blueView.topAnchor constraintEqualToAnchor:lineView.topAnchor],
        [blueView.leadingAnchor constraintEqualToAnchor:lineView.leadingAnchor],
        [blueView.widthAnchor constraintEqualToConstant:3],
        [blueView.heightAnchor constraintEqualToAnchor:lineView.heightAnchor
                                            multiplier:0.5],
    ]];
}

- (NSArray<NSNumber *> *)items {
    switch (self.page) {
        case DWGetStartedPage_1:
            return @[
                @(DWGetStartedItemType_1),
                @(DWGetStartedItemType_Inactive2),
                @(DWGetStartedItemType_Inactive3),
            ];

        case DWGetStartedPage_2:
            return @[
                @(DWGetStartedItemType_1),
                @(DWGetStartedItemType_Active2),
                @(DWGetStartedItemType_Inactive3),
            ];

        case DWGetStartedPage_3:
            return @[
                @(DWGetStartedItemType_1),
                @(DWGetStartedItemType_Active2),
                @(DWGetStartedItemType_Active3),
            ];
    }
}

- (NSArray<NSNumber *> *)completedItems {
    switch (self.page) {
        case DWGetStartedPage_1:
            return @[
                @NO,
                @NO,
                @NO,
            ];

        case DWGetStartedPage_2:
            return @[
                @YES,
                @NO,
                @NO,
            ];

        case DWGetStartedPage_3:
            return @[
                @YES,
                @YES,
                @NO,
            ];
    }
}

@end
