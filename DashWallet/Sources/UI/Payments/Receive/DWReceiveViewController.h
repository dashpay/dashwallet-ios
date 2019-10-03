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

#import "DWReceiveViewType.h"

NS_ASSUME_NONNULL_BEGIN

@class DWReceiveModel;
@class DWReceiveViewController;

/**
 Used for `DWReceiveViewType_QuickReceive` type
 */
@protocol DWReceiveViewControllerDelegate <NSObject>

- (void)receiveViewControllerExitButtonAction:(DWReceiveViewController *)controller;

@end

@interface DWReceiveViewController : UIViewController

@property (nonatomic, assign) DWReceiveViewType viewType;
@property (nullable, nonatomic, weak) id<DWReceiveViewControllerDelegate> delegate;

+ (instancetype)controllerWithModel:(DWReceiveModel *)receiveModel;

@end

NS_ASSUME_NONNULL_END
