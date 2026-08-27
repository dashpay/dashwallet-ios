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

#import "DWExtendedContainerViewController+DWProtected.h"

#import "DWContainerViewController+DWProtected.h"
#import "UIView+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWExtendedContainerViewController

#pragma mark - Public

- (void)displayModalViewController:(UIViewController *)modalController completion:(void (^)(void))completion {
    NSParameterAssert(modalController);
    if (!modalController || self.modalController == modalController) {
        if (completion) {
            completion();
        }

        return;
    }

    self.modalController = modalController;

    [self.currentController beginAppearanceTransition:NO animated:YES];

    UIView *contentView = self.containerView;
    UIView *childView = modalController.view;

    [self addChildViewController:modalController];

    [contentView dw_embedSubview:childView];
    childView.preservesSuperviewLayoutMargins = YES;

    CGRect frame = contentView.bounds;
    frame.origin.y = CGRectGetHeight(frame);
    childView.frame = frame;

    [UIView animateWithDuration:self.transitionAnimationDuration
        delay:0.0
        usingSpringWithDamping:1.0
        initialSpringVelocity:0.0
        options:UIViewAnimationOptionCurveEaseInOut
        animations:^{
            childView.frame = contentView.bounds;

            [self setNeedsStatusBarAppearanceUpdate];
        }
        completion:^(BOOL finished) {
            [modalController didMoveToParentViewController:self];

            [self.currentController endAppearanceTransition];

            if (completion) {
                completion();
            }
        }];
}

- (void)hideModalControllerCompletion:(void (^)(void))completion {
    UIViewController *modalController = self.modalController;
    self.modalController = nil;

    if (!modalController) {
        if (completion) {
            completion();
        }

        return;
    }

    [self.currentController beginAppearanceTransition:YES
                                             animated:YES];

    UIView *childView = modalController.view;
    [modalController willMoveToParentViewController:nil];

    [UIView animateWithDuration:self.transitionAnimationDuration
        delay:0.0
        usingSpringWithDamping:1.0
        initialSpringVelocity:0.0
        options:UIViewAnimationOptionCurveEaseInOut
        animations:^{
            CGRect frame = childView.frame;
            frame.origin.y = CGRectGetHeight(frame);
            childView.frame = frame;

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

#pragma mark - Life Cycle

- (nullable UIViewController *)childViewControllerForStatusBarStyle {
    return self.modalController ?: self.currentController;
}

- (nullable UIViewController *)childViewControllerForStatusBarHidden {
    return self.modalController ?: self.currentController;
}

@end

NS_ASSUME_NONNULL_END
