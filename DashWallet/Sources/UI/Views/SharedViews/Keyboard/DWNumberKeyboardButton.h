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
    DWNumberKeyboardButtonTypeDigit0,
    DWNumberKeyboardButtonTypeDigit1,
    DWNumberKeyboardButtonTypeDigit2,
    DWNumberKeyboardButtonTypeDigit3,
    DWNumberKeyboardButtonTypeDigit4,
    DWNumberKeyboardButtonTypeDigit5,
    DWNumberKeyboardButtonTypeDigit6,
    DWNumberKeyboardButtonTypeDigit7,
    DWNumberKeyboardButtonTypeDigit8,
    DWNumberKeyboardButtonTypeDigit9,
    DWNumberKeyboardButtonTypeSeparator,
    DWNumberKeyboardButtonTypeCustom,
    DWNumberKeyboardButtonTypeClear,
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
