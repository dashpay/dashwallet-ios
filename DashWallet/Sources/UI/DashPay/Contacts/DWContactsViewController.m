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
#import "DWContactsModel.h"
#import "DWUserSearchViewController.h"

@interface DWContactsViewController () <DWContactsContentViewDelegate>

@property (nonatomic, strong) DWContactsContentView *view;
@property (nonatomic, strong) DWContactsModel *model;

@end

@implementation DWContactsViewController

@dynamic view;

- (DWContactsModel *)model {
    if (!_model) {
        _model = [[DWContactsModel alloc] init];
    }

    return _model;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)loadView {
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWContactsContentView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.delegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Contacts", nil);

    UIImage *image = [[UIImage imageNamed:@"dp_add_contact"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithImage:image
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(addContactButtonAction)];
    self.navigationItem.rightBarButtonItem = button;

    self.view.model = self.model;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (void)addContactButtonAction {
    DWUserSearchViewController *controller = [[DWUserSearchViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - DWContactsContentViewDelegate

- (void)contactsContentView:(DWContactsContentView *)view didSelectContact:(id<DWContactItem>)contact {
}

- (void)contactsContentView:(DWContactsContentView *)view didAcceptContact:(id<DWContactItem>)contact {
    NSLog(@"accept");
}

- (void)contactsContentView:(DWContactsContentView *)view didDeclineContact:(id<DWContactItem>)contact {
    NSLog(@"decline");
}

@end
