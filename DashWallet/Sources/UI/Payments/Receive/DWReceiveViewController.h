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

@protocol DWReceiveModelProtocol;
@class DWReceiveViewController;

/**
 Used for `DWReceiveViewType_QuickReceive` type
 */
@protocol DWReceiveViewControllerOldDelegate <NSObject>

- (void)receiveViewControllerExitButtonAction:(DWReceiveViewController *)controller;

@end

@interface DWReceiveViewControllerOld : UIViewController

@property (nonatomic, assign) NSUInteger viewType;
@property (nullable, nonatomic, weak) id<DWReceiveViewControllerOldDelegate> delegate;
@property (nonatomic, strong) id<DWReceiveModelProtocol> model;

+ (instancetype)controllerWithModel:(id<DWReceiveModelProtocol>)receiveModel;

@end

NS_ASSUME_NONNULL_END
