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

@class DWCurrentUserProfileView;
@class DSBlockchainIdentity;

@protocol DWCurrentUserProfileViewDelegate <NSObject>

- (void)currentUserProfileView:(DWCurrentUserProfileView *)view showQRAction:(UIButton *)sender;
- (void)currentUserProfileView:(DWCurrentUserProfileView *)view editProfileAction:(UIButton *)sender;

@end

@interface DWCurrentUserProfileView : UIView

@property (nullable, nonatomic, weak) id<DWCurrentUserProfileViewDelegate> delegate;
@property (nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

/// Refresh the avatar image + info label from
/// `DWCurrentUserIdentityInfo.shared`. Row #17 proper entry point —
/// equivalent to setting `blockchainIdentity` from the DashSync path,
/// but sourced from SwiftDashSDK. Safe to call repeatedly; the
/// underlying `dw_setAvatarWithURLString:` helper cancels any
/// in-flight image load.
- (void)reloadFromCurrentUser;

@end

NS_ASSUME_NONNULL_END
