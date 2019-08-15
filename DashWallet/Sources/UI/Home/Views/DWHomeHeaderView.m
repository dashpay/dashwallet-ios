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
#import "DWHomeModel.h"
#import "DWShortcutsView.h"
#import "DWSyncModel.h"
#import "DWSyncView.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const SYNCVIEW_HIDE_DELAY = 2.0;

@interface DWHomeHeaderView () <DWBalancePayReceiveButtonsViewDelegate, DWShortcutsViewDelegate>

@property (readonly, nonatomic, strong) DWBalancePayReceiveButtonsView *balancePayReceiveButtonsView;
@property (readonly, nonatomic, strong) DWSyncView *syncView;
@property (readonly, nonatomic, strong) DWShortcutsView *shortcutsView;
@property (readonly, nonatomic, strong) UIStackView *stackView;

@end

@implementation DWHomeHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        DWBalancePayReceiveButtonsView *balancePayReceiveButtonsView = [[DWBalancePayReceiveButtonsView alloc] initWithFrame:CGRectZero];
        balancePayReceiveButtonsView.delegate = self;
        _balancePayReceiveButtonsView = balancePayReceiveButtonsView;

        DWSyncView *syncView = [[DWSyncView alloc] initWithFrame:CGRectZero];
        _syncView = syncView;

        DWShortcutsView *shortcutsView = [[DWShortcutsView alloc] initWithFrame:CGRectZero];
        shortcutsView.delegate = self;
        _shortcutsView = shortcutsView;

        NSArray<UIView *> *views = @[ balancePayReceiveButtonsView, syncView, shortcutsView ];
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

        // KVO

        [self mvvm_observe:DW_KEYPATH(self, model.syncModel.state)
                      with:^(typeof(self) self, NSNumber *value) {
                          if (!value) {
                              return;
                          }

                          const DWSyncModelState state = self.model.syncModel.state;

                          [self.syncView setSyncState:state];

                          if (state == DWSyncModelState_SyncDone) {
                              [self performSelector:@selector(hideSyncView)
                                         withObject:nil
                                         afterDelay:SYNCVIEW_HIDE_DELAY];
                          }
                          else {
                              [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                                       selector:@selector(hideSyncView)
                                                                         object:nil];
                          }
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.syncModel.progress)
                      with:^(typeof(self) self, NSNumber *value) {
                          if (!value) {
                              return;
                          }

                          [self.syncView setProgress:self.model.syncModel.progress animated:YES];
                      }];
    }
    return self;
}

- (void)setModel:(nullable DWHomeModel *)model {
    _model = model;

    self.balancePayReceiveButtonsView.model = model;
    self.shortcutsView.model = model.shortcutsModel;
}

- (nullable id<DWShortcutsActionDelegate>)shortcutsDelegate {
    return self.shortcutsView.actionDelegate;
}

- (void)setShortcutsDelegate:(nullable id<DWShortcutsActionDelegate>)shortcutsDelegate {
    self.shortcutsView.actionDelegate = shortcutsDelegate;
}

- (void)parentScrollViewDidScroll:(UIScrollView *)scrollView {
    [self.balancePayReceiveButtonsView parentScrollViewDidScroll:scrollView];
}

#pragma mark - DWBalancePayReceiveButtonsViewDelegate

- (void)balancePayReceiveButtonsView:(DWBalancePayReceiveButtonsView *)view
                     payButtonAction:(UIButton *)sender {
    [self.delegate homeHeaderView:self payButtonAction:sender];
}

- (void)balancePayReceiveButtonsView:(DWBalancePayReceiveButtonsView *)view
                 receiveButtonAction:(UIButton *)sender {
    [self.delegate homeHeaderView:self receiveButtonAction:sender];
}

#pragma mark - DWShortcutsViewDelegate

- (void)shortcutsViewDidUpdateContentSize:(DWShortcutsView *)view {
    [self.delegate homeHeaderViewDidUpdateContents:self];
}

#pragma mark - Private

- (void)hideSyncView {
    self.syncView.hidden = YES;

    [self.delegate homeHeaderViewDidUpdateContents:self];
}

@end

NS_ASSUME_NONNULL_END
