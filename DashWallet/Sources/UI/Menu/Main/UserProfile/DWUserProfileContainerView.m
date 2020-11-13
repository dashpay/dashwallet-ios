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

#import "DWUserProfileContainerView.h"

#import "DWCurrentUserProfileModel.h"
#import "DWErrorUpdatingUserProfileView.h"
#import "DWUIKit.h"
#import "DWUpdatingUserProfileView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileContainerView () <DWErrorUpdatingUserProfileViewDelegate>

@property (readonly, nonatomic, strong) DWCurrentUserProfileView *profileView;
@property (readonly, nonatomic, strong) DWUpdatingUserProfileView *updatingView;
@property (readonly, nonatomic, strong) DWErrorUpdatingUserProfileView *errorView;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileContainerView

- (id<DWCurrentUserProfileViewDelegate>)delegate {
    return self.profileView.delegate;
}

- (void)setDelegate:(id<DWCurrentUserProfileViewDelegate>)delegate {
    self.profileView.delegate = delegate;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        DWCurrentUserProfileView *profileView = [[DWCurrentUserProfileView alloc] init];
        profileView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:profileView];
        _profileView = profileView;

        DWUpdatingUserProfileView *updatingView = [[DWUpdatingUserProfileView alloc] init];
        updatingView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:updatingView];
        _updatingView = updatingView;

        DWErrorUpdatingUserProfileView *errorView = [[DWErrorUpdatingUserProfileView alloc] init];
        errorView.translatesAutoresizingMaskIntoConstraints = NO;
        errorView.delegate = self;
        [self addSubview:errorView];
        _errorView = errorView;

        const CGFloat padding = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [profileView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [profileView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:profileView.bottomAnchor],
            [self.trailingAnchor constraintEqualToAnchor:profileView.trailingAnchor],

            [updatingView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [updatingView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                       constant:padding],
            [self.bottomAnchor constraintEqualToAnchor:updatingView.bottomAnchor
                                              constant:5.0],
            [self.trailingAnchor constraintEqualToAnchor:updatingView.trailingAnchor
                                                constant:padding],

            [errorView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [errorView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:padding],
            [self.bottomAnchor constraintEqualToAnchor:errorView.bottomAnchor
                                              constant:5.0],
            [self.trailingAnchor constraintEqualToAnchor:errorView.trailingAnchor
                                                constant:padding],
        ]];

        [self mvvm_observe:DW_KEYPATH(self, userModel.updateModel.state)
                      with:^(typeof(self) self, id value) {
                          switch (self.userModel.updateModel.state) {
                              case DWDPUpdateProfileModelState_Ready:
                                  [self update];
                                  self.profileView.hidden = NO;
                                  self.updatingView.hidden = YES;
                                  self.errorView.hidden = YES;
                                  break;
                              case DWDPUpdateProfileModelState_Loading:
                                  self.profileView.hidden = YES;
                                  self.updatingView.hidden = NO;
                                  self.errorView.hidden = YES;
                                  break;
                              case DWDPUpdateProfileModelState_Error:
                                  self.profileView.hidden = YES;
                                  self.updatingView.hidden = YES;
                                  self.errorView.hidden = NO;
                                  break;
                          }
                      }];
    }
    return self;
}

- (void)update {
    self.profileView.blockchainIdentity = self.userModel.blockchainIdentity;
}

#pragma mark - DWErrorUpdatingUserProfileViewDelegate

- (void)errorUpdatingUserProfileView:(DWErrorUpdatingUserProfileView *)view retryAction:(UIButton *)sender {
    [self.userModel.updateModel retry];
}

- (void)errorUpdatingUserProfileView:(DWErrorUpdatingUserProfileView *)view cancelAction:(UIButton *)sender {
    [self.userModel.updateModel reset];
    [self.userModel update];
}

@end
