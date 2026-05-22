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

#import "DSBlockchainIdentity.h"

NS_ASSUME_NONNULL_BEGIN

@interface DSBlockchainIdentity (DWDisplayTitleSubtitle)

- (NSAttributedString *)dw_asTitleSubtitle;

@end

/// Build a title+subtitle attributed string for the current
/// SwiftDashSDK-side user identity. Mirrors the (display name / username)
/// layout of `-dw_asTitleSubtitle` but sources the strings from
/// `DWCurrentUserIdentityInfo.shared`. Returns an empty attributed
/// string when no identity is registered.
///
/// Row #17 proper entry point — used by the current-user surfaces
/// (My Profile, Edit Profile preview). Contact / other-user
/// rendering keeps using the existing category method until row #18
/// migrates `DSBlockchainIdentity` reads on the contact side too.
extern NSAttributedString *DWCurrentUserTitleSubtitleAttributedString(void);

NS_ASSUME_NONNULL_END
