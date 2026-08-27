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

#import "DWProgressView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const PROGRESS_ANIMATION_KEY = @"DW_PROGRESS_ANIMATION_KEY";
static CFTimeInterval const DELAY_BETWEEN_PULSE = 4.0;

static CGPoint AnchorByProgress(float progress) {
    return CGPointMake(0.5 - progress, 0.5);
}

@interface DWProgressView ()

@property (nonatomic, strong) CALayer *greenLayer;
@property (nonatomic, strong) CALayer *blueLayer;
@property (nonatomic, assign) BOOL animating;

@end

@implementation DWProgressView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor dw_progressBackgroundColor];
    self.layer.masksToBounds = YES;

    CALayer *greenLayer = [CALayer layer];
    greenLayer.backgroundColor = [UIColor dw_greenColor].CGColor;
    [self.layer addSublayer:greenLayer];
    self.greenLayer = greenLayer;

    CALayer *blueLayer = [CALayer layer];
    blueLayer.backgroundColor = [UIColor dw_dashNavigationBlueColor].CGColor;
    [self.layer addSublayer:blueLayer];
    self.blueLayer = blueLayer;
}

- (void)layoutSublayersOfLayer:(CALayer *)layer {
    [super layoutSublayersOfLayer:layer];

    if (layer == self.layer) {
        self.greenLayer.frame = layer.bounds;
        self.blueLayer.frame = layer.bounds;
        const CGFloat x = CGRectGetWidth(layer.bounds) / 2.0;
        const CGFloat y = CGRectGetHeight(layer.bounds) / 2.0;
        // set 0 progress position
        self.greenLayer.position = CGPointMake(-x, y);
        self.blueLayer.position = CGPointMake(-x, y);
    }
}

- (void)setProgress:(float)progress {
    [self setProgress:progress animated:NO];
}

- (void)setProgress:(float)progress animated:(BOOL)animated {
    NSAssert(progress >= 0.0 && progress <= 1.0, @"Invalid progress");

    _progress = MAX(0.0, MIN(1.0, progress));

    // use implicit animation
    self.greenLayer.anchorPoint = AnchorByProgress(_progress);

    if (_progress == 1.0) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(progressAnimationIteration)
                                                   object:nil];
        self.animating = NO;
    }
    else if (_progress > 0.0 && !self.animating) {
        self.animating = YES;
        [self performSelector:@selector(progressAnimationIteration)
                   withObject:nil
                   afterDelay:DELAY_BETWEEN_PULSE];
    }
}

#pragma mark - Private

- (void)progressAnimationIteration {
    if (!self.animating) {
        [self.blueLayer removeAnimationForKey:PROGRESS_ANIMATION_KEY];

        return;
    }

    const CFTimeInterval anchorAnimationDuration = 0.4;
    const CFTimeInterval delayBeforeFadingOut = 0.4;
    const CFTimeInterval colorAnimationDuration = 1.0;

    CABasicAnimation *anchorAnimation = [CABasicAnimation animationWithKeyPath:@"anchorPoint"];
    anchorAnimation.fromValue = [NSValue valueWithCGPoint:AnchorByProgress(0.0)];
    anchorAnimation.toValue = [NSValue valueWithCGPoint:AnchorByProgress(self.progress)];
    anchorAnimation.duration = anchorAnimationDuration;
    anchorAnimation.beginTime = 0.0;
    anchorAnimation.removedOnCompletion = NO;
    anchorAnimation.fillMode = kCAFillModeForwards;
    anchorAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];

    CABasicAnimation *colorAnimation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    colorAnimation.fromValue = (id)[UIColor dw_dashNavigationBlueColor].CGColor;
    colorAnimation.toValue = (id)[UIColor dw_greenColor].CGColor;
    colorAnimation.duration = colorAnimationDuration;
    colorAnimation.beginTime = anchorAnimationDuration + delayBeforeFadingOut;
    colorAnimation.fillMode = kCAFillModeForwards;

    CAAnimationGroup *groupAnimation = [CAAnimationGroup animation];
    groupAnimation.animations = @[ anchorAnimation, colorAnimation ];
    groupAnimation.duration = anchorAnimationDuration +
                              delayBeforeFadingOut +
                              colorAnimationDuration +
                              DELAY_BETWEEN_PULSE;

    [self.blueLayer addAnimation:groupAnimation forKey:PROGRESS_ANIMATION_KEY];

    [self performSelector:@selector(progressAnimationIteration)
               withObject:nil
               afterDelay:DELAY_BETWEEN_PULSE];
}

@end

NS_ASSUME_NONNULL_END
