//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWAlertViewController.h"

#import "DWAlertDismissalAnimationController.h"
#import "DWAlertPresentationAnimationController.h"
#import "DWAlertPresentationController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWAlertViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self setupAlertController];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self setupAlertController];
    }
    return self;
}

- (void)setupAlertController {
    self.modalPresentationStyle = UIModalPresentationCustom;
    self.transitioningDelegate = self;
    self.shouldDimBackground = YES;
}

#pragma mark - UIViewControllerTransitioningDelegate

- (nullable id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                           presentingController:(UIViewController *)presenting
                                                                               sourceController:(UIViewController *)source {
    DWAlertPresentationAnimationController *animationController = [[DWAlertPresentationAnimationController alloc] init];
    return animationController;
}

- (nullable id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    DWAlertDismissalAnimationController *animationController = [[DWAlertDismissalAnimationController alloc] init];
    return animationController;
}

- (nullable UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented
                                                               presentingViewController:(nullable UIViewController *)presenting
                                                                   sourceViewController:(UIViewController *)source {
    DWAlertPresentationController *presentationController = [[DWAlertPresentationController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
    presentationController.shouldDimBackground = self.shouldDimBackground;
    return presentationController;
}

@end

NS_ASSUME_NONNULL_END
