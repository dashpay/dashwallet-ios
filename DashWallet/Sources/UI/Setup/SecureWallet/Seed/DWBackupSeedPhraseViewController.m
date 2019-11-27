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

#import "DWBackupSeedPhraseViewController.h"

#import "DWPreviewSeedPhraseModel.h"
#import "DWPreviewSeedPhraseViewController+DWProtected.h"
#import "DWSeedPhraseModel.h"
#import "DWVerifySeedPhraseViewController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWBackupSeedPhraseViewController

+ (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Continue", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Backup Wallet", nil);
    self.actionButton.enabled = NO;

    self.contentView.displayType = DWSeedPhraseDisplayType_Backup;
}

- (void)actionButtonAction:(id)sender {
    DWSeedPhraseModel *seedPhrase = self.contentView.model;

    DWVerifySeedPhraseViewController *controller = [DWVerifySeedPhraseViewController
        controllerWithSeedPhrase:seedPhrase];
    controller.delegate = self.delegate;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)screenshotAlertOKAction {
    if (self.shouldCreateNewWalletOnScreenshot == NO) {
        return;
    }

    [self.model clearAllWallets];

    [self.feedbackGenerator notificationOccurred:UINotificationFeedbackTypeError];

    DWSeedPhraseModel *seedPhrase = [self.model getOrCreateNewWallet];
    [self.contentView updateSeedPhraseModelAnimated:seedPhrase];
    [self.contentView showScreenshotDetectedErrorMessage];

    self.actionButton.enabled = NO;
}

@end

NS_ASSUME_NONNULL_END
