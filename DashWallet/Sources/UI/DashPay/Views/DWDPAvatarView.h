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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const DPCropParameterName;

@class DSBlockchainIdentity;

typedef NS_ENUM(NSUInteger, DWDPAvatarBackgroundMode) {
    DWDPAvatarBackgroundMode_DashBlue,
    DWDPAvatarBackgroundMode_Random,
};

@interface DWDPAvatarView : UIView

@property (nonatomic, assign) DWDPAvatarBackgroundMode backgroundMode;

/// TODO(invitations-sdk-rebuild): invitation-flow-only legacy setter, kept so the
/// DashSync-backed invitation screens compile untouched until they are rebuilt on
/// SwiftDashSDK. Everything else configures with
/// `configureWithUsername:avatarURLString:` or `configureAsCurrentUser`.
@property (nullable, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;
@property (nonatomic, assign, getter=isSmall) BOOL small;

- (void)setAsDashPlaceholder;
- (void)configureWithUsername:(NSString *)username;
/// Current-user render path backed by `DWCurrentUserIdentityInfo.shared`.
- (void)configureAsCurrentUser;

/// Letter + remote profile image from plain strings (no identity object needed).
/// `avatarURLString` is the raw profile `avatarUrl` — percent-encoding is applied
/// here. Falls back to the username letter when the URL is nil or fails to load.
- (void)configureWithUsername:(nullable NSString *)username avatarURLString:(nullable NSString *)avatarURLString;

@end

NS_ASSUME_NONNULL_END
