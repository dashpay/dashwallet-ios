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

#import "DWContactsContentView.h"
#import "DWContactsContentViewController.h"
#import "DWContactsModel.h"
#import "DWUserSearchViewController.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsViewController () <UITableViewDelegate>

@property (nonatomic, strong) DWContactsModel *model;
@property (null_resettable, nonatomic, strong) DWContactsContentViewController *contentController;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsViewController

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Contacts", nil);

    self.disableSearchBarBecomesFirstResponderOnFirstAppearance = YES;
    self.searchBar.placeholder = NSLocalizedString(@"Search for a contact", nil);

    UIImage *image = [[UIImage imageNamed:@"dp_add_contact"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithImage:image
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(addContactButtonAction)];
    self.navigationItem.rightBarButtonItem = button;

    [self dw_embedChild:self.contentController inContainer:self.contentView];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.model start];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.model stop];
}

#pragma mark - Actions

- (void)addContactButtonAction {
    DWUserSearchViewController *controller = [[DWUserSearchViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    id<DWUserDetails> item = [self.model.dataSource userDetailsAtIndexPath:indexPath];
}

#pragma mark - Private

- (DWContactsModel *)model {
    if (!_model) {
        _model = [[DWContactsModel alloc] init];
    }
    return _model;
}

- (DWContactsContentViewController *)contentController {
    if (_contentController == nil) {
        DWContactsContentViewController *controller = [[DWContactsContentViewController alloc] initWithStyle:UITableViewStylePlain];
        controller.model = self.model;
        controller.tableView.delegate = self;
        _contentController = controller;
    }
    return _contentController;
}

@end
