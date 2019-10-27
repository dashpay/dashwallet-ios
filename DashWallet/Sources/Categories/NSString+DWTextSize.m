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

#import "NSString+DWTextSize.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (DWTextSize)

- (CGSize)dw_textSizeWithFont:(UIFont *)font maxWidth:(CGFloat)maxWidth {
    NSParameterAssert(font);

    const CGSize maxSize = CGSizeMake(maxWidth, CGFLOAT_MAX);
    return [self dw_textSizeWithFont:font maxSize:maxSize];
}

- (CGSize)dw_textSizeWithFont:(UIFont *)font maxSize:(CGSize)maxSize {
    NSParameterAssert(font);

    NSDictionary *const attributes = @{
        NSFontAttributeName : font,
    };
    return [self dw_textSizeWithAttributes:attributes maxSize:maxSize];
}

- (CGSize)dw_textSizeWithAttributes:(NSDictionary *)attributes maxSize:(CGSize)maxSize {
    NSParameterAssert(attributes);

    const CGRect rect = [self boundingRectWithSize:maxSize
                                           options:NSStringDrawingUsesLineFragmentOrigin
                                        attributes:attributes
                                           context:nil];
    const CGSize size = rect.size;

    if (size.width == 0.0 || size.height == 0.0) {
        return CGSizeZero;
    }
    else {
        return CGSizeMake(ceil(size.width), ceil(size.height));
    }
}

@end

NS_ASSUME_NONNULL_END
