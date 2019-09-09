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

#import "DWSuccessfulTransactionAnimatedIconView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const CIRCLE_LINE_WIDTH = 1.0;
static CGFloat const CHECKMARK_LINE_WIDTH = 2.0;

static UIBezierPath *CheckmarkBezierPath(void) {
    //
    //        3
    //  1
    //     2
    //
    UIBezierPath *bezierPath = [UIBezierPath bezierPath];
    [bezierPath moveToPoint:CGPointMake(13.0, 30.0)];    // 1
    [bezierPath addLineToPoint:CGPointMake(25.0, 40.0)]; // 2
    [bezierPath addLineToPoint:CGPointMake(44.0, 18.0)]; // 3

    return bezierPath;
}

static UIBezierPath *CircleBezierPath(CGSize size) {
    // Angles in the default coordinate system
    //
    //         3π/2
    //         *  *
    //      *      \ *
    //  π  *        | *  0, 2π
    //     *        v *
    //      *        *
    //         *  *
    //          π/2
    //
    const CGFloat startAngle = -M_PI / 4.0;
    const CGFloat endAngle = 2 * M_PI + startAngle;

    const CGPoint arcCenter = CGPointMake(size.width / 2.0, size.height / 2.0);
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:arcCenter
                                                        radius:arcCenter.x
                                                    startAngle:startAngle
                                                      endAngle:endAngle
                                                     clockwise:YES];

    return path;
}

@interface DWSuccessfulTransactionAnimatedIconView ()

@property (readonly, nonatomic, strong) CAShapeLayer *circleLayer;
@property (readonly, nonatomic, strong) CAShapeLayer *checkmarkLayer;

@end

@implementation DWSuccessfulTransactionAnimatedIconView

- (void)successTransactionAnimatedIconView_setup {
    if (self.circleLayer) {
        return;
    }

    self.backgroundColor = [UIColor dw_backgroundColor];

    const CGRect bounds = self.bounds;
    UIColor *color = [UIColor dw_dashBlueColor];
    const CGFloat rasterizationScale = [UIScreen mainScreen].scale;

    CAShapeLayer *circleLayer = [CAShapeLayer layer];
    circleLayer.frame = bounds;
    circleLayer.fillColor = nil;
    circleLayer.lineWidth = CIRCLE_LINE_WIDTH;
    circleLayer.lineCap = kCALineCapRound;
    circleLayer.strokeColor = color.CGColor;
    circleLayer.path = CircleBezierPath(bounds.size).CGPath;
    circleLayer.shouldRasterize = YES;
    circleLayer.rasterizationScale = rasterizationScale;
    [self.layer addSublayer:circleLayer];
    _circleLayer = circleLayer;

    CAShapeLayer *checkmarkLayer = [CAShapeLayer layer];
    checkmarkLayer.frame = bounds;
    checkmarkLayer.fillColor = nil;
    checkmarkLayer.lineWidth = CHECKMARK_LINE_WIDTH;
    checkmarkLayer.lineCap = kCALineCapRound;
    checkmarkLayer.lineJoin = kCALineJoinRound;
    checkmarkLayer.strokeColor = color.CGColor;
    checkmarkLayer.path = CheckmarkBezierPath().CGPath;
    checkmarkLayer.shouldRasterize = YES;
    checkmarkLayer.rasterizationScale = rasterizationScale;
    [self.layer addSublayer:checkmarkLayer];
    _checkmarkLayer = checkmarkLayer;
}

- (void)showAnimatedIfNeeded {
    if (self.circleLayer) {
        return;
    }

    [self successTransactionAnimatedIconView_setup];

    const CFTimeInterval circleDuration = 0.35;
    const CFTimeInterval checkmarkDuration = 0.3;

    CABasicAnimation *circleAnimation = [self strokeEndAnimation];
    circleAnimation.duration = circleDuration;
    [self.circleLayer addAnimation:circleAnimation forKey:@"dw_circle_animation"];

    CABasicAnimation *checkmarkAnimation = [self strokeEndAnimation];
    checkmarkAnimation.duration = checkmarkDuration;
    checkmarkAnimation.fillMode = kCAFillModeBackwards;
    checkmarkAnimation.beginTime = CACurrentMediaTime() + circleDuration / 3.0;
    [self.checkmarkLayer addAnimation:checkmarkAnimation forKey:@"dw_checkmark_animation"];
}

- (CABasicAnimation *)strokeEndAnimation {
    NSString *strokeEndKey = @"strokeEnd";
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:strokeEndKey];
    animation.fromValue = @0.0;
    animation.toValue = @1.0;
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    return animation;
}

@end

NS_ASSUME_NONNULL_END
