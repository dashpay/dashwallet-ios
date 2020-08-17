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

#import "DWRequestsViewController.h"

#import "DWBaseContactsViewController+DWProtected.h"
#import "DWRequestsContentViewController.h"
#import "DWRequestsModel.h"

@implementation DWRequestsViewController

@synthesize model = _model;
@synthesize stateController = _stateController;
@synthesize contentController = _contentController;

- (instancetype)initWithModel:(DWRequestsModel *)model
                     payModel:(id<DWPayModelProtocol>)payModel
                 dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super initWithPayModel:payModel dataProvider:dataProvider];
    if (self) {
        _model = model;
        _model.delegate = self;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Contact Requests", nil);
    self.searchBar.placeholder = NSLocalizedString(@"Search for a contact request", nil);
}

#pragma mark - Private

- (DWSearchStateViewController *)stateController {
    if (_stateController == nil) {
        _stateController = [[DWSearchStateViewController alloc] init];
        _stateController.delegate = self;
    }
    return _stateController;
}

- (DWBaseContactsContentViewController *)contentController {
    if (_contentController == nil) {
        DWRequestsContentViewController *controller =
            [[DWRequestsContentViewController alloc] initWithPayModel:self.payModel
                                                         dataProvider:self.dataProvider];
        controller.itemsDelegate = self;
        controller.delegate = self.contentDelegate ?: self;
        controller.dataSource = self.model.dataSource;
        _contentController = controller;
    }
    return _contentController;
}

@end
