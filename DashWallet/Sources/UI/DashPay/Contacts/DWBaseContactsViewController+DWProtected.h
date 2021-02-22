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

#import "DWBaseContactsViewController.h"

#import "DWBaseContactsContentViewController.h"
#import "DWBaseContactsModel.h"
#import "DWDPNewIncomingRequestItem.h"
#import "DWSearchStateViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBaseContactsViewController () <DWContactsModelDelegate, DWSearchStateViewControllerDelegate, DWDPNewIncomingRequestItemDelegate>

@property (readonly, nonatomic, strong) id<DWPayModelProtocol> payModel;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;

@property (readonly, nonatomic, strong) DWBaseContactsModel *model;
@property (readonly, nonatomic, strong) DWSearchStateViewController *stateController;
@property (readonly, nonatomic, strong) __kindof UIViewController *localNoContactsController;
@property (readonly, nonatomic, strong) DWBaseContactsContentViewController *contentController;

- (void)addContactButtonAction;

@end

NS_ASSUME_NONNULL_END
