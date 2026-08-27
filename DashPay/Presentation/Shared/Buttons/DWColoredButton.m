//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWColoredButton.h"

#import "DWUIKit.h"

@implementation DWColoredButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;

        self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
    }
    return self;
}

- (void)setStyle:(DWColoredButtonStyle)style {
    _style = style;

    switch (style) {
        case DWColoredButtonStyle_Black: {
            [self setBackgroundColor:[UIColor dw_buttonBlackColor]];
            [self setTitleColor:[UIColor dw_buttonBlackTitleColor] forState:UIControlStateNormal];

            break;
        }
        default:
            break;
    }
}

@end
