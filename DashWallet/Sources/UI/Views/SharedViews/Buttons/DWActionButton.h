//
//  Created by Sam Westrich
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

#import "DWButton.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWActionButton : DWButton

- (UIColor *)backgroundColorForState:(UIControlState)state;
- (void)setBackgroundColor:(UIColor *)color forState:(UIControlState)state;

- (UIColor *)borderColorForState:(UIControlState)state;
- (void)setBorderColor:(UIColor *)color forState:(UIControlState)state;

- (CGFloat)borderWidthForState:(UIControlState)state;
- (void)setBorderWidth:(CGFloat)width forState:(UIControlState)state;

@end

NS_ASSUME_NONNULL_END
