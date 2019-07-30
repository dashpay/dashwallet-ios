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

    UIView *toView = toViewController.view;
    UIView *fromView = fromViewController.view;

    [fromViewController willMoveToParentViewController:nil];
    [self addChildViewController:toViewController];

    toView.frame = self.view.bounds;
    toView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:toView];

    toView.alpha = 0.0;

    [UIView animateWithDuration:ANIMATION_DURATION
        delay:0.0
        usingSpringWithDamping:1.0
        initialSpringVelocity:0.0
        options:UIViewAnimationOptionCurveEaseInOut
        animations:^{
            toView.alpha = 1.0;
            fromView.alpha = 0.0;
        }
        completion:^(BOOL finished) {
            [fromView removeFromSuperview];
            [fromViewController removeFromParentViewController];
            [toViewController didMoveToParentViewController:self];
        }];
}

@end

NS_ASSUME_NONNULL_END
