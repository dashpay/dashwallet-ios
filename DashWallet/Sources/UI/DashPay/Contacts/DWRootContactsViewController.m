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

#import "DWRootContactsViewController.h"

#import "DWContactsPlaceholderViewController.h"
#import "DWContactsViewController.h"
#import "DWDashPayModel.h"
#import "DWGlobalOptions.h"
#import "DWUIKit.h"

@interface DWRootContactsViewController ()

@property (readonly, nonatomic, strong) id<DWPayModelProtocol> payModel;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;
@property (readonly, nonatomic, strong) id<DWDashPayProtocol> dashPayModel;
@property (readonly, nonatomic, strong) id<DWDashPayReadyProtocol> dashPayReady;

@end

@implementation DWRootContactsViewController

- (instancetype)initWithPayModel:(id<DWPayModelProtocol>)payModel
                    dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider
                    dashPayModel:(id<DWDashPayProtocol>)dashPayModel
                    dashPayReady:(id<DWDashPayReadyProtocol>)dashPayReady {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _payModel = payModel;
        _dataProvider = dataProvider;
        _dashPayModel = dashPayModel;
        _dashPayReady = dashPayReady;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Contacts", nil);

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    // Model:

    [self update];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(update)
                               name:DWDashPayRegistrationStatusUpdatedNotification
                             object:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)update {
    if ([self contactsAvailable]) {
        DWContactsViewController *contactsController =
            [[DWContactsViewController alloc] initWithPayModel:self.payModel
                                                  dataProvider:self.dataProvider];
        [self dw_embedChild:contactsController];
    }
    else {
        DWContactsPlaceholderViewController *placeholderController =
            [[DWContactsPlaceholderViewController alloc] initWithDashPayModel:self.dashPayModel
                                                                 dashPayReady:self.dashPayReady];
        [self dw_embedChild:placeholderController];
    }
}

- (BOOL)contactsAvailable {
    return self.dashPayModel.username != nil;
}

@end
