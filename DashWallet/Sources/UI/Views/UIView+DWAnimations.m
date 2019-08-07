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

#import "UIView+DWAnimations.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIView (DWAnimations)

- (void)dw_shakeViewWithCompletion:(void (^)(void))completion {
    NSParameterAssert(completion);
    if (!completion) {
        return;
    }

    [CATransaction begin];
    [CATransaction setCompletionBlock:completion];

    [self dw_shakeView];

    [CATransaction commit];
}

- (void)dw_shakeView {
    CAKeyframeAnimation *shakeAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shakeAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    shakeAnimation.duration = 0.5;
    shakeAnimation.values = @[ @(-24), @(24), @(-16), @(16), @(-8), @(8), @(-4), @(4), @(0) ];
    [self.layer addAnimation:shakeAnimation forKey:@"DWShakeAnimation"];
}

- (void)dw_pressedAnimation:(DWPressedAnimationStrength)strength pressed:(BOOL)pressed {
    CGAffineTransform transform;
    if (pressed) {
        CGFloat scale;
        switch (strength) {
            case DWPressedAnimationStrength_Heavy:
                scale = 0.93;
                break;
            case DWPressedAnimationStrength_Medium:
                scale = 0.95;
                break;
            case DWPressedAnimationStrength_Light:
                scale = 0.97;
                break;
        }
        transform = CGAffineTransformMakeScale(scale, scale);
    }
    else {
        transform = CGAffineTransformIdentity;
    }

    const UIViewAnimationOptions options =
        (UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction);

    [UIView animateWithDuration:0.4
                          delay:0.0
         usingSpringWithDamping:0.5
          initialSpringVelocity:1.0
                        options:options
                     animations:^{
                         self.transform = transform;
                     }
                     completion:nil];
}

@end

NS_ASSUME_NONNULL_END
