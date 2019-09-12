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

#import "UIPanGestureRecognizer+DWProjected.h"

NS_ASSUME_NONNULL_BEGIN

// WWDC 2018 Session 803 (https://developer.apple.com/wwdc18/803)
static CGFloat Project(CGFloat initialVelocity, CGFloat decelerationRate) {
    return (initialVelocity / 1000.0) * decelerationRate / (1.0 - decelerationRate);
}

@implementation UIPanGestureRecognizer (DWProjected)

- (CGPoint)dw_projectedVelocity:(UIScrollViewDecelerationRate)scrollViewDecelerationRate {
    const CGPoint velocity = [self velocityInView:self.view];

    const CGPoint projected = CGPointMake(Project(velocity.x, scrollViewDecelerationRate),
                                          Project(velocity.y, scrollViewDecelerationRate));

    return projected;
}

- (CGPoint)dw_projectedLocation:(UIScrollViewDecelerationRate)scrollViewDecelerationRate {
    UIView *view = self.view;
    NSParameterAssert(view);
    if (!view) {
        return CGPointZero;
    }

    const CGPoint location = [self locationInView:view];
    const CGPoint velocity = [self dw_projectedVelocity:scrollViewDecelerationRate];

    const CGPoint projected = CGPointMake(location.x + velocity.x, location.y + velocity.y);

    return projected;
}

@end

NS_ASSUME_NONNULL_END
