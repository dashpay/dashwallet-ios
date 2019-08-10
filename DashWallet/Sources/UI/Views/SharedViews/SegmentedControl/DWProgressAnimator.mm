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

#import "DWProgressAnimator.h"

#import "DWUnitBezier.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *TimingFunctionForAnimationCurve(UIViewAnimationCurve curve) {
    switch (curve) {
        case UIViewAnimationCurveEaseInOut:
            return kCAMediaTimingFunctionEaseInEaseOut;
        case UIViewAnimationCurveEaseIn:
            return kCAMediaTimingFunctionEaseIn;
        case UIViewAnimationCurveEaseOut:
            return kCAMediaTimingFunctionEaseOut;
        case UIViewAnimationCurveLinear:
            return kCAMediaTimingFunctionLinear;
    }
    return kCAMediaTimingFunctionEaseInEaseOut;
}

static double SolveBezier(struct dwblink::DWUnitBezier unitBezier, double progress) {
    return unitBezier.solve(progress, DBL_EPSILON);
}

@interface DWProgressAnimator ()

@property (nullable, nonatomic, strong) CADisplayLink *displayLink;

@property (nullable, nonatomic, copy) CGFloat (^curveBlock)(CGFloat progress);
@property (nullable, nonatomic, copy) void (^animations)(CGFloat);
@property (nullable, nonatomic, copy) void (^completion)(BOOL);

@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) NSTimeInterval delay;
@property (nonatomic, assign) CFTimeInterval initialTimestamp;

@end


@implementation DWProgressAnimator

- (void)dealloc {
    [self invalidateFinished:NO];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (^)(CGFloat progress))animations {
    [self animateWithDuration:duration animations:animations completion:nil];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (^)(CGFloat progress))animations
                 completion:(void (^_Nullable)(BOOL finished))completion {
    [self animateWithDuration:duration
                        delay:0.0
                        curve:UIViewAnimationCurveEaseInOut
                   animations:animations
                   completion:completion];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                      delay:(NSTimeInterval)delay
                      curve:(UIViewAnimationCurve)curve
                 animations:(void (^)(CGFloat progress))animations
                 completion:(void (^_Nullable)(BOOL finished))completion {
    NSString *timingFunctionName = TimingFunctionForAnimationCurve(curve);
    CAMediaTimingFunction *timingFunction = [CAMediaTimingFunction functionWithName:timingFunctionName];
    float value[4] = {};
    [timingFunction getControlPointAtIndex:1 values:&value[0]];
    [timingFunction getControlPointAtIndex:2 values:&value[2]];

    dwblink::DWUnitBezier unitBezier(value[1], value[1], value[2], value[3]);

    [self animateWithDuration:duration
                        delay:delay
                   curveBlock:^CGFloat(CGFloat progress) {
                       return SolveBezier(unitBezier, progress);
                   }
                   animations:animations
                   completion:completion];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                      delay:(NSTimeInterval)delay
                 curveBlock:(CGFloat (^)(CGFloat progress))curveBlock
                 animations:(void (^)(CGFloat progress))animations
                 completion:(void (^_Nullable)(BOOL finished))completion {
    self.duration = duration;
    self.delay = delay;
    self.curveBlock = curveBlock;
    self.animations = animations;
    self.completion = completion;
    self.initialTimestamp = 0.0;

    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkAction:)];
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)invalidate {
    [self invalidateFinished:NO];
}

#pragma mark - Private

- (void)displayLinkAction:(CADisplayLink *)displayLink {
    if (self.initialTimestamp == 0.0) {
        self.initialTimestamp = displayLink.timestamp;
    }

    const CGFloat timingValue = (self.duration == 0.0)
                                    ? 1.0
                                    : MAX(0.0, MIN(1.0, ((displayLink.timestamp - self.initialTimestamp) - self.delay) / self.duration));
    if (timingValue == 0.0 || !self.animations) {
        return;
    }

    const CGFloat progress = self.curveBlock(timingValue);
    self.animations(progress);

    if (timingValue == 1.0) {
        [self invalidateFinished:YES];
    }
}

- (void)invalidateFinished:(BOOL)finished {
    [self.displayLink invalidate];
    self.displayLink = nil;

    if (self.completion) {
        void (^completion)(BOOL) = self.completion;
        self.completion = nil;
        self.animations = nil;
        completion(finished);
    }
}


@end

NS_ASSUME_NONNULL_END
