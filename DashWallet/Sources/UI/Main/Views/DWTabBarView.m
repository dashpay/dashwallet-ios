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

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const TABBAR_HEIGHT = 49.0;
static CGFloat const TABBAR_HEIGHT_LARGE = 77.0;
static CGFloat const TABBAR_BORDER_WIDTH = 1.0;

static UIColor *ActiveButtonColor(void) {
    return [UIColor dw_dashBlueColor];
}

static UIColor *InactiveButtonColor(void) {
    return [UIColor dw_tabbarInactiveButtonColor];
}

@interface DWTabBarView ()

@property (nonatomic, copy) NSArray<UIButton *> *buttons;

@end

@implementation DWTabBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        self.layer.borderColor = [UIColor dw_tabbarBorderColor].CGColor;
        self.layer.borderWidth = TABBAR_BORDER_WIDTH;

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
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [self addSubview:button];
            [buttons addObject:button];
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

    const CGSize size = self.bounds.size;
    const CGFloat buttonWidth = size.width / self.buttons.count;
    CGFloat x = 0.0;
    for (UIButton *button in self.buttons) {
        button.frame = CGRectMake(x, 0.0, buttonWidth, MIN(TABBAR_HEIGHT, size.height));
        x += buttonWidth;
    }
}

@end

NS_ASSUME_NONNULL_END
