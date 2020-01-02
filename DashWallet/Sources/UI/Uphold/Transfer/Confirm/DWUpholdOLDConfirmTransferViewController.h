//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import <KVO-MVVM/KVOUIViewController.h>

#import "DWAlertAction.h"
#import "DWUpholdOTPProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class DWUpholdCardObject;
@class DWUpholdTransactionObject;
@class DWUpholdOLDConfirmTransferViewController;

@protocol DWUpholdConfirmTransferViewControllerDelegate <NSObject>

- (void)upholdConfirmTransferViewControllerDidCancel:(DWUpholdOLDConfirmTransferViewController *)controller;
- (void)upholdConfirmTransferViewControllerDidFinish:(DWUpholdOLDConfirmTransferViewController *)controller
                                         transaction:(DWUpholdTransactionObject *)transaction;

@end

@interface DWUpholdOLDConfirmTransferViewController : KVOUIViewController

@property (readonly, copy, nonatomic) NSArray<DWAlertAction *> *providedActions;
@property (readonly, strong, nonatomic) DWAlertAction *preferredAction;

@property (nullable, weak, nonatomic) id<DWUpholdConfirmTransferViewControllerDelegate> delegate;
@property (nullable, weak, nonatomic) id<DWUpholdOTPProvider> otpProvider;

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card transaction:(DWUpholdTransactionObject *)transaction;

@end

NS_ASSUME_NONNULL_END
