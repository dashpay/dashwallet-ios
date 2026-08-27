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

#import "DWDPUpdateProfileModel.h"

#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPUpdateProfileModel ()

@property (nonatomic, assign) DWDPUpdateProfileModelState state;
@property (nullable, nonatomic, copy) NSString *pendingDisplayName;
@property (nullable, nonatomic, copy) NSString *pendingAboutMe;
@property (nullable, nonatomic, copy) NSString *pendingAvatarURL;
@property (nullable, nonatomic, strong) UIImage *pendingAvatarImage;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPUpdateProfileModel

- (void)updateWithDisplayName:(NSString *)rawDisplayName
                      aboutMe:(NSString *)rawAboutMe
              avatarURLString:(nullable NSString *)avatarURLString
                  avatarImage:(nullable UIImage *)avatarImage {
    NSString *displayName = rawDisplayName;
    // `displayName` is normalised to empty string when it equals the
    // bare username (legacy DashSync convention: "displayName same
    // as username means no override"). Use the helper for the
    // reference username so the SDK path also gets the
    // normalisation.
    NSString *referenceUsername = DWCurrentUserIdentityInfo.shared.username;
    if (referenceUsername != nil && [rawDisplayName isEqualToString:referenceUsername]) {
        displayName = @"";
    }
    displayName = [displayName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSString *aboutMe = [rawAboutMe stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSString *avatar = avatarURLString;
    if (avatar.length == 0) {
        avatar = nil;
    }

    self.pendingDisplayName = displayName;
    self.pendingAboutMe = aboutMe;
    self.pendingAvatarURL = avatar;
    self.pendingAvatarImage = avatarImage;
    [self retry];
}

- (void)retry {
    self.state = DWDPUpdateProfileModelState_Loading;

    __weak typeof(self) weakSelf = self;
    [DWProfileUpdateBridge.shared
        updateProfileWithDisplayName:self.pendingDisplayName
                       publicMessage:self.pendingAboutMe
                           avatarURL:self.pendingAvatarURL
                         avatarImage:self.pendingAvatarImage
                          completion:^(NSError *_Nullable error) {
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              if (!strongSelf) {
                                  return;
                              }
                              strongSelf.state = error == nil
                                  ? DWDPUpdateProfileModelState_Ready
                                  : DWDPUpdateProfileModelState_Error;
                          }];
}

- (void)reset {
    self.state = DWDPUpdateProfileModelState_Ready;
}

@end
