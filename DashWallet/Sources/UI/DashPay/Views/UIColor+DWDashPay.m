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

#import "UIColor+DWDashPay.h"

@implementation UIColor (DWDashPay)

+ (UIColor *)dw_colorWithUsername:(NSString *)username {
    if (username.length > 0) {
        NSString *letter = [username substringToIndex:1];
        unichar charCode = [letter characterAtIndex:0];
        CGFloat hue;
        if (charCode <= 57) {             // is digit
            hue = (charCode - 48) / 36.0; // 48 == '0', 36 == total count of supported characters
        }
        else {
            hue = (charCode - 65 + 10) / 36.0; // 65 == 'A', 10 == count of digits
        }
        return [UIColor colorWithHue:hue saturation:0.3 brightness:0.6 alpha:1.0];
    }
    else {
        return [UIColor blackColor];
    }
}

@end
