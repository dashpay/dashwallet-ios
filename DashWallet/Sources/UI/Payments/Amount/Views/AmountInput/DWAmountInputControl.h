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

#import "DWAmountInputControlSource.h"

NS_ASSUME_NONNULL_BEGIN

// This control doesn't support Dynamic Type because it has already really large fonts in use

@class DWAmountInputControl;

@protocol DWAmountInputControlDelegate <NSObject>

- (void)amountInputControl:(DWAmountInputControl *)control currencySelectorAction:(UIButton *)sender;

@end

@interface DWAmountInputControl : UIControl

/**
 Small size is used in Uphold transfer UI
 */
@property (assign, nonatomic) IBInspectable BOOL smallSize;
@property (strong, nonatomic) IBInspectable UIColor *controlColor;
@property (nullable, nonatomic, weak) id<DWAmountInputControlDelegate> delegate;

@property (strong, nonatomic) id<DWAmountInputControlSource> source;

- (void)setActiveTypeAnimated:(DWAmountType)activeType completion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
