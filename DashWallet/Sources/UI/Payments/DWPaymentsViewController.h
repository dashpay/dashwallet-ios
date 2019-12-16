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

#import "DWNavigationFullscreenable.h"

NS_ASSUME_NONNULL_BEGIN

@class DWPaymentsViewController;
@protocol DWReceiveModelProtocol;
@protocol DWPayModelProtocol;
@protocol DWTransactionListDataProviderProtocol;

typedef NS_ENUM(NSUInteger, DWPaymentsViewControllerIndex) {
    DWPaymentsViewControllerIndex_None = -1,
    DWPaymentsViewControllerIndex_Pay = 0,
    DWPaymentsViewControllerIndex_Receive = 1,
};

@protocol DWPaymentsViewControllerDelegate <NSObject>

- (void)paymentsViewControllerDidCancel:(DWPaymentsViewController *)controller;

@end

@interface DWPaymentsViewController : UIViewController <DWNavigationFullscreenable>

@property (nullable, nonatomic, weak) id<DWPaymentsViewControllerDelegate> delegate;
@property (nonatomic, assign) DWPaymentsViewControllerIndex currentIndex;

+ (instancetype)controllerWithReceiveModel:(id<DWReceiveModelProtocol>)receiveModel
                                  payModel:(id<DWPayModelProtocol>)payModel
                              dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider;

@end

NS_ASSUME_NONNULL_END
