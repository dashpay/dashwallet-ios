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

typedef NS_ENUM(NSUInteger, DWPinFieldStyle) {
    DWPinFieldStyle_Default,      // 50pt field size
    DWPinFieldStyle_DefaultWhite, // 50pt field size, white bg (lock screen)
    DWPinFieldStyle_Small,        // 44pt
};

@class DWPinField;

@protocol DWPinFieldDelegate <NSObject>

- (void)pinFieldDidFinishInput:(DWPinField *)pinField;

@end

/// App-owned PIN entry control (C7 — ported from DashSync's `DSPinField`,
/// which vanishes with the pod). A `UITextInput` view drawing PIN_LENGTH
/// rounded boxes that fill dash-blue with a white dot as digits arrive;
/// used by the lock screen and Set-PIN flows. Rendering matches the pod's
/// exactly (same field/dot sizes and colors) so the migration is invisible.
@interface DWPinField : UIView <UITextInput>

@property (nonatomic, assign) BOOL inputEnabled;
@property (nullable, nonatomic, weak) id<DWPinFieldDelegate> delegate;
@property (readonly, nonatomic, copy) NSString *text;

- (void)clear;

- (instancetype)initWithStyle:(DWPinFieldStyle)style;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
