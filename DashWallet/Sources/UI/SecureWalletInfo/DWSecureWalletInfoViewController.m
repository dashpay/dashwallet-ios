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

#import "DWSecureWalletInfoViewController.h"

#import "DWBackupInfoViewController.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSecureWalletInfoViewController ()

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UIButton *secureNowButton;
@property (strong, nonatomic) IBOutlet UIButton *skipButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWSecureWalletInfoViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"SecureWalletInfo" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

#pragma mark - DWRootNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Actions

- (IBAction)secureNowButtonAction:(id)sender {
    DWBackupInfoViewController *controller = [DWBackupInfoViewController controller];
    [self.navigationController pushViewController:controller animated:YES];
}

- (IBAction)skipButtonAction:(id)sender {
    [self.delegate secureWalletInfoViewControllerDidFinish:self];
}

#pragma mark - Private

- (void)setupView {
    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];

    self.titleLabel.text = NSLocalizedString(@"Secure Wallet Now", nil);
    self.descriptionLabel.text = NSLocalizedString(@"If you lose this device, you will lose your funds. Get your UniqueSecretKey so that you can restore your wallet on another device.", nil);

    [self.secureNowButton setTitle:NSLocalizedString(@"Secure now", nil)
                          forState:UIControlStateNormal];
    [self.skipButton setTitle:NSLocalizedString(@"Skip", nil)
                     forState:UIControlStateNormal];
}

@end

NS_ASSUME_NONNULL_END
