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

#import "DWHomeViewController+DWBackupReminder.h"

#import "DWHomeViewController+DWSecureWalletDelegateImpl.h"
#import "DWNavigationController.h"
#import "DWSecureWalletInfoViewController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWHomeViewController (DWBackupReminder)

- (void)showWalletBackupReminderIfNeeded {
    if (!self.model.shouldShowWalletBackupReminder) {
        return;
    }

    DWSecureWalletInfoViewController *controller = [DWSecureWalletInfoViewController controller];
    controller.type = DWSecureWalletInfoType_Reminder;
    controller.delegate = self;
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:navigationController
                       animated:YES
                     completion:^{
                         if ([self.presentedViewController isKindOfClass:UINavigationController.class]) {
                             UIViewController *controller =
                                 [(UINavigationController *)self.presentedViewController topViewController];
                             if ([controller isKindOfClass:DWSecureWalletInfoViewController.class]) {
                                 [self.model walletBackupReminderWasShown];
                             }
                         }
                     }];
}

@end

NS_ASSUME_NONNULL_END
