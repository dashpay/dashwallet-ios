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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIFont (DWFont)

/**
 Copy the font for the given weight

 @param weight The weight of the font
 @return  A copy of the current `UIFont` with updated weight
 */

- (instancetype)fontWithWeight:(CGFloat)weight;

/**
 Get the scaled font for the given text style

 @param textStyle The `UIFontTextStyle` for the font.
 @return  A `UIFont` of the custom font that has been scaled for the users currently selected preferred text size.
 */
+ (instancetype)dw_fontForTextStyle:(UIFontTextStyle)textStyle;

+ (UIFont *)dw_navigationBarTitleFont;

+ (UIFont *)dw_regularFontOfSize:(CGFloat)fontSize;
+ (UIFont *)dw_mediumFontOfSize:(CGFloat)fontSize;
+ (UIFont *)dw_boldFontOfSize:(CGFloat)fontSize;

@end

NS_ASSUME_NONNULL_END
