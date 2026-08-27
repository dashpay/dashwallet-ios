//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

typedef NS_ENUM(NSUInteger, DWPressedAnimationStrength) {
    /// 93% scale, works best with square controls
    DWPressedAnimationStrength_Heavy,
    /// 95% scale, works best with medium-width (~= half of the screen width) rectangle controls
    DWPressedAnimationStrength_Medium,
    /// 97% scale, works best with big-width (~= screen width) rectangle views
    DWPressedAnimationStrength_Light,
};

@interface UIView (DWAnimations)

- (void)dw_shakeViewWithCompletion:(void (^)(void))completion;
- (void)dw_shakeView;

- (void)dw_pressedAnimation:(DWPressedAnimationStrength)strength pressed:(BOOL)pressed;

@end

NS_ASSUME_NONNULL_END
