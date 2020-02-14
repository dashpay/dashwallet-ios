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

#import "DWPlanetarySystemView.h"

#pragma mark - Model

@implementation DWPlanetObject
@end

#pragma mark - View

static const CFTimeInterval ORBIT_ANIMATION_DURATION = 0.085;
static const CFTimeInterval ORBIT_ANIMATION_DELAY_BETWEEN = 0.25;

NS_ASSUME_NONNULL_BEGIN

@interface DWPlanetarySystemView ()

@property (strong, nonatomic) NSMutableArray<UIBezierPath *> *orbits;
@property (strong, nonatomic) NSMutableArray<CAShapeLayer *> *orbitLayers;
@property (strong, nonatomic) NSMutableArray<UIImageView *> *planetViews;

@end

NS_ASSUME_NONNULL_END

@implementation DWPlanetarySystemView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setNumberOfOrbits:(NSInteger)numberOfOrbits {
    _numberOfOrbits = numberOfOrbits;

    [self rebornTheUniverse];
}

- (void)setCenterOffset:(CGFloat)centerOffset {
    _centerOffset = centerOffset;

    [self rebornTheUniverse];
}

- (void)setBorderOffset:(CGFloat)borderOffset {
    _borderOffset = borderOffset;

    [self rebornTheUniverse];
}

- (void)setLineWidth:(CGFloat)lineWidth {
    _lineWidth = lineWidth;

    [self rebornTheUniverse];
}

- (void)setColors:(NSArray<UIColor *> *)colors {
    _colors = [colors copy];

    [self rebornTheUniverse];
}

- (void)setPlanets:(NSArray<DWPlanetObject *> *)planets {
    _planets = [planets copy];

    [self rebornTheUniverse];
}

- (void)showInitialAnimation {
    [self showOrbitsAnimated];

    const NSUInteger orbitsCount = self.orbits.count;
    // The actual delay is:
    // `orbitsCount * ORBIT_ANIMATION_DURATION + (orbitsCount - 1) * ORBIT_ANIMATION_DELAY_BETWEEN`
    // But we starting to show planets a bit before orbit animation is finished.
    const CFTimeInterval delay = orbitsCount * ORBIT_ANIMATION_DURATION;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self animatePlanetsWithRepeatCount:0.0];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [self rebornTheUniverse];
}

#pragma mark Private

- (void)setup {
    _colors = @[];
    _orbits = [NSMutableArray array];
    _orbitLayers = [NSMutableArray array];
    _planetViews = [NSMutableArray array];
}

- (void)showOrbitsAnimated {
    const CFTimeInterval duration = ORBIT_ANIMATION_DURATION;
    const CFTimeInterval delayBetween = ORBIT_ANIMATION_DELAY_BETWEEN;
    CFTimeInterval timeOffset = 0.0;
    for (CAShapeLayer *shapeLayer in self.orbitLayers) {
        NSString *keyPath = DW_KEYPATH(shapeLayer, opacity);
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:keyPath];
        animation.toValue = @1.0;
        animation.timeOffset = timeOffset;
        animation.duration = duration;
        [shapeLayer addAnimation:animation forKey:@"dw_orbit_animation"];
        shapeLayer.opacity = 1.0;
        timeOffset += duration + delayBetween;
    }
}

- (void)animatePlanetsWithRepeatCount:(float)repeatCount {
    if (self.planets.count != self.planetViews.count) {
        [self rebornTheUniverse];
    }

    for (NSInteger i = 0; i < self.planets.count; i++) {
        DWPlanetObject *planet = self.planets[i];
        UIImageView *planetView = self.planetViews[i];

        NSAssert(planet.orbit < self.orbits.count, @"Internal inconsistency");
        UIBezierPath *path = self.orbits[planet.orbit];

        // start off fading in when 1/3 of the rotation is completed
        const CFTimeInterval opacityBeginTime = planet.duration / planet.speed / 3.0;

        NSString *keyPath = DW_KEYPATH(planetView.layer, opacity);
        CABasicAnimation *opacityAnimation = [CABasicAnimation animationWithKeyPath:keyPath];
        opacityAnimation.toValue = @1.0;
        opacityAnimation.duration = planet.duration;
        opacityAnimation.beginTime = opacityBeginTime;
        opacityAnimation.removedOnCompletion = NO;
        opacityAnimation.fillMode = kCAFillModeForwards;

        keyPath = DW_KEYPATH(planetView.layer, position);
        CAKeyframeAnimation *positionAnimation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
        positionAnimation.path = path.CGPath;
        positionAnimation.repeatCount = repeatCount;
        positionAnimation.calculationMode = kCAAnimationPaced;
        positionAnimation.removedOnCompletion = NO;
        positionAnimation.fillMode = kCAFillModeForwards;
        positionAnimation.speed = (planet.rotateClockwise ? -1.0 : 1.0);
        positionAnimation.timeOffset = planet.duration * planet.offset;
        positionAnimation.duration = planet.duration;

        CAAnimationGroup *animation = [CAAnimationGroup animation];
        animation.animations = @[ opacityAnimation, positionAnimation ];
        animation.speed = planet.speed;
        animation.duration = opacityBeginTime + planet.duration;
        animation.removedOnCompletion = NO;
        animation.fillMode = kCAFillModeForwards;
        [planetView.layer addAnimation:animation forKey:@"dw_planet_animation"];
    }
}

/// big bang!
- (void)rebornTheUniverse {
    [self.orbits removeAllObjects];

    [self.orbitLayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [self.orbitLayers removeAllObjects];

    [self.planetViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self.planetViews removeAllObjects];

    if (self.numberOfOrbits == 0 || self.numberOfOrbits != self.colors.count || self.planets.count == 0) {
        return;
    }

    const CGSize size = self.bounds.size;
    const CGPoint center = CGPointMake(size.width / 2.0, size.height / 2.0);
    const CGFloat radius = MIN(size.width, size.height) / self.numberOfOrbits / 2.0 - self.borderOffset;

    for (NSInteger i = 0; i < self.numberOfOrbits; i++) {
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                            radius:radius * i + self.centerOffset
                                                        startAngle:0.0
                                                          endAngle:M_PI * 2.0
                                                         clockwise:NO];
        CAShapeLayer *shapeLayer = [CAShapeLayer layer];
        shapeLayer.path = path.CGPath;
        shapeLayer.frame = self.bounds;
        shapeLayer.strokeColor = self.colors[i].CGColor;
        shapeLayer.lineWidth = self.lineWidth;
        shapeLayer.fillColor = [UIColor clearColor].CGColor;
        shapeLayer.opacity = 0.0; // initially hidden
        [self.layer addSublayer:shapeLayer];

        [self.orbits addObject:path];
        [self.orbitLayers addObject:shapeLayer];
    }

    for (DWPlanetObject *planet in self.planets) {
        const CGRect rect = CGRectMake(-planet.size.width * 0.5, -planet.size.height * 0.5,
                                       planet.size.width, planet.size.height);
        UIImageView *planetView = [[UIImageView alloc] initWithFrame:rect];
        planetView.image = planet.image;
        planetView.layer.opacity = 0.0; // initially hidden
        [self addSubview:planetView];

        [self.planetViews addObject:planetView];
    }
}

@end
