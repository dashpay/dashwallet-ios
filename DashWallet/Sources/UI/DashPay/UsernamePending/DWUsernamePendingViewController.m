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

#import "DWUsernamePendingViewController.h"

#import "DWUsernamePendingContentViewController.h"
#import "UIViewController+DWEmbedding.h"

@interface DWUsernamePendingViewController ()

@property (null_resettable, strong, nonatomic) DWUsernamePendingContentViewController *contentController;

@end

@implementation DWUsernamePendingViewController

- (void)setUsername:(NSString *)username {
    _username = username;
    self.contentController.username = username;
}

- (NSString *)actionButtonTitle {
    // TODO: Localize
    return @"Let me know when it’s done";
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.hidesBottomBarWhenPushed = YES;
    self.actionButton.enabled = YES;

    // TODO: Localize
    self.title = @"Dash Username";

    UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [self setupContentView:contentView];

    [self dw_embedChild:self.contentController inContainer:contentView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (DWUsernamePendingContentViewController *)contentController {
    if (_contentController == nil) {
        _contentController = [[DWUsernamePendingContentViewController alloc] init];
    }

    return _contentController;
}

- (void)actionButtonAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
