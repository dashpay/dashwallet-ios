//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWSetupViewController.h"

#import "DWCreateNewWalletViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSetupViewController ()

@property (strong, nonatomic) IBOutlet UIButton *createWalletButton;
@property (strong, nonatomic) IBOutlet UIButton *recoverWalletButton;

@end

@implementation DWSetupViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Setup" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (IBAction)createWalletButtonAction:(id)sender {
    DWCreateNewWalletViewController *controller = [DWCreateNewWalletViewController controller];
    [self.navigationController pushViewController:controller animated:YES];
}

- (IBAction)recoverWalletButtonAction:(id)sender {
}

#pragma mark - Private

- (void)setupView {
    [self.createWalletButton setTitle:NSLocalizedString(@"Create a New Wallet", nil) forState:UIControlStateNormal];
    [self.recoverWalletButton setTitle:NSLocalizedString(@"Recover Wallet", nil) forState:UIControlStateNormal];
}

@end

NS_ASSUME_NONNULL_END
