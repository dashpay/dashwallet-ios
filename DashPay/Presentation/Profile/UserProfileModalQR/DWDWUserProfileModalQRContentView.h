//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

@protocol DWReceiveModelProtocol;
@class DWUserProfileModalQRContentView;

@protocol DWDWUserProfileModalQRContentViewDelegate <NSObject>

- (void)userProfileModalQRContentView:(DWUserProfileModalQRContentView *)view shareButtonAction:(UIButton *)sender;
- (void)userProfileModalQRContentView:(DWUserProfileModalQRContentView *)view closeButtonAction:(UIButton *)sender;

@end

@interface DWUserProfileModalQRContentView : KVOUIView

@property (nullable, weak, nonatomic) id<DWDWUserProfileModalQRContentViewDelegate> delegate;

- (void)viewDidAppear;

- (instancetype)initWithModel:(id<DWReceiveModelProtocol>)model;

- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;


@end

NS_ASSUME_NONNULL_END
