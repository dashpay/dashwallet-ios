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

#import "DWDimmingView.h"

#import "DWAnimatableShapeLayer.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDimmingView ()

@property (readonly, strong, nonatomic) DWAnimatableShapeLayer *fillLayer;

@end

@implementation DWDimmingView

@synthesize dimmedPath = _dimmedPath;

+ (Class)layerClass {
    return [DWAnimatableShapeLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupDimmingView];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self setupDimmingView];
    }
    return self;
}

- (UIBezierPath *)dimmedPath {
    if (!_dimmedPath) {
        _dimmedPath = [UIBezierPath bezierPathWithRect:self.bounds];
    }
    return _dimmedPath;
}

- (void)setDimmedPath:(nullable UIBezierPath *)dimmedPath {
    _dimmedPath = dimmedPath;
    [self updateWithVisiblePath:self.visiblePath];
}

- (void)setVisiblePath:(nullable UIBezierPath *)visiblePath {
    _visiblePath = visiblePath;
    [self updateWithVisiblePath:visiblePath];
}

- (void)setDimmingColor:(UIColor *)dimmingColor {
    _dimmingColor = dimmingColor;
    [self updateWithVisiblePath:self.visiblePath];
}

- (void)setInverted:(BOOL)inverted {
    _inverted = inverted;
    [self updateWithVisiblePath:self.visiblePath];
}

#pragma mark - Private

- (DWAnimatableShapeLayer *)fillLayer {
    return (DWAnimatableShapeLayer *)self.layer;
}

- (void)setupDimmingView {
    _dimmingOpacity = 0.4;
    _dimmingColor = [UIColor blackColor];
    
    DWAnimatableShapeLayer *fillLayer = (DWAnimatableShapeLayer *)self.layer;
    fillLayer.fillRule = kCAFillRuleEvenOdd;
}

- (void)updateWithVisiblePath:(nullable UIBezierPath *)visiblePath {
    UIBezierPath *dimmedPath = nil;
    if (self.inverted) {
        dimmedPath = visiblePath;
    }
    else {
        dimmedPath = [UIBezierPath bezierPathWithCGPath:self.dimmedPath.CGPath];
        if (visiblePath) {
            visiblePath.usesEvenOddFillRule = YES;
            [dimmedPath appendPath:visiblePath];
        }
    }
    dimmedPath.usesEvenOddFillRule = YES;

    self.fillLayer.fillColor = self.dimmingColor.CGColor;
    self.fillLayer.opacity = self.dimmingOpacity;
    self.fillLayer.path = dimmedPath.CGPath;
}

@end

NS_ASSUME_NONNULL_END
