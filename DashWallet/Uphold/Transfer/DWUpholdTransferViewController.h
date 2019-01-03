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

#import "DWAlertViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class DWUpholdCardObject;
@class DWUpholdTransferViewController;

@protocol DWUpholdTransferViewControllerDelegate <NSObject>

- (void)upholdTransferViewControllerDidFinish:(DWUpholdTransferViewController *)controller;
- (void)upholdTransferViewControllerDidFinish:(DWUpholdTransferViewController *)controller
                           openTransactionURL:(NSURL *)url;
- (void)upholdTransferViewControllerDidCancel:(DWUpholdTransferViewController *)controller;

@end

@interface DWUpholdTransferViewController : DWAlertViewController

@property (nullable, weak, nonatomic) id<DWUpholdTransferViewControllerDelegate> delegate;

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card;

@end

NS_ASSUME_NONNULL_END
