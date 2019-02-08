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

typedef NS_ENUM(NSUInteger, DWAmountButtonType) {
    DWAmountButtonTypeDigit0,
    DWAmountButtonTypeDigit1,
    DWAmountButtonTypeDigit2,
    DWAmountButtonTypeDigit3,
    DWAmountButtonTypeDigit4,
    DWAmountButtonTypeDigit5,
    DWAmountButtonTypeDigit6,
    DWAmountButtonTypeDigit7,
    DWAmountButtonTypeDigit8,
    DWAmountButtonTypeDigit9,
    DWAmountButtonTypeSeparator,
    DWAmountButtonTypeClear,
};

@class DWAmountButton;

@protocol DWAmountButtonDelegate <NSObject>

- (void)amountButton:(DWAmountButton *)amountButton touchBegan:(UITouch *)touch;
- (void)amountButton:(DWAmountButton *)amountButton touchMoved:(UITouch *)touch;
- (void)amountButton:(DWAmountButton *)amountButton touchEnded:(UITouch *)touch;
- (void)amountButton:(DWAmountButton *)amountButton touchCancelled:(UITouch *)touch;

@end

@interface DWAmountButton : UIView

@property (readonly, assign, nonatomic) DWAmountButtonType type;
@property (assign, nonatomic, getter=isHighlighted) BOOL highlighted;
@property (nullable, weak, nonatomic) id<DWAmountButtonDelegate> delegate;

- (instancetype)initWithWithType:(DWAmountButtonType)type;

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
