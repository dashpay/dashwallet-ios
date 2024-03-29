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

#import "DWBaseActionButtonViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class DWRootEditProfileViewController;

@protocol DWRootEditProfileViewControllerDelegate <NSObject>

- (void)editProfileViewController:(DWRootEditProfileViewController *)controller
                updateDisplayName:(NSString *)rawDisplayName
                          aboutMe:(NSString *)rawAboutMe
                  avatarURLString:(nullable NSString *)avatarURLString;

- (void)editProfileViewControllerDidCancel:(DWRootEditProfileViewController *)controller;

@end


@interface DWRootEditProfileViewController : DWBaseActionButtonViewController

@property (nullable, nonatomic, weak) id<DWRootEditProfileViewControllerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
