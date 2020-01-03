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

#import "DWUpholdTransferViewController.h"

#import <DWAlertController/DWAlertController.h>

#import "DWUpholdAmountModel.h"
#import "DWUpholdConfirmViewController.h"
#import "DWUpholdOTPProvider.h"
#import "DWUpholdOTPViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdTransferViewController () <DWUpholdAmountModelStateNotifier, DWUpholdConfirmViewControllerDelegate, DWUpholdOTPProvider>

@property (readonly, nonatomic, strong) DWUpholdAmountModel *upholdAmountModel;

@end

NS_ASSUME_NONNULL_END

@implementation DWUpholdTransferViewController

- (instancetype)initWithCard:(DWUpholdCardObject *)card {
    DWUpholdAmountModel *model = [[DWUpholdAmountModel alloc] initWithCard:card];

    self = [super initWithModel:model];
    if (self) {
    }
    return self;
}

- (DWUpholdAmountModel *)upholdAmountModel {
    return (DWUpholdAmountModel *)self.model;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Transfer", @"A verb, button title.");
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Uphold", nil);

    self.upholdAmountModel.stateNotifier = self;

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(contentSizeCategoryDidChangeNotification)
                               name:UIContentSizeCategoryDidChangeNotification
                             object:nil];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self.upholdAmountModel resetAttributedValues];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self.upholdAmountModel resetAttributedValues];
}

#pragma mark - Actions

- (void)actionButtonAction:(id)sender {
    BOOL inputValid = [self validateInputAmount];
    if (!inputValid) {
        return;
    }

    [self.upholdAmountModel createTransactionWithOTPToken:nil];
}

#pragma mark - DWUpholdAmountModelStateNotifier

- (void)upholdAmountModel:(DWUpholdAmountModel *)model
           didUpdateState:(DWUpholdRequestTransferModelState)state {
    switch (state) {
        case DWUpholdRequestTransferModelState_None: {
            self.view.userInteractionEnabled = YES;
            [self hideActivityIndicator];

            break;
        }
        case DWUpholdRequestTransferModelState_Loading: {
            self.view.userInteractionEnabled = NO;
            [self showActivityIndicator];

            break;
        }
        case DWUpholdRequestTransferModelState_Success: {
            DWUpholdConfirmViewController *controller = [[DWUpholdConfirmViewController alloc] initWithModel:[self.upholdAmountModel transferModel]];
            controller.resultDelegate = self;
            controller.otpProvider = self;
            [self presentViewController:controller animated:YES completion:nil];

            self.view.userInteractionEnabled = YES;
            [self hideActivityIndicator];

            break;
        }
        case DWUpholdRequestTransferModelState_Fail: {
            self.view.userInteractionEnabled = YES;
            [self hideActivityIndicator];
            [self showErrorWithMessage:NSLocalizedString(@"Something went wrong", nil)];

            break;
        }
        case DWUpholdRequestTransferModelState_FailInsufficientFunds: {
            self.view.userInteractionEnabled = YES;
            [self hideActivityIndicator];
            [self showErrorWithMessage:NSLocalizedString(@"Fee is greater than balance", nil)];

            break;
        }
        case DWUpholdRequestTransferModelState_OTP: {
            __weak typeof(self) weakSelf = self;
            [self requestOTPWithCompletion:^(NSString *_Nullable otpToken) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                if (otpToken) {
                    [strongSelf.upholdAmountModel createTransactionWithOTPToken:otpToken];
                }
                else {
                    [strongSelf.upholdAmountModel resetCreateTransactionState];
                }
            }];

            break;
        }
    }
}

#pragma mark - DWUpholdConfirmViewControllerDelegate

- (void)upholdConfirmViewController:(DWUpholdConfirmViewController *)controller
                 didSendTransaction:(DWUpholdTransactionObject *)transaction {
    [self.delegate upholdTransferViewController:self didSendTransaction:transaction];
}

#pragma mark - DWUpholdOTPProvider

- (void)requestOTPWithCompletion:(void (^)(NSString *_Nullable otpToken))completion {
    DWUpholdOTPViewController *otpController = [DWUpholdOTPViewController controllerWithCompletion:^(DWUpholdOTPViewController *_Nonnull controller, NSString *_Nullable otpToken) {
        [controller dismissViewControllerAnimated:YES completion:nil];

        if (completion) {
            completion(otpToken);
        }
    }];

    DWAlertController *alertOTPController = [DWAlertController alertControllerWithContentController:otpController];
    [alertOTPController setupActions:otpController.providedActions];
    alertOTPController.preferredAction = otpController.preferredAction;

    UIViewController *presenting = self;
    if (self.presentedViewController) {
        presenting = self.presentedViewController;
    }

    [presenting presentViewController:alertOTPController animated:YES completion:nil];
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
