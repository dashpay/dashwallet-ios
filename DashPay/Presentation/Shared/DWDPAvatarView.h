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
@property (nullable, nonatomic, copy) DSBlockchainIdentity *blockchainIdentity;
@property (nonatomic, assign, getter=isSmall) BOOL small;

- (void)setAsDashPlaceholder;
- (void)configureWithUsername:(NSString *)username;

/// Paint the avatar for the current SwiftDashSDK-side user identity.
/// Reads username + avatar URL from `DWCurrentUserIdentityInfo.shared`
/// and triggers the same async image-load + letter-fallback pattern
/// as `setBlockchainIdentity:`. Row #17 proper entry point; the
/// legacy `setBlockchainIdentity:` path stays for contact / other-
/// user rendering (Row #18).
- (void)configureAsCurrentUser;

@end

NS_ASSUME_NONNULL_END
