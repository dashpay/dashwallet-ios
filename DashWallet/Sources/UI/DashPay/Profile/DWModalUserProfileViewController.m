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

#import "DWModalUserProfileViewController.h"

#import "DWNavigationController.h"
#import "DWUserProfileViewController.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWModalUserProfileViewController ()

@property (nonatomic, strong) DWUserProfileViewController *profileController;

@end

NS_ASSUME_NONNULL_END

@implementation DWModalUserProfileViewController

- (instancetype)initWithItem:(id<DWDPBasicUserItem>)item
                    payModel:(id<DWPayModelProtocol>)payModel
                dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _profileController =
            [[DWUserProfileViewController alloc] initWithItem:item
                                                     payModel:payModel
                                                 dataProvider:dataProvider
                                           shouldSkipUpdating:YES];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"payments_nav_cross"]
                                                                     style:UIBarButtonItemStyleDone
                                                                    target:self
                                                                    action:@selector(cancelButtonAction)];
    self.profileController.navigationItem.rightBarButtonItem = cancelButton;

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:self.profileController];
    [self dw_embedChild:navigationController];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.profileController.view setNeedsLayout];
    [self.profileController.view layoutIfNeeded];
}

- (void)cancelButtonAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
