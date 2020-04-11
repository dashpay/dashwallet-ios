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

#import "DWContainerViewController+DWProtected.h"

#import "UIView+DWEmbedding.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWContainerViewController

- (NSTimeInterval)transitionAnimationDuration {
    return 0.35;
}

- (UIView *)containerView {
    return self.view;
}

- (void)displayViewController:(UIViewController *)controller {
    NSParameterAssert(controller);
    if (!controller) {
        return;
    }

    [self dw_embedChild:controller inContainer:self.containerView];
    self.currentController = controller;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)transitionToViewController:(UIViewController *)toViewController
                          withType:(DWContainerTransitionType)transitionType {
    NSParameterAssert(toViewController);
    if (!toViewController) {
        return;
    }

    if (self.currentController == toViewController) {
        return;
    }

    UIViewController *fromViewController = self.childViewControllers.firstObject;
    NSAssert(fromViewController, @"To perform transition there should be child view controller. Use displayViewController: instead");
    if (!fromViewController) {
        [self displayViewController:toViewController];

        return;
    }

    UIView *toView = toViewController.view;
    UIView *fromView = fromViewController.view;
    UIView *contentView = self.containerView;

    self.currentController = toViewController;

    [fromViewController willMoveToParentViewController:nil];
    [self addChildViewController:toViewController];

    [contentView dw_embedSubview:toView];
    toView.preservesSuperviewLayoutMargins = YES;

    [self prepareForTransitionWithType:transitionType fromView:fromView toView:toView];

    [self animateTransitionWithType:transitionType
                           fromView:fromView
                             toView:toView
                         completion:^(BOOL finished) {
                             [fromView removeFromSuperview];
                             [fromViewController removeFromParentViewController];
                             [toViewController didMoveToParentViewController:self];
                         }];
}

#pragma mark - Life Cycle

- (nullable UIViewController *)childViewControllerForStatusBarStyle {
    return self.currentController;
}

- (nullable UIViewController *)childViewControllerForStatusBarHidden {
    return self.currentController;
}

#pragma mark - Private

- (void)prepareForTransitionWithType:(DWContainerTransitionType)transitionType
                            fromView:(UIView *)fromView
                              toView:(UIView *)toView {
    switch (transitionType) {
        case DWContainerTransitionType_WithoutAnimation: {
            // NOP

            break;
        }
        case DWContainerTransitionType_CrossDissolve: {
            toView.alpha = 0.0;

            break;
        }
        case DWContainerTransitionType_ScaleAndCrossDissolve: {
            toView.alpha = 0.0;
            toView.transform = CGAffineTransformMakeScale(1.25, 1.25);

            break;
        }
    }
}

- (void)animateTransitionWithType:(DWContainerTransitionType)transitionType
                         fromView:(UIView *)fromView
                           toView:(UIView *)toView
                       completion:(void (^__nullable)(BOOL finished))completion {
    void (^animationBlock)(void) = ^{
        toView.alpha = 1.0;
        toView.transform = CGAffineTransformIdentity;
        fromView.alpha = 0.0;

        [self setNeedsStatusBarAppearanceUpdate];
    };

    switch (transitionType) {
        case DWContainerTransitionType_WithoutAnimation: {
            animationBlock();
            completion(YES);

            break;
        }
        default: {
            [UIView animateWithDuration:self.transitionAnimationDuration
                                  delay:0.0
                 usingSpringWithDamping:1.0
                  initialSpringVelocity:0.0
                                options:UIViewAnimationOptionCurveEaseInOut
                             animations:animationBlock
                             completion:completion];

            break;
        }
    }
}

@end

NS_ASSUME_NONNULL_END
