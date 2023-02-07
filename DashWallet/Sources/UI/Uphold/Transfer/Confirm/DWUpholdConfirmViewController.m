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

#import "DWUpholdConfirmViewController.h"

#import "DWUpholdConfirmTransferModel.h"
#import "DWUpholdTransactionObject+DWView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdConfirmViewController () <DWUpholdConfirmTransferModelStateNotifier, DWConfirmPaymentViewControllerDelegate>

@property (nonatomic, strong) DWUpholdConfirmTransferModel *transferModel;

@end

NS_ASSUME_NONNULL_END

@implementation DWUpholdConfirmViewController

- (instancetype)initWithModel:(DWUpholdConfirmTransferModel *)transferModel {
    self = [super init];
    if (self) {
        _transferModel = transferModel;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.delegate = self;
    self.model = self.transferModel.transaction;
    self.transferModel.stateNotifier = self;
}

#pragma mark - DWUpholdConfirmTransferModelStateNotifier

- (void)upholdConfirmTransferModel:(DWUpholdConfirmTransferModel *)model
                    didUpdateState:(DWUpholdConfirmTransferModelState)state {
    switch (state) {
        case DWUpholdConfirmTransferModelState_None: {
            self.sendingEnabled = YES;

            break;
        }
        case DWUpholdConfirmTransferModelState_Loading: {
            self.sendingEnabled = NO;

            break;
        }
        case DWUpholdConfirmTransferModelState_Success: {
            [self dismissViewControllerAnimated:YES
                                     completion:^{
                                         [self.resultDelegate upholdConfirmViewController:self
                                                                       didSendTransaction:self.transferModel.transaction];
                                     }];

            break;
        }
        case DWUpholdConfirmTransferModelState_Fail: {
            self.sendingEnabled = YES;

            break;
        }
        case DWUpholdConfirmTransferModelState_OTP: {
            __weak typeof(self) weakSelf = self;
            [self.otpProvider requestOTPWithCompletion:^(NSString *_Nullable otpToken) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                if (otpToken) {
                    [strongSelf.transferModel confirmWithOTPToken:otpToken];
                }
                else {
                    [strongSelf.transferModel resetState];
                }
            }];

            break;
        }
    }

    if (state == DWUpholdConfirmTransferModelState_Fail) {
        [self showErrorWithMessage:NSLocalizedString(@"Something went wrong", nil)];
    }
}

#pragma mark - DWConfirmPaymentViewControllerDelegate

- (void)confirmPaymentViewControllerDidConfirm:(DWConfirmPaymentViewController *)controller {
    [self.transferModel confirmWithOTPToken:nil];
}

- (void)confirmPaymentViewControllerDidCancel:(nonnull DWConfirmPaymentViewController *)controller {
    [self.resultDelegate upholdConfirmViewControllerDidCancelTransaction:self];
}


#pragma mark - Private

- (void)showErrorWithMessage:(NSString *)message {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Uphold", nil)
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:okAction];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
