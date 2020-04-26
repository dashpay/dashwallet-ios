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

#import "DWSendAmountModel.h"

#import "DWAmountModel+DWProtected.h"
#import "DWEnvironment.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

@implementation DWSendAmountModel

- (instancetype)initWithSendingDestination:(nullable NSString *)sendingDestination
                            paymentDetails:(nullable DSPaymentProtocolDetails *)paymentDetails {
    self = [super init];
    if (self) {
        _sendingOptions = [[DWAmountSendingOptionsModel alloc]
            initWithSendingDestination:sendingDestination
                        paymentDetails:paymentDetails];
    }

    return self;
}

- (BOOL)showsMaxButton {
    return YES;
}

- (void)selectAllFundsWithPreparationBlock:(void (^)(void))preparationBlock {
    void (^selectAllFundsBlock)(void) = ^{
        preparationBlock();

        DSPriceManager *priceManager = [DSPriceManager sharedInstance];
        DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
        const uint64_t allAvailableFunds = account.maxOutputAmount;

        if (allAvailableFunds > 0) {
            self.amountEnteredInDash = [[DWAmountObject alloc] initWithPlainAmount:allAvailableFunds];
            self.amountEnteredInLocalCurrency = nil;
            [self updateCurrentAmount];
        }
    };

    DSAuthenticationManager *authManager = [DSAuthenticationManager sharedInstance];
    if (authManager.didAuthenticate) {
        selectAllFundsBlock();
    }
    else {
        [authManager authenticateWithPrompt:nil
               usingBiometricAuthentication:YES
                             alertIfLockout:YES
                                 completion:^(BOOL authenticatedOrSuccess, BOOL usedBiometrics, BOOL cancelled) {
                                     if (authenticatedOrSuccess) {
                                         selectAllFundsBlock();
                                     }
                                 }];
    }
}

- (void)updateCurrentAmount {
    [super updateCurrentAmount];

    const int64_t plainAmount = self.amount.plainAmount;

    [self.sendingOptions updateWithAmount:plainAmount];

    NSString *descriptionText = nil;
    switch (self.sendingOptions.state) {
        case DWAmountSendOptionsModelState_None: {
            break;
        }
        case DWAmountSendOptionsModelState_Regular: {
            descriptionText = NSLocalizedString(@"This transaction may take several minutes to settle.", nil);

            break;
        }
        case DWAmountSendOptionsModelState_AutoLocks: {
            descriptionText = NSLocalizedString(@"This transaction should settle instantly at no extra fee", nil);

            break;
        }
    }

    DWAmountDescriptionViewModel *descriptionModel = [[DWAmountDescriptionViewModel alloc] init];

    // Insufficient funds message prioritized over other messages

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    const uint64_t allAvailableFunds = account.maxOutputAmount;
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    const BOOL canShowInsufficientFunds = (authenticationManager.didAuthenticate ||
                                           self.insufficientFundsErrorWasShown);
    if (canShowInsufficientFunds && plainAmount > allAvailableFunds) {
        NSDictionary<NSAttributedStringKey, id> *attributes = @{
            NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCallout],
            NSForegroundColorAttributeName : [UIColor dw_redColor],
        };
        NSAttributedString *descriptionAttributed =
            [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Insufficient funds", nil)
                                            attributes:attributes];

        descriptionModel.attributedText = descriptionAttributed;
    }
    else {
        descriptionModel.text = descriptionText;
    }

    self.descriptionModel = descriptionModel;
}

@end
