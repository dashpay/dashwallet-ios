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

@class UIColor;
@class UIFont;

@interface NSAttributedString (DWBuilder)

+ (NSAttributedString *)dw_dashAttributedStringForAmount:(uint64_t)amount
                                               tintColor:(UIColor *)tintColor
                                              symbolSize:(CGSize)symbolSize;

+ (NSAttributedString *)dw_dashAttributedStringForAmount:(uint64_t)amount
                                               tintColor:(UIColor *)tintColor
                                                    font:(UIFont *)font;
+ (NSAttributedString *)dw_dashAttributedStringForFormattedAmount:(NSString *)string
                                                        tintColor:(UIColor *)tintColor
                                                             font:(UIFont *)font;

+ (NSAttributedString *)dw_dashAddressAttributedString:(NSString *)address withFont:(UIFont *)font showingLogo:(BOOL)showingLogo;
+ (NSAttributedString *)dw_dashAddressAttributedString:(NSString *)address withFont:(UIFont *)font;

@end

NS_ASSUME_NONNULL_END
