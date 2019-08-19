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

#import "DWTabBarView.h"

#import "DWPaymentsButton.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const TABBAR_HEIGHT = 49.0;
static CGFloat const TABBAR_HEIGHT_LARGE = 77.0;
static CGFloat const TABBAR_BORDER_WIDTH = 1.0;
static CGFloat const CENTER_CIRCLE_SIZE = 68.0;

static UIColor *ActiveButtonColor(void) {
    return [UIColor dw_dashBlueColor];
}

static UIColor *InactiveButtonColor(void) {
    return [UIColor dw_tabbarInactiveButtonColor];
}

@interface DWTabBarView ()

@property (nonatomic, strong) CALayer *backgroundLayer;
@property (nonatomic, strong) CAShapeLayer *centerCircleLayer;
@property (nonatomic, strong) CALayer *circleOverlayLayer;

@property (nonatomic, copy) NSArray<UIButton *> *buttons;
@property (nonatomic, strong) DWPaymentsButton *paymentsButton;

@end

@implementation DWTabBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];
        self.clipsToBounds = NO;

        CALayer *backgroundLayer = [CALayer layer];
        backgroundLayer.backgroundColor = self.backgroundColor.CGColor;
        backgroundLayer.borderColor = [UIColor dw_tabbarBorderColor].CGColor;
        backgroundLayer.borderWidth = TABBAR_BORDER_WIDTH;
        [self.layer addSublayer:backgroundLayer];
        _backgroundLayer = backgroundLayer;

        CAShapeLayer *centerCircleLayer = [CAShapeLayer layer];
        centerCircleLayer.fillColor = self.backgroundColor.CGColor;
        centerCircleLayer.strokeColor = [UIColor dw_tabbarBorderColor].CGColor;
        centerCircleLayer.lineWidth = TABBAR_BORDER_WIDTH;
        const CGFloat radius = CENTER_CIRCLE_SIZE / 2.0;
        UIBezierPath *circlePath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(radius, radius)
                                                                  radius:radius
                                                              startAngle:0
                                                                endAngle:M_PI
                                                               clockwise:NO];
        centerCircleLayer.path = circlePath.CGPath;
        [self.layer addSublayer:centerCircleLayer];
        _centerCircleLayer = centerCircleLayer;

        CALayer *circleOverlayLayer = [CALayer layer];
        circleOverlayLayer.backgroundColor = self.backgroundColor.CGColor;
        [self.layer addSublayer:circleOverlayLayer];
        _circleOverlayLayer = circleOverlayLayer;

        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];

        {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *image = [UIImage imageNamed:@"tabbar_home_icon"];
            [button setImage:image forState:UIControlStateNormal];
            button.tintColor = ActiveButtonColor();
            [self addSubview:button];
            [buttons addObject:button];
        }

        {
            DWPaymentsButton *button = [[DWPaymentsButton alloc] initWithFrame:CGRectZero];
            [button addTarget:self
                          action:@selector(paymentsButtonAction:)
                forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
            [buttons addObject:button];
            _paymentsButton = button;
        }

        {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *image = [UIImage imageNamed:@"tabbar_other_icon"];
            [button setImage:image forState:UIControlStateNormal];
            button.tintColor = InactiveButtonColor();
            [self addSubview:button];
            [buttons addObject:button];
        }

        _buttons = [buttons copy];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric,
                      DEVICE_HAS_HOME_INDICATOR ? TABBAR_HEIGHT_LARGE : TABBAR_HEIGHT);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    NSAssert(self.buttons.count > 0, @"Invalid state");

    const CGSize size = self.bounds.size;
    const CGFloat buttonWidth = size.width / self.buttons.count;
    CGFloat x = 0.0;
    for (UIButton *button in self.buttons) {
        if (button != self.paymentsButton) {
            button.frame = CGRectMake(x, 0.0, buttonWidth, MIN(TABBAR_HEIGHT, size.height));
        }

        x += buttonWidth;
    }

    self.backgroundLayer.frame = self.bounds;

    const CGSize arcSize = CGSizeMake(CENTER_CIRCLE_SIZE, CENTER_CIRCLE_SIZE / 2.0);
    self.centerCircleLayer.frame = CGRectMake((size.width - arcSize.width) / 2.0,
                                              -DW_TABBAR_NOTCH,
                                              arcSize.width,
                                              arcSize.height);

    const CGSize overlaySize = CGSizeMake(CENTER_CIRCLE_SIZE + TABBAR_BORDER_WIDTH * 2,
                                          TABBAR_HEIGHT - TABBAR_BORDER_WIDTH * 2);
    self.circleOverlayLayer.frame = CGRectMake((size.width - overlaySize.width) / 2.0,
                                               TABBAR_BORDER_WIDTH,
                                               overlaySize.width,
                                               overlaySize.height);

    self.paymentsButton.frame = CGRectMake((size.width - DW_PAYMENTS_BUTTON_SIZE.width) / 2.0,
                                           0.0,
                                           DW_PAYMENTS_BUTTON_SIZE.width,
                                           DW_PAYMENTS_BUTTON_SIZE.height);
}

- (void)setPaymentsButtonOpened:(BOOL)opened {
    self.paymentsButton.opened = opened;
}

#pragma mark - Actions

- (void)paymentsButtonAction:(DWPaymentsButton *)sender {
    if (sender.opened == NO) {
        [self.delegate tabBarViewDidOpenPayments:self];
    }
    else {
        [self.delegate tabBarViewDidClosePayments:self];
    }
}

@end

NS_ASSUME_NONNULL_END
