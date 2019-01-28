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

#import "KVOUIView.h"

#import "DWAlertAction.h"

NS_ASSUME_NONNULL_BEGIN

@class DWAlertViewActionButton;

@protocol DWAlertViewActionButtonDelegate <NSObject>

- (void)actionButton:(DWAlertViewActionButton *)actionButton touchBegan:(UITouch *)touch;
- (void)actionButton:(DWAlertViewActionButton *)actionButton touchMoved:(UITouch *)touch;
- (void)actionButton:(DWAlertViewActionButton *)actionButton touchEnded:(UITouch *)touch;
- (void)actionButton:(DWAlertViewActionButton *)actionButton touchCancelled:(UITouch *)touch;

@end

@interface DWAlertViewActionButton : KVOUIView

@property (readonly, strong, nonatomic) DWAlertAction *alertAction;
@property (assign, nonatomic, getter=isHighlighted) BOOL highlighted;
@property (assign, nonatomic, getter=isPreferred) BOOL preferred;
@property (nullable, weak, nonatomic) id<DWAlertViewActionButtonDelegate> delegate;

- (instancetype)initWithAlertAction:(DWAlertAction *)alertAction;

- (void)updateForCurrentContentSizeCategory;

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
