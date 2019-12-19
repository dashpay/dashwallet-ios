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

#import "DWDemoMainTabbarViewController.h"

#import "DWExtendedContainerViewController+DWProtected.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWDemoMainTabbarViewController

- (void)hideModalControllerCompletion:(void (^)(void))completion {
    UIViewController *modalController = self.modalController;
    self.modalController = nil;

    if (!modalController) {
        if (completion) {
            completion();
        }

        return;
    }

    [self.currentController beginAppearanceTransition:YES animated:YES];

    UIView *childView = modalController.view;
    [modalController willMoveToParentViewController:nil];

    [UIView animateWithDuration:self.transitionAnimationDuration
        animations:^{
            childView.alpha = 0.0;

            [self setNeedsStatusBarAppearanceUpdate];
        }
        completion:^(BOOL finished) {
            [childView removeFromSuperview];
            [modalController removeFromParentViewController];

            [self.currentController endAppearanceTransition];

            if (completion) {
                completion();
            }
        }];
}

@end

NS_ASSUME_NONNULL_END
