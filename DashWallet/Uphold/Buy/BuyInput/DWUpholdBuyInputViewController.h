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

#import "KVOUIViewController.h"

#import "DWAlertAction.h"
#import "DWUpholdOTPProvider.h"


NS_ASSUME_NONNULL_BEGIN

@class DWUpholdCardObject;
@class DWUpholdAccountObject;
@class DWUpholdTransactionObject;
@class DWUpholdBuyInputViewController;

@protocol DWUpholdBuyInputViewControllerDelegate <NSObject>

- (void)upholdBuyInputViewController:(DWUpholdBuyInputViewController *)controller
                      didProduceTransaction:(DWUpholdTransactionObject *)transaction;
- (void)upholdBuyInputViewControllerDidCancel:(DWUpholdBuyInputViewController *)controller;


@end

@interface DWUpholdBuyInputViewController : KVOUIViewController

@property (readonly, copy, nonatomic) NSArray<DWAlertAction *> *providedActions;
@property (readonly, strong, nonatomic) DWAlertAction *preferredAction;

@property (nullable, weak, nonatomic) id<DWUpholdBuyInputViewControllerDelegate> delegate;
@property (nullable, weak, nonatomic) id<DWUpholdOTPProvider> otpProvider;

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card account:(DWUpholdAccountObject *)account;

@end

NS_ASSUME_NONNULL_END
