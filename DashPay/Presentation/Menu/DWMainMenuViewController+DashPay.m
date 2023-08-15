//  
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

#import "DWMainMenuViewController+DashPay.h"
#import "DWRootEditProfileViewController.h"
#import "DWMainMenuContentView.h"

@implementation DWMainMenuViewController (DashPay)

#pragma mark - DWRootEditProfileViewControllerDelegate

- (void)editProfileViewController:(DWRootEditProfileViewController *)controller
                updateDisplayName:(NSString *)rawDisplayName
                          aboutMe:(NSString *)rawAboutMe
                  avatarURLString:(nullable NSString *)avatarURLString {
    DWMainMenuContentView *view = (DWMainMenuContentView *) self.view;
    [view.userModel.updateModel updateWithDisplayName:rawDisplayName aboutMe:rawAboutMe avatarURLString:avatarURLString];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)editProfileViewControllerDidCancel:(DWRootEditProfileViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

@end
