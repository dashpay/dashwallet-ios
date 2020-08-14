//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWDashPayAnimationView.h"

#import "CALayer+MBAnimationPersistence.h"
#import "DWAnimatedShapeLayer.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIBezierPath *LeftSidePath(void) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(0, 12)];
    [path addLineToPoint:CGPointMake(22, 23)];
    [path addLineToPoint:CGPointMake(22, 41)];
    [path addLineToPoint:CGPointMake(22, 45)];
    [path addLineToPoint:CGPointMake(0, 34)];
    [path addLineToPoint:CGPointMake(0, 12)];
    [path closePath];
    return path;
}

static UIBezierPath *TopSidePath(void) {
    UIBezierPath *bezierPath = [UIBezierPath bezierPath];
    [bezierPath moveToPoint:CGPointMake(0.5, 11)];
    [bezierPath addLineToPoint:CGPointMake(22.5, 0)];
    [bezierPath addLineToPoint:CGPointMake(44.5, 11)];
    [bezierPath addLineToPoint:CGPointMake(22.5, 22)];
    [bezierPath addLineToPoint:CGPointMake(0.5, 11)];
    [bezierPath closePath];
    return bezierPath;
}

static UIBezierPath *RightSidePath(void) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(45, 12)];
    [path addLineToPoint:CGPointMake(23, 23)];
    [path addLineToPoint:CGPointMake(23, 41)];
    [path addLineToPoint:CGPointMake(23, 45)];
    [path addLineToPoint:CGPointMake(45, 34)];
    [path addLineToPoint:CGPointMake(45, 12)];
    [path closePath];
    return path;
}

static CGFloat const SHIFT = 20.0;
static CGFloat const SCALE = 0.1;

static CATransform3D LeftSideTransform(void) {
    return CATransform3DScale(CATransform3DMakeTranslation(-SHIFT, SHIFT, 0), SCALE, SCALE, SCALE);
}

static CATransform3D RightSideTransform(void) {
    return CATransform3DScale(CATransform3DMakeTranslation(SHIFT, SHIFT, 0), SCALE, SCALE, SCALE);
}

static CATransform3D TopSideTransform(void) {
    return CATransform3DScale(CATransform3DMakeTranslation(0, -SHIFT, 0), SCALE, SCALE, SCALE);
}

@interface DWDashPayAnimationView ()

@property (readonly, strong, nonatomic) DWAnimatedShapeLayer *leftSideLayer;
@property (readonly, strong, nonatomic) DWAnimatedShapeLayer *topSideLayer;
@property (readonly, strong, nonatomic) DWAnimatedShapeLayer *rightSideLayer;

@property (readonly, nonatomic, strong) CALayer *leftHeadLayer;
@property (readonly, nonatomic, strong) CALayer *leftBodyLayer;
@property (readonly, nonatomic, strong) CALayer *rightHeadLayer;
@property (readonly, nonatomic, strong) CALayer *rightBodyLayer;

@end

NS_ASSUME_NONNULL_END

@implementation DWDashPayAnimationView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)layoutSublayersOfLayer:(CALayer *)layer {
    [super layoutSublayersOfLayer:layer];

    if (self.layer == layer) {
        const CGRect frame = self.layer.bounds;
        self.leftSideLayer.frame = frame;
        self.rightSideLayer.frame = frame;
        self.topSideLayer.frame = frame;

        const CGSize size = frame.size;
        const CGSize headSize = CGSizeMake(6, 6);
        const CGSize bodySize = CGSizeMake(12, 4);
        const CGFloat spacing = 1.0;

        CGFloat y = (size.height - headSize.height - spacing - bodySize.height) / 2.0;
        const CGRect headFrame = CGRectMake((size.width - headSize.width) / 2.0, y, headSize.width, headSize.height);
        y += spacing + headSize.height;
        const CGRect bodyFrame = CGRectMake((size.width - bodySize.width) / 2.0, y, bodySize.width, bodySize.height);

        self.leftHeadLayer.frame = headFrame;
        self.leftBodyLayer.frame = bodyFrame;
        self.rightHeadLayer.frame = headFrame;
        self.rightBodyLayer.frame = bodyFrame;

        const CGFloat userpicShift = 12;
        CATransform3D leftTransform = CATransform3DMakeTranslation(-userpicShift, 0, 0);
        leftTransform = CATransform3DRotate(leftTransform, -M_PI_4, 0, 1, 0);
        leftTransform = CATransform3DRotate(leftTransform, 20 * M_PI / 180.0, 0, 0, 1);
        self.leftHeadLayer.transform = leftTransform;
        self.leftBodyLayer.transform = leftTransform;

        CATransform3D rightTransform = CATransform3DMakeTranslation(userpicShift, 0, 0);
        rightTransform = CATransform3DRotate(rightTransform, M_PI_4, 0, 1, 0);
        rightTransform = CATransform3DRotate(rightTransform, -20 * M_PI / 180.0, 0, 0, 1);
        self.rightHeadLayer.transform = rightTransform;
        self.rightBodyLayer.transform = rightTransform;
    }
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(45, 56);
}

- (void)startAnimating {
    [self stopAllAnimations];
    [self startAllAnimations];
}

- (void)stopAnimating {
    [self stopAllAnimations];
}

#pragma mark - Private

- (void)setupView {
    DWAnimatedShapeLayer *leftSideLayer = [DWAnimatedShapeLayer layer];
    leftSideLayer.fillColor = [UIColor dw_darkBlueColor].CGColor;
    leftSideLayer.path = LeftSidePath().CGPath;
    leftSideLayer.opacity = 0;
    leftSideLayer.transform = LeftSideTransform();
    [self.layer addSublayer:leftSideLayer];
    _leftSideLayer = leftSideLayer;

    DWAnimatedShapeLayer *rightSideLayer = [DWAnimatedShapeLayer layer];
    rightSideLayer.fillColor = [UIColor dw_darkBlueColor].CGColor;
    rightSideLayer.path = RightSidePath().CGPath;
    rightSideLayer.opacity = 0;
    rightSideLayer.transform = RightSideTransform();
    [self.layer addSublayer:rightSideLayer];
    _rightSideLayer = rightSideLayer;

    DWAnimatedShapeLayer *topSideLayer = [DWAnimatedShapeLayer layer];
    topSideLayer.fillColor = [UIColor colorWithRed:166.0 / 255.0 green:215.0 / 255.0 blue:245.0 / 255.0 alpha:1.0].CGColor;
    topSideLayer.path = TopSidePath().CGPath;
    topSideLayer.opacity = 0;
    topSideLayer.transform = TopSideTransform();
    [self.layer addSublayer:topSideLayer];
    _topSideLayer = topSideLayer;

    UIImage *headImage = [UIImage imageNamed:@"dp_animation_head"];
    CALayer *leftHeadLayer = [CALayer layer];
    leftHeadLayer.contents = (id)headImage.CGImage;
    leftHeadLayer.zPosition = 10;
    leftHeadLayer.opacity = 0;
    [self.layer addSublayer:leftHeadLayer];
    _leftHeadLayer = leftHeadLayer;

    UIImage *bodyImage = [UIImage imageNamed:@"dp_animation_body"];
    CALayer *leftBodyLayer = [CALayer layer];
    leftBodyLayer.contents = (id)bodyImage.CGImage;
    leftBodyLayer.zPosition = 10;
    leftBodyLayer.opacity = 0;
    [self.layer addSublayer:leftBodyLayer];
    _leftBodyLayer = leftBodyLayer;

    CALayer *rightHeadLayer = [CALayer layer];
    rightHeadLayer.contents = (id)headImage.CGImage;
    rightHeadLayer.zPosition = 10;
    rightHeadLayer.opacity = 0;
    [self.layer addSublayer:rightHeadLayer];
    _rightHeadLayer = rightHeadLayer;

    CALayer *rightBodyLayer = [CALayer layer];
    rightBodyLayer.contents = (id)bodyImage.CGImage;
    rightBodyLayer.zPosition = 10;
    rightBodyLayer.opacity = 0;
    [self.layer addSublayer:rightBodyLayer];
    _rightBodyLayer = rightBodyLayer;
}

- (void)stopAllAnimations {
    NSArray<CALayer *> *layers = @[ self.leftSideLayer, self.rightSideLayer, self.topSideLayer ];
    [layers makeObjectsPerformSelector:@selector(removeAllAnimations)];

    NSArray<CALayer *> *usersLayers = @[ self.leftHeadLayer, self.leftBodyLayer, self.rightHeadLayer, self.rightBodyLayer ];
    [usersLayers makeObjectsPerformSelector:@selector(removeAllAnimations)];
}

- (void)startAllAnimations {
    NSArray<CALayer *> *layers = @[ self.leftSideLayer, self.rightSideLayer, self.topSideLayer ];
    NSArray<NSValue *> *transforms = @[ @(LeftSideTransform()), @(RightSideTransform()), @(TopSideTransform()) ];
    NSAssert(layers.count == transforms.count, @"Internal inconsistency");
    const NSUInteger count = layers.count;

    [layers makeObjectsPerformSelector:@selector(removeAllAnimations)];

    NSValue *identityTransform = @(CATransform3DIdentity);

    const CFTimeInterval step = 0.4;

    const CFTimeInterval wait = step * count;

    for (NSInteger i = 0; i < count; i++) {
        CALayer *layer = layers[i];
        NSValue *transform = transforms[i];
        [self animateCubeSide:i identityTransform:identityTransform layer:layer step:step transform:transform wait:wait];
    }

    NSArray<CALayer *> *usersLayers = @[ self.leftHeadLayer, self.leftBodyLayer, self.rightHeadLayer, self.rightBodyLayer ];
    [usersLayers makeObjectsPerformSelector:@selector(removeAllAnimations)];

    const CFTimeInterval halfStep = step / 2.0;
    const CFTimeInterval totalDuration = step * 8; // 1 (show) + 3 (wait) + 1 (hide) + 3 (wait)

    [self animateUserpic:self.leftHeadLayer step:step beginTime:step totalDuration:totalDuration];
    [self animateUserpic:self.leftBodyLayer step:step beginTime:step + halfStep totalDuration:totalDuration];
    [self animateUserpic:self.rightHeadLayer step:step beginTime:step * 2 totalDuration:totalDuration];
    [self animateUserpic:self.rightBodyLayer step:step beginTime:step * 2 + halfStep totalDuration:totalDuration];
}

- (void)animateCubeSide:(NSInteger)i
      identityTransform:(NSValue *)identityTransform
                  layer:(CALayer *)layer
                   step:(CFTimeInterval)step
              transform:(NSValue *)transform
                   wait:(CFTimeInterval)wait {
    CABasicAnimation *opacity1 = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity1.fromValue = @0;
    opacity1.toValue = @1;
    opacity1.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    opacity1.duration = step;

    CABasicAnimation *transform1 = [CABasicAnimation animationWithKeyPath:@"transform"];
    transform1.toValue = identityTransform;
    transform1.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    transform1.duration = step;

    CABasicAnimation *opacity2 = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity2.fromValue = @1;
    opacity2.toValue = @1;
    opacity2.duration = wait;
    opacity2.beginTime = opacity1.duration;

    CABasicAnimation *transform2 = [CABasicAnimation animationWithKeyPath:@"transform"];
    transform2.fromValue = identityTransform;
    transform2.toValue = identityTransform;
    transform2.duration = wait;
    transform2.beginTime = transform1.duration;

    CABasicAnimation *opacity3 = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity3.fromValue = @1;
    opacity3.toValue = @0;
    opacity3.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    opacity3.duration = step;
    opacity3.beginTime = opacity2.beginTime + opacity2.duration;

    CABasicAnimation *transform3 = [CABasicAnimation animationWithKeyPath:@"transform"];
    transform3.fromValue = identityTransform;
    transform3.toValue = transform;
    transform3.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    transform3.duration = step;
    transform3.beginTime = transform2.beginTime + transform2.duration;

    CABasicAnimation *opacity4 = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity4.fromValue = @0;
    opacity4.toValue = @0;
    opacity4.duration = wait;
    opacity4.beginTime = opacity3.beginTime + opacity3.duration;

    CABasicAnimation *transform4 = [CABasicAnimation animationWithKeyPath:@"transform"];
    transform4.fromValue = transform;
    transform4.toValue = transform;
    transform4.duration = wait;
    transform4.beginTime = transform3.beginTime + transform3.duration;

    NSAssert((opacity4.beginTime + opacity4.duration) == (transform4.beginTime + transform4.duration),
             @"Invalid animation");

    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[ opacity1, transform1, opacity2, transform2, opacity3, transform3, opacity4, transform4 ];
    group.beginTime = CACurrentMediaTime() + i * step;
    group.duration = opacity4.beginTime + opacity4.duration;
    group.repeatCount = HUGE_VALF;

    [layer addAnimation:group forKey:@"dw_dp_layer_group"];
    [layer MB_setCurrentAnimationsPersistent];
}

- (void)animateUserpic:(CALayer *)layer
                  step:(CFTimeInterval)step
             beginTime:(CFTimeInterval)beginTime
         totalDuration:(CFTimeInterval)totalDuration {
    const CFTimeInterval halfStep = step / 2.0;

    CABasicAnimation *opacity_s = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity_s.fromValue = @0;
    opacity_s.toValue = @1;
    opacity_s.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    opacity_s.duration = halfStep;

    CABasicAnimation *opacity_sw = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity_sw.fromValue = @1;
    opacity_sw.toValue = @1;
    opacity_sw.duration = step * 2;
    opacity_sw.beginTime = opacity_s.beginTime + opacity_s.duration;

    CABasicAnimation *opacity_h = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity_h.fromValue = @1;
    opacity_h.toValue = @0;
    opacity_h.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    opacity_h.duration = halfStep;
    opacity_h.beginTime = opacity_sw.beginTime + opacity_sw.duration;

    CABasicAnimation *opacity_hw = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity_hw.fromValue = @0;
    opacity_hw.toValue = @0;
    opacity_hw.duration = totalDuration - (opacity_h.beginTime + opacity_h.duration);
    opacity_hw.beginTime = opacity_h.beginTime + opacity_h.duration;

    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[ opacity_s, opacity_sw, opacity_h, opacity_hw ];
    group.beginTime = CACurrentMediaTime() + beginTime;
    group.duration = totalDuration;
    group.repeatCount = HUGE_VALF;

    [layer addAnimation:group forKey:@"dw_dp_user_animation"];
    [layer MB_setCurrentAnimationsPersistent];
}

@end
