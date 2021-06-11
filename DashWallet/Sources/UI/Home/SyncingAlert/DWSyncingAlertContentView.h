//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import <KVO-MVVM/KVOUIView.h>

#import "DWSyncContainerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class DWSyncingAlertContentView;

@protocol DWSyncingAlertContentViewDelegate <NSObject>

- (void)syncingAlertContentView:(DWSyncingAlertContentView *)view okButtonAction:(UIButton *)sender;

@end

@interface DWSyncingAlertContentView : KVOUIView

@property (nullable, nonatomic, weak) id<DWSyncingAlertContentViewDelegate> delegate;

@property (nonatomic, strong) id<DWSyncContainerProtocol> model;

@end

NS_ASSUME_NONNULL_END
