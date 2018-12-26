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

#import "UIViewController+DWChildControllers.h"

#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ANIMATION_DURATION = 0.3;

@implementation UIViewController (DWChildControllers)

- (nullable UIViewController *)dw_currentChildController {
    return objc_getAssociatedObject(self, @selector(dw_currentChildController));
}

- (void)setDw_currentChildController:(nullable UIViewController *)dw_currentChildController {
    objc_setAssociatedObject(self, @selector(dw_currentChildController), dw_currentChildController, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dw_displayViewController:(UIViewController *)controller {
    NSParameterAssert(controller);

    [self addChildViewController:controller];
    controller.view.frame = self.view.bounds;
    controller.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:controller.view];
    [controller didMoveToParentViewController:self];

    self.dw_currentChildController = controller;
}

- (void)dw_performTransitionToViewController:(UIViewController *)toViewController
                                  completion:(void (^_Nullable)(BOOL finished))completion {
    UIViewController *fromViewController = self.dw_currentChildController;
    self.dw_currentChildController = toViewController;

    [fromViewController willMoveToParentViewController:nil];
    [self addChildViewController:toViewController];

    toViewController.view.frame = self.view.bounds;
    toViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    toViewController.view.alpha = 0.0;
    [self transitionFromViewController:fromViewController
        toViewController:toViewController
        duration:ANIMATION_DURATION
        options:0
        animations:^{
            toViewController.view.alpha = 1.0;
            fromViewController.view.alpha = 0.0;

            [self setNeedsStatusBarAppearanceUpdate];
        }
        completion:^(BOOL finished) {
            [fromViewController removeFromParentViewController];
            [toViewController didMoveToParentViewController:self];

            if (completion) {
                completion(finished);
            }
        }];
}

@end

NS_ASSUME_NONNULL_END
