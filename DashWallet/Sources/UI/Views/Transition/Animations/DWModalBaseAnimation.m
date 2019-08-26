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

#import "DWModalBaseAnimation.h"

#import "UISpringTimingParameters+DWInit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWModalBaseAnimation

- (instancetype)init {
    self = [super init];
    if (self) {
        UISpringTimingParameters *timingParameters =
            [[UISpringTimingParameters alloc] initWithDamping:0.8
                                                     response:0.4];
        UIViewPropertyAnimator *animator =
            [[UIViewPropertyAnimator alloc] initWithDuration:0.0
                                            timingParameters:timingParameters];

        _animator = animator;
    }
    return self;
}

- (UIViewPropertyAnimator *)animatorForTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    NSAssert(NO, @"Must be overriden");
    return self.animator;
}

#pragma mark - UIViewControllerAnimatedTransitioning

- (NSTimeInterval)transitionDuration:(nullable id<UIViewControllerContextTransitioning>)transitionContext {
    return self.animator.duration;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    // Since `-interruptibleAnimatorForTransition:` is implemented this could be a NOP
    UIViewPropertyAnimator *animator = [self animatorForTransition:transitionContext];
    [animator startAnimation];
}

- (id<UIViewImplicitlyAnimating>)interruptibleAnimatorForTransition:
    (id<UIViewControllerContextTransitioning>)transitionContext {
    return [self animatorForTransition:transitionContext];
}

- (void)animationEnded:(BOOL)transitionCompleted {
    // NOP
}

@end

NS_ASSUME_NONNULL_END
