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

typedef NS_ENUM(NSUInteger, DWNumberKeyboardButtonType) {
    DWNumberKeyboardButtonType_Digit0,
    DWNumberKeyboardButtonType_Digit1,
    DWNumberKeyboardButtonType_Digit2,
    DWNumberKeyboardButtonType_Digit3,
    DWNumberKeyboardButtonType_Digit4,
    DWNumberKeyboardButtonType_Digit5,
    DWNumberKeyboardButtonType_Digit6,
    DWNumberKeyboardButtonType_Digit7,
    DWNumberKeyboardButtonType_Digit8,
    DWNumberKeyboardButtonType_Digit9,
    DWNumberKeyboardButtonType_Separator,
    DWNumberKeyboardButtonType_Custom,
    DWNumberKeyboardButtonType_Clear,
};

@class DWNumberKeyboardButton;

@protocol DWNumberKeyboardButtonDelegate <NSObject>

- (void)numberButton:(DWNumberKeyboardButton *)numberButton touchBegan:(UITouch *)touch;
- (void)numberButton:(DWNumberKeyboardButton *)numberButton touchMoved:(UITouch *)touch;
- (void)numberButton:(DWNumberKeyboardButton *)numberButton touchEnded:(UITouch *)touch;
- (void)numberButton:(DWNumberKeyboardButton *)numberButton touchCancelled:(UITouch *)touch;

@end

@interface DWNumberKeyboardButton : UIView

@property (assign, nonatomic) DWNumberKeyboardButtonType type;
@property (assign, nonatomic, getter=isHighlighted) BOOL highlighted;
@property (nullable, weak, nonatomic) id<DWNumberKeyboardButtonDelegate> delegate;

- (instancetype)init;

- (void)configureAsCustomTypeWithTitle:(NSString *)title;

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
