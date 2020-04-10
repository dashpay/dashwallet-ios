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

#import <KVO-MVVM/KVOUIView.h>

#import "DWHomeProtocol.h"
#import "DWShortcutsActionDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@class DWHomeHeaderView;

@protocol DWHomeHeaderViewDelegate <NSObject>

- (void)homeHeaderViewDidUpdateContents:(DWHomeHeaderView *)view;
- (void)homeHeaderView:(DWHomeHeaderView *)view payButtonAction:(UIButton *)sender;
- (void)homeHeaderView:(DWHomeHeaderView *)view receiveButtonAction:(UIButton *)sender;

@end

@interface DWHomeHeaderView : KVOUIView

@property (nullable, nonatomic, strong) id<DWHomeProtocol> model;
@property (nullable, nonatomic, weak) id<DWHomeHeaderViewDelegate> delegate;
@property (nullable, nonatomic, weak) id<DWShortcutsActionDelegate> shortcutsDelegate;

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)parentScrollViewDidScroll:(UIScrollView *)scrollView;

@end

NS_ASSUME_NONNULL_END
