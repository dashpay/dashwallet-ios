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

#import "DWCreateUsernameViewController.h"

#import "DWConfirmUsernameViewController.h"
#import "DWInputUsernameViewController.h"
#import "UIViewController+DWEmbedding.h"

@interface DWCreateUsernameViewController () <DWInputUsernameViewControllerDelegate, DWConfirmUsernameViewControllerDelegate>

@property (nonatomic, strong) DWInputUsernameViewController *inputUsername;

@end

@implementation DWCreateUsernameViewController

- (NSString *)actionButtonTitle {
    // TODO: Localize
    return @"Register";
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.hidesBottomBarWhenPushed = YES;

    // TODO: Localize
    self.title = @"Dash Username";

    UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [self setupContentView:contentView];

    [self dw_embedChild:self.inputUsername inContainer:contentView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (DWInputUsernameViewController *)inputUsername {
    if (_inputUsername == nil) {
        _inputUsername = [DWInputUsernameViewController controller];
        _inputUsername.delegate = self;
    }

    return _inputUsername;
}

- (void)actionButtonAction:(id)sender {
    DWConfirmUsernameViewController *controller = [[DWConfirmUsernameViewController alloc] init];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - DWInputUsernameViewControllerDelegate

- (void)inputUsernameViewControllerDidUpdateText:(DWInputUsernameViewController *)controller {
    // TODO: validation logic
    self.actionButton.enabled = controller.text.length > 0;
}

#pragma mark - DWConfirmUsernameViewControllerDelegate

- (void)confirmUsernameViewControllerDidConfirm:(DWConfirmUsernameViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

@end
