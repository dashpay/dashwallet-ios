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

#import "DWMaxButton.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const MAXBUTTON_INSETS = {4.0, 20.0, 4.0, 20.0};

@implementation DWMaxButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self dwMaxButtonSetup];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self dwMaxButtonSetup];
    }
    return self;
}

- (void)dwMaxButtonSetup {
    UIColor *maxNormalColor = [UIColor dw_tertiaryTextColor];
    UIColor *maxHighlightedColor = [maxNormalColor colorWithAlphaComponent:0.5];
    UIColor *maxSelectedColor = [UIColor dw_dashBlueColor];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    self.contentEdgeInsets = MAXBUTTON_INSETS;
    self.layer.cornerRadius = 8.0;
    self.layer.borderWidth = 1.0;
    self.layer.masksToBounds = YES;
    [self setTitleColor:maxNormalColor forState:UIControlStateNormal];
    [self setTitleColor:maxHighlightedColor forState:UIControlStateHighlighted];
    [self setTitleColor:maxSelectedColor forState:UIControlStateSelected];
    [self setTitle:NSLocalizedString(@"Max", @"Contracted variant of 'Maximum' word")
          forState:UIControlStateNormal];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    UIControlState state = highlighted ? UIControlStateHighlighted : UIControlStateNormal;
    if (!highlighted) {
        state = self.selected ? UIControlStateSelected : UIControlStateNormal;
    }

    [self setBorderColorForState:state];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];

    [self setBorderColorForState:selected ? UIControlStateSelected : UIControlStateNormal];
}

#pragma mark - Private

- (void)setBorderColorForState:(UIControlState)state {
    UIColor *color = [self titleColorForState:state];
    self.layer.borderColor = color.CGColor;
}

@end

NS_ASSUME_NONNULL_END
