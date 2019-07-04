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

@end

NS_ASSUME_NONNULL_END
