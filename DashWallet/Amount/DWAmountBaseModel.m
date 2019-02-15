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

#import "DWAmountBaseModel.h"

#import "DWAmountInputValidator.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWAmountBaseModel ()

@property (assign, nonatomic) DWAmountType activeType;
@property (strong, nonatomic) DWAmountObject *amount;
@property (assign, nonatomic) DWAmountModelActionState actionState;
@property (nullable, copy, nonatomic) NSAttributedString *balanceString;

@property (strong, nonatomic) DWAmountInputValidator *dashValidator;
@property (strong, nonatomic) DWAmountInputValidator *localCurrencyValidator;
@property (nullable, strong, nonatomic) DWAmountObject *amountEnteredInDash;
@property (nullable, strong, nonatomic) DWAmountObject *amountEnteredInLocalCurrency;

@end

@implementation DWAmountBaseModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _dashValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeDash];
        _localCurrencyValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeLocalCurrency];

        DWAmountObject *amount = [[DWAmountObject alloc] initWithDashAmountString:@"0"];
        _amountEnteredInDash = amount;
        _amount = amount;

        BOOL locked = ![DSAuthenticationManager sharedInstance].didAuthenticate;
        _actionState = locked ? DWAmountModelActionStateLocked : DWAmountModelActionStateUnlockedInactive;

        // TODO: from type
        _actionButtonTitle = NSLocalizedString(@"Request", nil);

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(walletBalanceDidChangeNotification:)
                                                     name:DSWalletBalanceDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackgroundNotification:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];

        [self updateBalanceString];
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
            self.amountEnteredInLocalCurrency = [[DWAmountObject alloc] initAsLocalWithPreviousAmount:self.amountEnteredInDash];
        }
        self.activeType = DWAmountTypeSupplementary;
    }
    else {
        if (!self.amountEnteredInDash) {
            self.amountEnteredInDash = [[DWAmountObject alloc] initAsDashWithPreviousAmount:self.amountEnteredInLocalCurrency];
        }
        self.activeType = DWAmountTypeMain;
    }
    [self updateCurrentAmount];
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
    [DSEventManager saveEvent:@"amount:unlock"];

    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    [authenticationManager authenticateWithPrompt:nil andTouchId:YES alertIfLockout:YES completion:^(BOOL authenticated, BOOL cancelled) {
        if (authenticated) {
            [DSEventManager saveEvent:@"amount:successful_unlock"];

            BOOL hasAmount = self.amount.plainAmount > 0;
            self.actionState = hasAmount ? DWAmountModelActionStateUnlockedActive : DWAmountModelActionStateUnlockedInactive;
        }
    }];
}

- (void)selectAllFunds {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    uint64_t allFunds = wallet.balance;

    // TODO: implement
}

#pragma mark - Private

- (nullable NSString *)validatedStringFromLastInputString:(NSString *)lastInputString
                                                    range:(NSRange)range
                                        replacementString:(NSString *)string {
    NSParameterAssert(lastInputString);
    NSParameterAssert(string);

    DWAmountInputValidator *validator = self.activeType == DWAmountTypeMain ? self.dashValidator : self.localCurrencyValidator;
    return [validator validatedAmountForLastInputString:lastInputString range:range replacementString:string];
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

    if (self.actionState != DWAmountModelActionStateLocked) {
        BOOL hasAmount = self.amount.plainAmount > 0;
        self.actionState = hasAmount ? DWAmountModelActionStateUnlockedActive : DWAmountModelActionStateUnlockedInactive;
    }
}

- (void)updateBalanceString {
    if ([DWEnvironment sharedInstance].currentChainManager.syncProgress < 1.0) {
        self.balanceString = nil;

        return;
    }

    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    NSMutableAttributedString *attributedString = [[priceManager attributedStringForDashAmount:wallet.balance
                                                                                 withTintColor:[UIColor whiteColor]
                                                                          useSignificantDigits:YES] mutableCopy];
    NSString *titleString = [NSString stringWithFormat:@" (%@)",
                                                       [priceManager localCurrencyStringForDashAmount:wallet.balance]];
    [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName : [UIColor whiteColor]}]];
    self.balanceString = attributedString;
}

- (void)walletBalanceDidChangeNotification:(NSNotification *)n {
    [self updateBalanceString];

    if ([[DSAuthenticationManager sharedInstance] didAuthenticate]) {
        BOOL hasAmount = self.amount.plainAmount > 0;
        self.actionState = hasAmount ? DWAmountModelActionStateUnlockedActive : DWAmountModelActionStateUnlockedInactive;
    }
    else {
        self.actionState = DWAmountModelActionStateLocked;
    }
}

- (void)applicationDidEnterBackgroundNotification:(NSNotification *)n {
    self.actionState = DWAmountModelActionStateLocked;
}

@end

NS_ASSUME_NONNULL_END
