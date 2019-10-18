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

#import "DWResetWalletInfoViewController.h"

#import "DWRecoverViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWResetWalletInfoViewController () <DWRecoverViewControllerDelegate>

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UIButton *continueButton;
@property (strong, nonatomic) IBOutlet UIButton *cancelButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWResetWalletInfoViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"ResetWalletInfo" bundle:nil];
    DWResetWalletInfoViewController *controller = [storyboard instantiateInitialViewController];
    controller.hidesBottomBarWhenPushed = YES;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (IBAction)continueButtonAction:(id)sender {
    DWRecoverViewController *controller = [[DWRecoverViewController alloc] init];
    controller.hidesBottomBarWhenPushed = YES;
    controller.action = DWRecoverAction_Wipe;
    controller.delegate = self;
    [self.navigationController pushViewController:controller animated:YES];
}

- (IBAction)cancelButtonAction:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - DWRecoverViewControllerDelegate

- (void)recoverViewControllerDidRecoverWallet:(DWRecoverViewController *)controller {
    NSAssert(NO, @"Inconsistent state");
}

- (void)recoverViewControllerDidWipe:(DWRecoverViewController *)controller {
    [self.delegate didWipeWallet];
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Wipe Wallet", nil);

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];

    self.titleLabel.text = NSLocalizedString(@"Warning", nil);
    self.descriptionLabel.text = NSLocalizedString(@"You are about to wipe this wallet from this device. Funds associated with this wallet can only be retrieved if you have your recovery phrase.", nil);

    [self.continueButton setTitle:NSLocalizedString(@"Continue", nil)
                         forState:UIControlStateNormal];
    [self.cancelButton setTitle:NSLocalizedString(@"Cancel", nil)
                       forState:UIControlStateNormal];
}

@end

NS_ASSUME_NONNULL_END
