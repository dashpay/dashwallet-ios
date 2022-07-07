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

// Original idea: https://useyourloaf.com/blog/using-a-custom-font-with-dynamic-type/

#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Category

@implementation UIFont (DWFont)

- (instancetype)fontWithWeight:(CGFloat)weight {
    UIFontDescriptor *newDescriptor = [self.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute : @{UIFontWeightTrait : @(weight)}}];

    return [UIFont fontWithDescriptor:newDescriptor size:self.pointSize];
}

+ (instancetype)dw_fontForTextStyle:(UIFontTextStyle)textStyle {
    return [UIFont preferredFontForTextStyle:textStyle];
}

+ (UIFont *)dw_navigationBarTitleFont {
    return [UIFont dw_mediumFontOfSize:18.0];
}

+ (UIFont *)dw_regularFontOfSize:(CGFloat)fontSize {
    return [UIFont systemFontOfSize:fontSize];
}

+ (UIFont *)dw_mediumFontOfSize:(CGFloat)fontSize {
    return [UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium];
}

@end

NS_ASSUME_NONNULL_END
