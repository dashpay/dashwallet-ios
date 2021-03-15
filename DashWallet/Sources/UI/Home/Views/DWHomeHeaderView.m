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

#import "DWBalanceView.h"
#import "DWCurrentUserProfileModel.h"
#import "DWDPRegistrationStatus.h"
#import "DWDPWelcomeView.h"
#import "DWDashPayProfileView.h"
#import "DWShortcutAction.h"
#import "DWShortcutsView.h"
#import "DWSyncView.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const AVATAR_SIZE = {72.0, 72.0};

@interface DWHomeHeaderView () <DWBalanceViewDelegate,
                                DWShortcutsViewDelegate,
                                DWSyncViewDelegate>

@property (readonly, nonatomic, strong) DWDashPayProfileView *profileView;
@property (readonly, nonatomic, strong) DWBalanceView *balanceView;
@property (readonly, nonatomic, strong) DWSyncView *syncView;
@property (readonly, nonatomic, strong) DWShortcutsView *shortcutsView;
@property (readonly, nonatomic, strong) DWDPWelcomeView *welcomeView;
@property (readonly, nonatomic, strong) UIStackView *stackView;

@end

@implementation DWHomeHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        DWDashPayProfileView *profileView = [[DWDashPayProfileView alloc] initWithFrame:CGRectZero];
        profileView.translatesAutoresizingMaskIntoConstraints = NO;
        [profileView addTarget:self action:@selector(profileViewAction:) forControlEvents:UIControlEventTouchUpInside];
        _profileView = profileView;

        DWBalanceView *balanceView = [[DWBalanceView alloc] initWithFrame:CGRectZero];
        balanceView.translatesAutoresizingMaskIntoConstraints = NO;
        balanceView.delegate = self;
        _balanceView = balanceView;

        DWSyncView *syncView = [[DWSyncView alloc] initWithFrame:CGRectZero];
        syncView.translatesAutoresizingMaskIntoConstraints = NO;
        syncView.delegate = self;
        _syncView = syncView;

        DWShortcutsView *shortcutsView = [[DWShortcutsView alloc] initWithFrame:CGRectZero];
        shortcutsView.translatesAutoresizingMaskIntoConstraints = NO;
        shortcutsView.delegate = self;
        _shortcutsView = shortcutsView;

        DWDPWelcomeView *welcomeView = [[DWDPWelcomeView alloc] initWithFrame:CGRectZero];
        welcomeView.translatesAutoresizingMaskIntoConstraints = NO;
        [welcomeView addTarget:self action:@selector(joinDashPayAction:) forControlEvents:UIControlEventTouchUpInside];
        _welcomeView = welcomeView;

        NSArray<UIView *> *views = @[ profileView, balanceView, shortcutsView, welcomeView, syncView ];
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
                              [self hideSyncView];
                          }
                          else {
                              [self showSyncView];
                          }
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.syncModel.progress)
                      with:^(typeof(self) self, NSNumber *value) {
                          if (!value) {
                              return;
                          }

                          [self.syncView setProgress:self.model.syncModel.progress animated:YES];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.dashPayModel.registrationStatus)
                      with:^(typeof(self) self, id value) {
                          [self updateProfileView];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.dashPayModel.username)
                      with:^(typeof(self) self, id value) {
                          [self updateProfileView];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.dashPayModel.userProfile.state)
                      with:^(typeof(self) self, id value) {
                          [self updateProfileView];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.dashPayModel.unreadNotificationsCount)
                      with:^(typeof(self) self, id value) {
                          self.profileView.unreadCount = self.model.dashPayModel.unreadNotificationsCount;
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.isDashPayReady)
                      with:^(typeof(self) self, id value) {
                          [self updateProfileView];
                      }];
    }
    return self;
}

- (void)setModel:(nullable id<DWHomeProtocol>)model {
    _model = model;

    self.balanceView.model = model;
    self.shortcutsView.model = model.shortcutsModel;
    [self updateProfileView];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];

    if (self.window) {
        [self.model.dashPayModel.userProfile update];
        [self updateProfileView];
    }
}

- (nullable id<DWShortcutsActionDelegate>)shortcutsDelegate {
    return self.shortcutsView.actionDelegate;
}

- (void)setShortcutsDelegate:(nullable id<DWShortcutsActionDelegate>)shortcutsDelegate {
    self.shortcutsView.actionDelegate = shortcutsDelegate;
}

- (void)parentScrollViewDidScroll:(UIScrollView *)scrollView {
}

#pragma mark - DWBalanceViewDelegate

- (void)balanceView:(DWBalanceView *)view balanceLongPressAction:(UIControl *)sender {
    DWShortcutAction *action = [DWShortcutAction action:DWShortcutActionType_LocalCurrency];
    [self.shortcutsDelegate shortcutsView:self.balanceView
                          didSelectAction:action
                                   sender:sender];
}

#pragma mark - DWShortcutsViewDelegate

- (void)shortcutsViewDidUpdateContentSize:(DWShortcutsView *)view {
    [self.delegate homeHeaderViewDidUpdateContents:self];
}

#pragma mark - DWSyncViewDelegate

- (void)syncViewRetryButtonAction:(DWSyncView *)view {
    [self.model retrySyncing];
}

#pragma mark - Private

- (void)profileViewAction:(UIControl *)sender {
    [self.delegate homeHeaderView:self profileButtonAction:sender];
}

- (void)joinDashPayAction:(UIControl *)sender {
    [self.delegate homeHeaderView:self joinDashPayAction:sender];
}

- (void)updateProfileView {
    DWDPRegistrationStatus *status = self.model.dashPayModel.registrationStatus;
    const BOOL completed = self.model.dashPayModel.registrationCompleted;
    if ((status.state == DWDPRegistrationState_Done || completed) && self.model.dashPayModel.blockchainIdentity) {
        self.profileView.blockchainIdentity = self.model.dashPayModel.blockchainIdentity;
        self.profileView.unreadCount = self.model.dashPayModel.unreadNotificationsCount;
        self.profileView.hidden = NO;
    }
    else {
        self.profileView.hidden = YES;
    }
    self.welcomeView.hidden = ![self.model isDashPayReadyMainSuggestion];
    [self.delegate homeHeaderViewDidUpdateContents:self];
}

- (void)hideSyncView {
    self.syncView.hidden = YES;

    [self.delegate homeHeaderViewDidUpdateContents:self];
}

- (void)showSyncView {
    self.syncView.hidden = NO;

    [self.delegate homeHeaderViewDidUpdateContents:self];
}

@end

NS_ASSUME_NONNULL_END
