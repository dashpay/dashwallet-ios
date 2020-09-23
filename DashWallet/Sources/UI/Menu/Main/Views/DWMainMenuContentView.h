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

#import "DWCurrentUserProfileModel.h"
#import "DWMainMenuItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DWMainMenuModel;
@class DWMainMenuContentView;

@protocol DWMainMenuContentViewDelegate <NSObject>

- (void)mainMenuContentView:(DWMainMenuContentView *)view didSelectMenuItem:(id<DWMainMenuItem>)item;

- (void)mainMenuContentView:(DWMainMenuContentView *)view showQRAction:(UIButton *)sender;
- (void)mainMenuContentView:(DWMainMenuContentView *)view editProfileAction:(UIButton *)sender;

@end

@interface DWMainMenuContentView : KVOUIView

@property (nonatomic, strong) DWMainMenuModel *model;
@property (nonatomic, strong) DWCurrentUserProfileModel *userModel;
@property (nullable, nonatomic, weak) id<DWMainMenuContentViewDelegate> delegate;

- (void)viewWillAppear;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
