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
#import "DWRequestsViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsViewController () <DWContactsContentControllerDelegate>

@end

NS_ASSUME_NONNULL_END

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
        DWContactsContentViewController *controller =
            [[DWContactsContentViewController alloc] initWithPayModel:self.payModel
                                                         dataProvider:self.dataProvider];
        controller.dataSource = self.model.dataSource;
        controller.itemsDelegate = self;
        controller.delegate = self;
        _contentController = controller;
    }
    return _contentController;
}

#pragma mark - DWBaseContactsContentViewControllerDelegate

- (void)baseContactsContentViewController:(DWBaseContactsContentViewController *)controller didSelect:(id<DWDPBasicUserItem>)item {
    if (self.intent == DWContactsControllerIntent_Default) {
        [super baseContactsContentViewController:controller didSelect:item];
    }
    else {
        [self.payDelegate contactsViewController:self payToItem:item];
    }
}

#pragma mark -  DWContactsContentControllerDelegate

- (void)contactsContentController:(DWContactsContentViewController *)controller
       contactsFilterButtonAction:(UIButton *)sender {
    NSString *title = NSLocalizedString(@"Sort Contacts", nil);
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Name", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        self.model.sortMode = DWContactsSortMode_ByUsername;
                    }];
        [alert addAction:action];
    }

    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Cancel", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:action];
    }

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = sender;
        alert.popoverPresentationController.sourceRect = sender.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)contactsContentController:(DWContactsContentViewController *)controller
      contactRequestsButtonAction:(UIButton *)sender {
    DWRequestsModel *requestsModel = [self.model contactRequestsModel];
    DWRequestsViewController *requestsController =
        [[DWRequestsViewController alloc] initWithModel:requestsModel
                                               payModel:self.payModel
                                           dataProvider:self.dataProvider];
    if (self.intent == DWContactsControllerIntent_PayToSelector) {
        requestsController.contentDelegate = self;
    }
    [self.navigationController pushViewController:requestsController animated:YES];
}

@end
