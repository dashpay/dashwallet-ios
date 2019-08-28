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

#import "DWModalChevronView.h"

#import "DWAnimatableShapeLayer.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static DWAnimatableShapeLayer *SegmentLayer(void) {
    DWAnimatableShapeLayer *layer = [DWAnimatableShapeLayer layer];
    layer.strokeColor = [UIColor dw_chevronColor].CGColor;
    layer.fillColor = [UIColor yellowColor].CGColor;
    layer.lineWidth = 3.0;
    layer.lineCap = kCALineCapRound;
    layer.lineJoin = kCALineJoinRound;

    return layer;
}

// Bezier paths in (0, 0) coordinates

static UIBezierPath *VFirstSegment(void) {
    UIBezierPath *bezierPath = [UIBezierPath bezierPath];
    [bezierPath moveToPoint:CGPointMake(0, 0)];
    [bezierPath addLineToPoint:CGPointMake(15, 10.5)];

    return bezierPath;
}

static UIBezierPath *VSecondSegment(void) {
    UIBezierPath *bezierPath = [UIBezierPath bezierPath];
    [bezierPath moveToPoint:CGPointMake(15, 10.5)];
    [bezierPath addLineToPoint:CGPointMake(30, 0)];

    return bezierPath;
}

static UIBezierPath *LineFirstSegment(void) {
    UIBezierPath *bezierPath = [UIBezierPath bezierPath];
    [bezierPath moveToPoint:CGPointMake(0, 0)];
    [bezierPath addLineToPoint:CGPointMake(15, 0)];

    return bezierPath;
}

static UIBezierPath *LineSecondSegment(void) {
    UIBezierPath *bezierPath = [UIBezierPath bezierPath];
    [bezierPath moveToPoint:CGPointMake(15, 0)];
    [bezierPath addLineToPoint:CGPointMake(30, 0)];

    return bezierPath;
}

@interface DWModalChevronView ()

@property (readonly, strong, nonatomic) DWAnimatableShapeLayer *firstSegmentLayer;
@property (readonly, strong, nonatomic) DWAnimatableShapeLayer *secondSegmentLayer;

@end

@implementation DWModalChevronView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self chevronView_setup];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self chevronView_setup];
    }
    return self;
}

- (void)chevronView_setup {
    self.backgroundColor = [UIColor dw_backgroundColor];

    DWAnimatableShapeLayer *firstSegmentLayer = SegmentLayer();
    [self.layer addSublayer:firstSegmentLayer];
    _firstSegmentLayer = firstSegmentLayer;

    DWAnimatableShapeLayer *secondSegmentLayer = SegmentLayer();
    [self.layer addSublayer:secondSegmentLayer];
    _secondSegmentLayer = secondSegmentLayer;

    // Initial state
    firstSegmentLayer.path = VFirstSegment().CGPath;
    secondSegmentLayer.path = VSecondSegment().CGPath;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.firstSegmentLayer.frame = self.bounds;
    self.secondSegmentLayer.frame = self.bounds;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(30.0, 12.0);
}

- (void)setFlattened:(BOOL)flattened {
    _flattened = flattened;

    if (flattened) {
        [self animateLayer:self.firstSegmentLayer toPath:LineFirstSegment() isSecond:NO];
        [self animateLayer:self.secondSegmentLayer toPath:LineSecondSegment() isSecond:YES];
    }
    else {
        [self animateLayer:self.firstSegmentLayer toPath:VFirstSegment() isSecond:NO];
        [self animateLayer:self.secondSegmentLayer toPath:VSecondSegment() isSecond:YES];
    }
}

- (void)animateLayer:(DWAnimatableShapeLayer *)layer toPath:(UIBezierPath *)path isSecond:(BOOL)isSecond {
    NSString *const pathKey = @"path";
    const CFTimeInterval pathDuration = 0.1;

    CGPathRef pathRef = path.CGPath;

    CABasicAnimation *pathAnimation = [CABasicAnimation animationWithKeyPath:pathKey];
    pathAnimation.fromValue = [layer.presentationLayer valueForKey:pathKey];
    pathAnimation.toValue = (id)path.CGPath;
    pathAnimation.duration = pathDuration;
    pathAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];

    layer.path = pathRef;
    [layer removeAllAnimations]; // prevent chevron from springing when presentation/dismissal animation still in flight
    [layer addAnimation:pathAnimation forKey:@"dw_segment_animation"];
}

@end

NS_ASSUME_NONNULL_END
