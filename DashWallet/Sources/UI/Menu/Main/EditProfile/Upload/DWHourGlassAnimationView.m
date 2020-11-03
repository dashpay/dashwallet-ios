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

#import "DWHourGlassAnimationView.h"

NS_ASSUME_NONNULL_BEGIN

static CFTimeInterval const Step = 1.5;

@interface DWHourGlassAnimationView ()

@property (readonly, nonatomic, strong) CALayer *hgLayer;
@property (nonatomic, assign) BOOL animating;

@end

NS_ASSUME_NONNULL_END

@implementation DWHourGlassAnimationView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CALayer *hgLayer = [CALayer layer];
        hgLayer.contentsGravity = kCAGravityResizeAspect;
        [self.layer addSublayer:hgLayer];
        _hgLayer = hgLayer;
    }
    return self;
}

- (void)startAnimating {
    if (self.animating) {
        return;
    }
    self.animating = YES;

    self.hgLayer.contents = nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self performOneStep];
    });
}

- (void)stopAnimating {
    self.animating = NO;
    [self.hgLayer removeAllAnimations];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGSize size = self.bounds.size;
    CGSize hgsize = CGSizeMake(18, 24);
    self.hgLayer.frame = CGRectMake((size.width - hgsize.width) / 2, (size.height - hgsize.height) / 2, hgsize.width, hgsize.height);
}

- (void)performOneStep {
    CFTimeInterval subStep = 0.3;

    CAKeyframeAnimation *keyframeAnimation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
    keyframeAnimation.values = @[
        (id)[UIImage imageNamed:@"hourglass_1"].CGImage,
        (id)[UIImage imageNamed:@"hourglass_2"].CGImage,
        (id)[UIImage imageNamed:@"hourglass_3"].CGImage,
        (id)[UIImage imageNamed:@"hourglass_4"].CGImage,
        (id)[UIImage imageNamed:@"hourglass_5"].CGImage,
    ];
    keyframeAnimation.duration = Step;

    CABasicAnimation *lastValueAnimation = [CABasicAnimation animationWithKeyPath:@"contents"];
    lastValueAnimation.toValue = (id)[UIImage imageNamed:@"hourglass_5"].CGImage;
    lastValueAnimation.beginTime = Step;
    lastValueAnimation.duration = subStep * 2;

    CABasicAnimation *rotationAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimation.toValue = @(M_PI);
    rotationAnimation.duration = subStep * 2;
    rotationAnimation.beginTime = Step + subStep;

    CAAnimationGroup *groupAnimation = [CAAnimationGroup animation];
    groupAnimation.animations = @[ keyframeAnimation, lastValueAnimation, rotationAnimation ];
    groupAnimation.duration = Step + subStep * 3;
    groupAnimation.beginTime = CACurrentMediaTime();
    groupAnimation.repeatCount = HUGE_VALF;
    groupAnimation.removedOnCompletion = NO;

    [self.hgLayer addAnimation:groupAnimation forKey:@"hg_animation"];
    self.hgLayer.contents = (id)[UIImage imageNamed:@"hourglass_5"].CGImage;
}

@end
