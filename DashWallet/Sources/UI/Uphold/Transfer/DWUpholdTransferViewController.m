//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWUpholdConfirmTransferViewController.h"
#import "DWUpholdOTPProvider.h"
#import "DWUpholdOTPViewController.h"
#import "DWUpholdRequestTransferViewController.h"
#import "DWUpholdSuccessTransferViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdTransferViewController () <DWUpholdOTPProvider,
                                              DWUpholdRequestTransferViewControllerDelegate,
                                              DWUpholdConfirmTransferViewControllerDelegate,
                                              DWUpholdSuccessTransferViewControllerDelegate>

@property (readonly, strong, nonatomic) DWUpholdCardObject *card;
@property (readonly, strong, nonatomic) DWUpholdRequestTransferViewController *requestController;

@end

@implementation DWUpholdTransferViewController

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card {
    DWUpholdTransferViewController *controller = [[DWUpholdTransferViewController alloc] initWithCard:card];
    return controller;
}

- (instancetype)initWithCard:(DWUpholdCardObject *)card {
    DWUpholdRequestTransferViewController *requestController = [DWUpholdRequestTransferViewController controllerWithCard:card];

    self = [super initWithContentController:requestController];
    if (self) {
        _card = card;

        _requestController = requestController;
        _requestController.delegate = self;
        _requestController.otpProvider = self;
    }
    return self;
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

    [self presentViewController:alertOTPController animated:YES completion:nil];
}

#pragma mark - DWUpholdRequestTransferViewControllerDelegate

- (void)upholdRequestTransferViewController:(DWUpholdRequestTransferViewController *)controller
                      didProduceTransaction:(DWUpholdTransactionObject *)transaction {
    DWUpholdConfirmTransferViewController *confirmController =
        [DWUpholdConfirmTransferViewController controllerWithCard:self.card
                                                      transaction:transaction];
    confirmController.delegate = self;
    confirmController.otpProvider = self;

    [self performTransitionToContentController:confirmController animated:YES];
    [self setupActions:confirmController.providedActions];
    self.preferredAction = confirmController.preferredAction;
}

- (void)upholdRequestTransferViewControllerDidCancel:(DWUpholdRequestTransferViewController *)controller {
    [self.delegate upholdTransferViewControllerDidCancel:self];
}

#pragma mark - DWUpholdConfirmTransferViewControllerDelegate

- (void)upholdConfirmTransferViewControllerDidCancel:(DWUpholdConfirmTransferViewController *)controller {
    NSParameterAssert(self.contentController);
    [self performTransitionToContentController:self.requestController animated:YES];
    [self setupActions:self.requestController.providedActions];
    self.preferredAction = self.requestController.preferredAction;
}

- (void)upholdConfirmTransferViewControllerDidFinish:(DWUpholdConfirmTransferViewController *)controller transaction:(DWUpholdTransactionObject *)transaction {
    DWUpholdSuccessTransferViewController *successController =
        [DWUpholdSuccessTransferViewController controllerWithTransaction:transaction];
    successController.delegate = self;

    [self performTransitionToContentController:successController animated:YES];
    [self setupActions:successController.providedActions];
    self.preferredAction = successController.preferredAction;
}

#pragma mark - DWUpholdSuccessTransferViewControllerDelegate

- (void)upholdSuccessTransferViewControllerDidFinish:(DWUpholdSuccessTransferViewController *)controller {
    [self.delegate upholdTransferViewControllerDidFinish:self];
}

- (void)upholdSuccessTransferViewControllerDidFinish:(DWUpholdSuccessTransferViewController *)controller
                                  openTransactionURL:(NSURL *)url {
    [self.delegate upholdTransferViewControllerDidFinish:self openTransactionURL:url];
}

@end

NS_ASSUME_NONNULL_END
