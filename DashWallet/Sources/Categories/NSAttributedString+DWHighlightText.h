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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAttributedString (DWHighlightText)

+ (nullable NSAttributedString *)attributedText:(NSString *)text
                                           font:(UIFont *)font
                                      textColor:(UIColor *)textColor
                                highlightedText:(nullable NSString *)highlightedText
                           highlightedTextColor:(UIColor *)highlightedTextColor;

+ (nullable NSAttributedString *)attributedText:(NSAttributedString *)text
                                      textColor:(UIColor *)textColor
                                highlightedText:(nullable NSString *)highlightedText
                           highlightedTextColor:(UIColor *)highlightedTextColor;

@end

NS_ASSUME_NONNULL_END
