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

#import "DWShadowView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWShadowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self shadowView_commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self shadowView_commonInit];
    }
    return self;
}

- (void)shadowView_commonInit {
    self.backgroundColor = [UIColor clearColor];

    [self.layer dw_applyShadowWithColor:[UIColor dw_shadowColor] alpha:0.02 x:0.0 y:0.0 blur:5.0];
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;

    _spread = 1.0;
}

- (void)setSpread:(CGFloat)spread {
    _spread = spread;

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.spread == 0 || self.isHidden) {
        self.layer.shadowPath = nil;
    }
    else {
        const CGFloat dx = -self.spread;
        const CGRect rect = CGRectInset(self.bounds, dx, dx);
        self.layer.shadowPath = [UIBezierPath bezierPathWithRect:rect].CGPath;
    }
}

@end

NS_ASSUME_NONNULL_END
