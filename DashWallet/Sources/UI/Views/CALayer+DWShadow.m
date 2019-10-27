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

#import "CALayer+DWShadow.h"

#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@implementation CALayer (DWShadow)

- (void)dw_applyShadowWithColor:(UIColor *)color
                          alpha:(float)alpha
                              x:(CGFloat)x
                              y:(CGFloat)y
                           blur:(CGFloat)blur {
    self.shadowColor = color.CGColor;
    self.shadowOpacity = alpha;
    self.shadowOffset = CGSizeMake(x, y);
    self.shadowRadius = blur / 2.0;
}

@end

NS_ASSUME_NONNULL_END
