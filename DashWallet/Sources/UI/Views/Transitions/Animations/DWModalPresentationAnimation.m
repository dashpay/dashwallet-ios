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

#import "DWModalPresentationAnimation.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWModalPresentationAnimation ()

@property (nonatomic, assign) BOOL animatorConfigured;

@end

@implementation DWModalPresentationAnimation

- (UIViewPropertyAnimator *)animatorForTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIViewPropertyAnimator *animator = self.animator;

    if (self.animatorConfigured) {
        return animator;
    }
    self.animatorConfigured = YES;

    UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];
    NSParameterAssert(toView);

    UIViewController *toViewController =
        [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    NSParameterAssert(toViewController);

    const CGRect finalFrame = [transitionContext finalFrameForViewController:toViewController];

    const CGFloat heightOffset = self.style == DWModalAnimationStyle_Default
                                     ? CGRectGetHeight(finalFrame)
                                     : CGRectGetHeight([UIScreen mainScreen].bounds);

    toView.frame = CGRectOffset(finalFrame, 0.0, heightOffset);

    [animator addAnimations:^{
        toView.frame = finalFrame;
    }];

    [animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
        [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
    }];

    return animator;
}

@end

NS_ASSUME_NONNULL_END
