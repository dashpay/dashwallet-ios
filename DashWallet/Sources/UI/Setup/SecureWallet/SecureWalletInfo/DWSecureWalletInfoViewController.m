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

#import <DashSync/DashSync.h>

#import "DWAuthenticationManager.h"
#import "DWBackupInfoViewController.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSecureWalletInfoViewController ()

@property (strong, nonatomic) DWPreviewSeedPhraseModel *seedPhraseModel;

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

    if (self.type == DWSecureWalletInfoType_Setup) {
        // Create wallet entry point
        self.seedPhraseModel = [[DWPreviewSeedPhraseModel alloc] init];
        [self.seedPhraseModel getOrCreateNewWallet];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Actions

- (IBAction)secureNowButtonAction:(id)sender {
    if (self.type == DWSecureWalletInfoType_Setup) {
        [self showBackupInfoController];
    }
    else {
        [DWAuthenticationManager
            authenticateWithPrompt:nil
                        biometrics:NO
                    alertIfLockout:YES
                        completion:^(BOOL authenticated, BOOL cancelled) {
                            if (!authenticated) {
                                return;
                            }

                            self.seedPhraseModel = [[DWPreviewSeedPhraseModel alloc] init];
                            [self.seedPhraseModel getOrCreateNewWallet];

                            [self showBackupInfoController];
                        }];
    }
}

- (IBAction)skipButtonAction:(id)sender {
    [self.delegate secureWalletRoutineDidCanceled:self];
}

#pragma mark - Private

- (void)setupView {
    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];

    self.titleLabel.text = NSLocalizedString(@"Secure Wallet Now", nil);

    NSString *descriptionText = nil;
    switch (self.type) {
        case DWSecureWalletInfoType_Setup: {
            descriptionText = NSLocalizedString(@"If you lose this device, you will lose your funds. Get your UniqueSecretKey so that you can restore your wallet on another device.", nil);
            break;
        }
        case DWSecureWalletInfoType_Reminder: {
            descriptionText = NSLocalizedString(@"You received Dash! If you lose this device, you will lose your funds. Get your UniqueSecretKey so that you can restore your wallet on another device.", nil);
            break;
        }
    }
    self.descriptionLabel.text = descriptionText;

    [self.secureNowButton setTitle:NSLocalizedString(@"Secure now", nil)
                          forState:UIControlStateNormal];
    [self.skipButton setTitle:NSLocalizedString(@"Skip", nil)
                     forState:UIControlStateNormal];
}

- (void)showBackupInfoController {
    DWBackupInfoViewController *controller = [DWBackupInfoViewController controllerWithModel:self.seedPhraseModel];
    controller.delegate = self.delegate;
    [self.navigationController pushViewController:controller animated:YES];
}

@end

NS_ASSUME_NONNULL_END
