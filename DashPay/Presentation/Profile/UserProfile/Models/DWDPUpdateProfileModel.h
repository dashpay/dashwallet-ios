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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWDPUpdateProfileModelState) {
    DWDPUpdateProfileModelState_Ready,
    DWDPUpdateProfileModelState_Loading,
    DWDPUpdateProfileModelState_Error,
};

@interface DWDPUpdateProfileModel : NSObject

@property (readonly, nonatomic, assign) DWDPUpdateProfileModelState state;

/// Update the current user's DashPay profile.
///
/// Row #17 proper: branches on whether DashSync has a registered
/// `defaultBlockchainIdentity` for this wallet — yes → legacy
/// DashSync write path (DSBlockchainIdentity sign-and-publish);
/// no → SwiftDashSDK write path
/// (`DWProfileUpdateBridge.updateProfile:...`).
///
/// `avatarImage` is the cropped UIImage the user picked, or `nil` if
/// the avatar wasn't changed in this session. The DashSync path
/// ignores it (legacy code uses the URL only); the SDK path
/// JPEG-encodes it and hands the bytes to the SDK for hash
/// computation.
- (void)updateWithDisplayName:(NSString *)rawDisplayName
                      aboutMe:(NSString *)rawAboutMe
              avatarURLString:(nullable NSString *)avatarURLString
                  avatarImage:(nullable UIImage *)avatarImage;

- (void)retry;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
