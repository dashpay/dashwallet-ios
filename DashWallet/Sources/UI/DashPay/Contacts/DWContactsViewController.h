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

#import "DWContactsModel.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWContactsControllerIntent) {
    DWContactsControllerIntent_Default,
    DWContactsControllerIntent_PayToSelector,
};

@class DWContactsViewController;

@protocol DWContactsViewControllerPayDelegate <NSObject>

- (void)contactsViewController:(DWContactsViewController *)controller payToItem:(id<DWDPBasicUserItem>)item;

@end

@interface DWContactsViewController : DWBaseContactsViewController

@property (nonatomic, strong) DWContactsModel *model;
@property (nonatomic, assign) DWContactsControllerIntent intent;
@property (nullable, nonatomic, weak) id<DWContactsViewControllerPayDelegate> payDelegate;

@end

NS_ASSUME_NONNULL_END
