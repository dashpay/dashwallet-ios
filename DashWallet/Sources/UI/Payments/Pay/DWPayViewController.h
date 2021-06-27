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

#import "DWBasePayViewController.h"

NS_ASSUME_NONNULL_BEGIN

@protocol DWPayModelProtocol;
@class DWPayViewController;
@protocol DWDPBasicUserItem;

@protocol DWPayViewControllerDelegate <NSObject>

- (void)payViewControllerDidFinishPayment:(DWPayViewController *)controller contact:(nullable id<DWDPBasicUserItem>)contact;

@end

@interface DWPayViewController : DWBasePayViewController

@property (nullable, nonatomic, weak) id<DWPayViewControllerDelegate> delegate;

+ (instancetype)controllerWithModel:(id<DWPayModelProtocol>)payModel
                       dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider;

@end

NS_ASSUME_NONNULL_END
