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

#import "DWContactsViewController.h"

#import "DWBaseContactsViewController+DWProtected.h"
#import "DWContactsContentViewController.h"

@implementation DWContactsViewController

@synthesize model = _model;
@synthesize stateController = _stateController;
@synthesize contentController = _contentController;

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Contacts", nil);
    self.searchBar.placeholder = NSLocalizedString(@"Search for a contact", nil);

    UIImage *image = [[UIImage imageNamed:@"dp_add_contact"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithImage:image
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(addContactButtonAction)];
    self.navigationItem.rightBarButtonItem = button;
}

#pragma mark - Private

- (DWContactsModel *)model {
    if (!_model) {
        _model = [[DWContactsModel alloc] init];
        _model.delegate = self;
    }
    return _model;
}

- (DWSearchStateViewController *)stateController {
    if (_stateController == nil) {
        _stateController = [[DWSearchStateViewController alloc] init];
        _stateController.delegate = self;
    }
    return _stateController;
}

- (DWBaseContactsContentViewController *)contentController {
    if (_contentController == nil) {
        DWContactsContentViewController *controller = [[DWContactsContentViewController alloc] initWithStyle:UITableViewStylePlain];
        controller.model = self.model;
        controller.delegate = self;
        _contentController = controller;
    }
    return _contentController;
}

@end
