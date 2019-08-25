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

#import "DWAmountModel.h"

#import "DWAmountInputValidator.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWAmountModel ()

@property (assign, nonatomic) DWAmountType activeType;
@property (strong, nonatomic) DWAmountObject *amount;
@property (assign, nonatomic, getter=isLocked) BOOL locked;

@property (strong, nonatomic) DWAmountInputValidator *dashValidator;
@property (strong, nonatomic) DWAmountInputValidator *localCurrencyValidator;
@property (nullable, strong, nonatomic) DWAmountObject *amountEnteredInDash;
@property (nullable, strong, nonatomic) DWAmountObject *amountEnteredInLocalCurrency;

@end

@implementation DWAmountModel

- (instancetype)initWithInputIntent:(DWAmountInputIntent)inputIntent
                 sendingDestination:(nullable NSString *)sendingDestination
                     paymentDetails:(nullable DSPaymentProtocolDetails *)paymentDetails {
    self = [super init];
    if (self) {
        _inputIntent = inputIntent;

        _dashValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeDash];
        _localCurrencyValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeLocalCurrency];

        DWAmountObject *amount = [[DWAmountObject alloc] initWithDashAmountString:@"0"];
        _amountEnteredInDash = amount;
        _amount = amount;

        _locked = ![DSAuthenticationManager sharedInstance].didAuthenticate;

        switch (inputIntent) {
            case DWAmountInputIntentRequest: {
                _actionButtonTitle = NSLocalizedString(@"Request", nil);

                break;
            }
            case DWAmountInputIntentSend: {
                NSParameterAssert(sendingDestination);
                _actionButtonTitle = NSLocalizedString(@"Pay", nil);
                _sendingOptions = [[DWAmountSendingOptionsModel alloc]
                    initWithSendingDestination:sendingDestination
                                paymentDetails:paymentDetails];

                break;
            }
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(walletBalanceDidChangeNotification:)
                                                     name:DSWalletBalanceDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackgroundNotification:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];

        [self updateCurrentAmount];
    }
    return self;
}

- (BOOL)isSwapToLocalCurrencyAllowed {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    BOOL allowed = priceManager.localCurrencyDashPrice != nil;

    return allowed;
}

- (void)swapActiveAmountType {
    NSAssert([self isSwapToLocalCurrencyAllowed], @"Switching until price is not fetched is not allowed");

    if (self.activeType == DWAmountTypeMain) {
        if (!self.amountEnteredInLocalCurrency) {
            self.amountEnteredInLocalCurrency = [[DWAmountObject alloc] initAsLocalWithPreviousAmount:self.amountEnteredInDash
                                                                               localCurrencyValidator:self.localCurrencyValidator];
        }
        self.activeType = DWAmountTypeSupplementary;
    }
    else {
        if (!self.amountEnteredInDash) {
            self.amountEnteredInDash = [[DWAmountObject alloc] initAsDashWithPreviousAmount:self.amountEnteredInLocalCurrency
                                                                              dashValidator:self.dashValidator];
        }
        self.activeType = DWAmountTypeMain;
    }
    [self updateCurrentAmount];
}

- (void)setAllFundsSelected:(BOOL)allFundsSelected {
    _allFundsSelected = allFundsSelected;

    if (!allFundsSelected) {
        // reset amount
        DWAmountObject *amount = [[DWAmountObject alloc] initWithDashAmountString:@"0"];
        _amountEnteredInDash = amount;

        [self updateCurrentAmount];
    }
}

- (void)updateAmountWithReplacementString:(NSString *)string range:(NSRange)range {
    NSString *lastInputString = self.amount.amountInternalRepresentation;
    NSString *validatedResult = [self validatedStringFromLastInputString:lastInputString range:range replacementString:string];
    if (!validatedResult) {
        return;
    }

    if (self.activeType == DWAmountTypeMain) {
        self.amountEnteredInDash = [[DWAmountObject alloc] initWithDashAmountString:validatedResult];
        self.amountEnteredInLocalCurrency = nil;
    }
    else {
        DWAmountObject *amount = [[DWAmountObject alloc] initWithLocalAmountString:validatedResult];
        if (!amount) { // entered amount is invalid (Dash amount exceeds limit)
            return;
        }

        self.amountEnteredInLocalCurrency = amount;
        self.amountEnteredInDash = nil;
    }
    [self updateCurrentAmount];
}

- (void)unlock {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    [authenticationManager authenticateWithPrompt:nil
                                       andTouchId:YES
                                   alertIfLockout:YES
                                       completion:^(BOOL authenticated, BOOL cancelled) {
                                           self.locked = !authenticated;
                                       }];
}

- (void)selectAllFunds {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    uint64_t allAvailableFunds = [account maxOutputAmountUsingInstantSend:FALSE];

    if (allAvailableFunds > 0) {
        self.amountEnteredInDash = [[DWAmountObject alloc] initWithPlainAmount:allAvailableFunds];
        self.amountEnteredInLocalCurrency = nil;
        [self updateCurrentAmount];
    }
}

- (BOOL)isEnteredAmountLessThenMinimumOutputAmount {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    uint64_t amount = self.amount.plainAmount;

    return amount < chain.minOutputAmount;
}

- (NSString *)minimumOutputAmountFormattedString {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];

    return [priceManager stringForDashAmount:chain.minOutputAmount];
}

#pragma mark - Private

- (nullable NSString *)validatedStringFromLastInputString:(NSString *)lastInputString
                                                    range:(NSRange)range
                                        replacementString:(NSString *)string {
    NSParameterAssert(lastInputString);
    NSParameterAssert(string);

    DWAmountInputValidator *validator = self.activeType == DWAmountTypeMain ? self.dashValidator : self.localCurrencyValidator;
    return [validator validatedStringFromLastInputString:lastInputString range:range replacementString:string];
}

- (void)updateCurrentAmount {
    if (self.activeType == DWAmountTypeMain) {
        NSParameterAssert(self.amountEnteredInDash);
        self.amount = self.amountEnteredInDash;
    }
    else {
        NSParameterAssert(self.amountEnteredInLocalCurrency);
        self.amount = self.amountEnteredInLocalCurrency;
    }

    if (self.inputIntent == DWAmountInputIntentSend) {
        NSParameterAssert(self.sendingOptions);
        [self.sendingOptions updateWithAmount:self.amount.plainAmount];
    }

    if (self.allFundsSelected) {
        self.allFundsSelected = NO;
    }
}

- (void)walletBalanceDidChangeNotification:(NSNotification *)n {
    self.locked = ![[DSAuthenticationManager sharedInstance] didAuthenticate];
}

- (void)applicationDidEnterBackgroundNotification:(NSNotification *)n {
    self.locked = YES;
}

@end

NS_ASSUME_NONNULL_END
