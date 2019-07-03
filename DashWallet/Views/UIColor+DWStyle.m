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

#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIColor (DWStyle)

+ (UIColor *)dw_dashBlue {
    UIColor *color = [UIColor colorNamed:@"DashBlueColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_title {
    UIColor *color = [UIColor colorNamed:@"TitleColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_disabledButton {
    UIColor *color = [UIColor colorNamed:@"DisabledButtonColor"];
    NSParameterAssert(color);
    return color;
}

@end

NS_ASSUME_NONNULL_END
