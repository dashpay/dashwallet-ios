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

#import "NSAttributedString+DWHighlightText.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSAttributedString (DWHighlightText)

+ (NSAttributedString *)attributedText:(NSString *)text
                                  font:(UIFont *)font
                             textColor:(UIColor *)textColor
                       highlightedText:(nullable NSString *)highlightedText
                  highlightedTextColor:(UIColor *)highlightedTextColor {
    if (text.length == 0) {
        return [[NSAttributedString alloc] init];
    }

    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:text];

    NSRange textRange = NSMakeRange(0, text.length);
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : textColor,
    };
    [string setAttributes:attributes range:textRange];

    if (highlightedText.length > 0) {
        NSRange searchRange = textRange;
        NSRange foundRange;
        while (searchRange.location < textRange.length) {
            searchRange.length = text.length - searchRange.location;
            foundRange = [text rangeOfString:highlightedText
                                     options:NSCaseInsensitiveSearch
                                       range:searchRange];
            if (foundRange.location != NSNotFound) {
                NSDictionary<NSAttributedStringKey, id> *attributes = @{
                    NSForegroundColorAttributeName : highlightedTextColor,
                };
                [string removeAttribute:NSForegroundColorAttributeName range:foundRange];
                [string addAttributes:attributes range:foundRange];

                searchRange.location = foundRange.location + foundRange.length;
            }
            else {
                break;
            }
        }
    }

    return [string copy];
}


@end

NS_ASSUME_NONNULL_END
