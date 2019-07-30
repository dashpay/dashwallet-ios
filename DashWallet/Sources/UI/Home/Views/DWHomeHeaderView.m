//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWHomeHeaderView.h"

#import "DWBalancePayReceiveButtonsView.h"
#import "DWSyncView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeHeaderView ()

@property (readonly, nonatomic, strong) DWBalancePayReceiveButtonsView *balancePayReceiveButtonsView;
@property (readonly, nonatomic, strong) DWSyncView *syncView;
@property (readonly, nonatomic, strong) UIStackView *stackView;

@end

@implementation DWHomeHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        DWBalancePayReceiveButtonsView *balancePayReceiveButtonsView = [[DWBalancePayReceiveButtonsView alloc] initWithFrame:CGRectZero];
        _balancePayReceiveButtonsView = balancePayReceiveButtonsView;

        DWSyncView *syncView = [[DWSyncView alloc] initWithFrame:CGRectZero];
        _syncView = syncView;

        NSArray<UIView *> *views = @[ balancePayReceiveButtonsView, syncView ];
        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:views];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        [self addSubview:stackView];
        _stackView = stackView;

        [NSLayoutConstraint activateConstraints:@[
            [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.syncView setProgress:0.5 animated:YES];
        });
    }
    return self;
}

- (void)parentScrollViewDidScroll:(UIScrollView *)scrollView {
    [self.balancePayReceiveButtonsView parentScrollViewDidScroll:scrollView];
}

@end

NS_ASSUME_NONNULL_END
