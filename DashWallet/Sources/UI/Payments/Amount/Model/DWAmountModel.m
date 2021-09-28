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

#import "DWAmountModel+DWProtected.h"

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import <DashSync/DSCurrencyPriceObject.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWAmountModel

- (instancetype)initWithContactItem:(nullable id<DWDPBasicUserItem>)contactItem {
    self = [super init];
    if (self) {
        _contactItem = contactItem;

        _localFormatter = [[DSPriceManager sharedInstance].localFormat copy];
        _currencyCode = [DSPriceManager sharedInstance].localCurrencyCode;

        _dashValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeDash];
        _localCurrencyValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeLocalCurrency];

        DWAmountObject *amount = [[DWAmountObject alloc] initWithDashAmountString:@"0"
                                                                   localFormatter:_localFormatter
                                                                     currencyCode:_currencyCode];
        _amountEnteredInDash = amount;
        _amount = amount;

        [self updateCurrentAmount];
    }
    return self;
}

- (BOOL)showsMaxButton {
    return NO;
}

- (BOOL)amountIsValidForProceeding {
    return self.amount.plainAmount > 0;
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
                                                                               localCurrencyValidator:self.localCurrencyValidator
                                                                                       localFormatter:self.localFormatter
                                                                                         currencyCode:self.currencyCode];
        }
        self.activeType = DWAmountTypeSupplementary;
    }
    else {
        if (!self.amountEnteredInDash) {
            self.amountEnteredInDash = [[DWAmountObject alloc] initAsDashWithPreviousAmount:self.amountEnteredInLocalCurrency
                                                                              dashValidator:self.dashValidator
                                                                             localFormatter:self.localFormatter
                                                                               currencyCode:self.currencyCode];
        }
        self.activeType = DWAmountTypeMain;
    }
    [self updateCurrentAmount];
}

- (void)rebuildAmounts {
    if (self.activeType == DWAmountTypeMain) {
        self.amountEnteredInDash = [[DWAmountObject alloc] initWithDashAmountString:self.amountEnteredInDash.amountInternalRepresentation
                                                                     localFormatter:self.localFormatter
                                                                       currencyCode:self.currencyCode];
        self.amountEnteredInLocalCurrency = nil;
    }
    else {
        self.amountEnteredInLocalCurrency = [[DWAmountObject alloc] initWithLocalAmountString:self.amountEnteredInLocalCurrency.amountInternalRepresentation
                                                                               localFormatter:self.localFormatter
                                                                                 currencyCode:self.currencyCode];
        self.amountEnteredInDash = nil;
    }

    [self updateCurrentAmount];
}

- (void)setupCurrencyCode:(NSString *)currencyCode {
    self.localFormatter.currencyCode = currencyCode;
    self.currencyCode = currencyCode;

    DSCurrencyPriceObject *priceObject = [[DSPriceManager sharedInstance] priceForCurrencyCode:currencyCode];

    self.localFormatter.maximum =
        [[NSDecimalNumber decimalNumberWithDecimal:priceObject.price.decimalValue]
            decimalNumberByMultiplyingBy:(id)[NSDecimalNumber numberWithLongLong:MAX_MONEY / DUFFS]];

    [self rebuildAmounts];
}

- (void)updateAmountWithReplacementString:(NSString *)string range:(NSRange)range {
    NSString *lastInputString = self.amount.amountInternalRepresentation;
    NSString *validatedResult = [self validatedStringFromLastInputString:lastInputString range:range replacementString:string];
    if (!validatedResult) {
        return;
    }

    if (self.activeType == DWAmountTypeMain) {
        self.amountEnteredInDash = [[DWAmountObject alloc] initWithDashAmountString:validatedResult
                                                                     localFormatter:self.localFormatter
                                                                       currencyCode:self.currencyCode];
        self.amountEnteredInLocalCurrency = nil;
    }
    else {
        DWAmountObject *amount = [[DWAmountObject alloc] initWithLocalAmountString:validatedResult
                                                                    localFormatter:self.localFormatter
                                                                      currencyCode:self.currencyCode];
        if (!amount) { // entered amount is invalid (Dash amount exceeds limit)
            return;
        }

        self.amountEnteredInLocalCurrency = amount;
        self.amountEnteredInDash = nil;
    }
    [self updateCurrentAmount];
}

- (void)selectAllFundsWithPreparationBlock:(void (^)(void))preparationBlock {
    NSAssert(NO, @"To be overriden");
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

- (void)reloadAttributedData {
    [self.amountEnteredInDash reloadAttributedData];
    [self.amountEnteredInLocalCurrency reloadAttributedData];
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
}

@end

NS_ASSUME_NONNULL_END
