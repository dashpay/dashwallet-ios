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

#import "DWUpholdBuyViewController.h"

#import "DWUpholdBuyInputViewController.h"
#import "DWUpholdConfirmTransferViewController.h"
#import "DWUpholdOTPProvider.h"
#import "DWUpholdOTPViewController.h"
#import "DWUpholdSelectCardViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdBuyViewController () <DWUpholdOTPProvider,
                                         DWUpholdSelectCardViewControllerDelegate,
                                         DWUpholdBuyInputViewControllerDelegate,
                                         DWUpholdConfirmTransferViewControllerDelegate>

@property (readonly, strong, nonatomic) DWUpholdCardObject *dashCard;
@property (readonly, copy, nonatomic) NSArray<DWUpholdCardObject *> *fiatCards;
@property (nullable, strong, nonatomic) DWUpholdCardObject *selectedCard;
@property (readonly, strong, nonatomic) DWUpholdSelectCardViewController *selectController;
@property (null_resettable, strong, nonatomic) DWUpholdBuyInputViewController *inputController;

@end

@implementation DWUpholdBuyViewController

+ (instancetype)controllerWithDashCard:(DWUpholdCardObject *)dashCard
                             fiatCards:(NSArray<DWUpholdCardObject *> *)fiatCards {
    DWUpholdBuyViewController *controller = [[DWUpholdBuyViewController alloc] init];
    return controller;
}

- (instancetype)initWithDashCard:(DWUpholdCardObject *)dashCard
                       fiatCards:(NSArray<DWUpholdCardObject *> *)fiatCards {
    DWUpholdSelectCardViewController *controller = [DWUpholdSelectCardViewController controllerWithCards:fiatCards];
    self = [super initWithContentController:controller];
    if (self) {
        _dashCard = dashCard;
        _fiatCards = [fiatCards copy];

        _selectController = controller;
        _selectController.delegate = self;

        [self setupActions:controller.providedActions];
        self.preferredAction = controller.preferredAction;
    }
    return self;
}

- (DWUpholdBuyInputViewController *)inputController {
    if (!_inputController) {
        DWUpholdBuyInputViewController *inputController = [DWUpholdBuyInputViewController controllerWithDashCard:self.dashCard
                                                                                                        fromCard:self.selectedCard];
        inputController.delegate = self;
        inputController.otpProvider = self;
        _inputController = inputController;
    }
    return _inputController;
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

#pragma mark - DWUpholdSelectAccountViewController

- (void)upholdSelectCardViewController:(DWUpholdSelectCardViewController *)controller didSelectCard:(DWUpholdCardObject *)card {
    self.selectedCard = card;
    self.inputController = nil; // reset
    [self showInputController];
}

- (void)upholdSelectCardViewControllerDidCancel:(DWUpholdSelectCardViewController *)controller {
    [self.delegate upholdBuyViewControllerDidCancel:self];
}

#pragma mark - DWUpholdBuyInputViewControllerDelegate

- (void)upholdBuyInputViewController:(DWUpholdBuyInputViewController *)controller
               didProduceTransaction:(DWUpholdTransactionObject *)transaction {
    DWUpholdConfirmTransferViewController *confirmController =
        [DWUpholdConfirmTransferViewController controllerWithCard:self.dashCard
                                                      transaction:transaction];
    confirmController.delegate = self;
    confirmController.otpProvider = self;

    [self performTransitionToContentController:confirmController animated:YES];
    [self setupActions:confirmController.providedActions];
    self.preferredAction = confirmController.preferredAction;
}

- (void)upholdBuyInputViewControllerDidCancel:(DWUpholdBuyInputViewController *)controller {
    [self showSelectController];
}

#pragma mark - DWUpholdConfirmTransferViewControllerDelegate

- (void)upholdConfirmTransferViewControllerDidCancel:(DWUpholdConfirmTransferViewController *)controller {
    [self showInputController];
}

- (void)upholdConfirmTransferViewControllerDidFinish:(DWUpholdConfirmTransferViewController *)controller transaction:(DWUpholdTransactionObject *)transaction {
    [self.delegate upholdBuyViewControllerDidFinish:self];
}

#pragma mark - Private

- (void)showSelectController {
    NSParameterAssert(self.contentController);

    [self performTransitionToContentController:self.selectController animated:YES];
    [self setupActions:self.selectController.providedActions];
    self.preferredAction = self.selectController.preferredAction;
}

- (void)showInputController {
    DWUpholdBuyInputViewController *inputController = self.inputController;

    [self performTransitionToContentController:inputController animated:YES];
    [self setupActions:inputController.providedActions];
    self.preferredAction = inputController.preferredAction;
}

@end

NS_ASSUME_NONNULL_END
