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

#import "DWUpholdAmountModel.h"

#import "DWAmountModel+DWProtected.h"
#import "DWEnvironment.h"
#import "DWUpholdCardObject.h"
#import "DWUpholdClient.h"
#import "DWUpholdConfirmTransferModel.h"
#import "DWUpholdTransactionObject.h"
#import "NSAttributedString+DWBuilder.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdAmountModel ()

@property (readonly, strong, nonatomic) DWUpholdCardObject *card;
@property (null_resettable, nonatomic, strong) DWAmountDescriptionViewModel *availableDescriptionModel;
@property (null_resettable, nonatomic, strong) DWAmountDescriptionViewModel *insufficientFundsDescriptionModel;

@property (assign, nonatomic) DWUpholdRequestTransferModelState transferState;
@property (nullable, weak, nonatomic) DWUpholdCancellationToken createTransactionCancellationToken;
@property (nullable, strong, nonatomic) DWUpholdTransactionObject *transaction;

@end

NS_ASSUME_NONNULL_END

@implementation DWUpholdAmountModel

- (instancetype)initWithCard:(DWUpholdCardObject *)card {
    self = [super initWithContactItem:nil];
    if (self) {
        _card = card;

        self.descriptionModel = self.availableDescriptionModel;
    }
    return self;
}

- (void)dealloc {
    [self.createTransactionCancellationToken cancel];
}

- (BOOL)showsMaxButton {
    return YES;
}

- (BOOL)amountIsValidForProceeding {
    BOOL superResult = [super amountIsValidForProceeding];
    if (!superResult) {
        return NO;
    }

    return [self isSufficientDashForInput];
}

- (void)selectAllFundsWithPreparationBlock:(void (^)(void))preparationBlock {
    NSParameterAssert(self.card);
    if (self.card == nil) {
        return;
    }

    preparationBlock();

    NSDecimalNumber *duffs = (NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:DUFFS];
    uint64_t allAvailableFunds = [self.card.available decimalNumberByMultiplyingBy:duffs].longLongValue;

    if (allAvailableFunds > 0) {
        self.amountEnteredInDash = [[DWAmountObject alloc] initWithPlainAmount:allAvailableFunds];
        self.amountEnteredInLocalCurrency = nil;
        [self updateCurrentAmount];
    }
}

- (void)updateCurrentAmount {
    [super updateCurrentAmount];

    if (self.card == nil) {
        // initialization in progress
        return;
    }

    if ([self isSufficientDashForInput]) {
        self.descriptionModel = self.availableDescriptionModel;
    }
    else {
        self.descriptionModel = self.insufficientFundsDescriptionModel;
    }
}

- (void)resetAttributedValues {
    _availableDescriptionModel = nil;
    _insufficientFundsDescriptionModel = nil;
}

- (void)createTransactionWithOTPToken:(nullable NSString *)otpToken {
    NSParameterAssert(self.stateNotifier);

    NSDecimalNumber *amountNumber = [self decimalAmountNumber];
    NSString *amount = [amountNumber descriptionWithLocale:[NSLocale currentLocale]];

    [self createTransactionForAmount:amount
            feeWasDeductedFromAmount:NO
                            otpToken:otpToken];
}

- (void)resetCreateTransactionState {
    self.transaction = nil;
    self.transferState = DWUpholdRequestTransferModelState_None;
}

- (DWUpholdConfirmTransferModel *)transferModel {
    NSAssert(self.transferState == DWUpholdRequestTransferModelState_Success, @"Inconsistent state");
    if (!self.transaction) {
        return nil;
    }

    DWUpholdConfirmTransferModel *model = [[DWUpholdConfirmTransferModel alloc] initWithCard:self.card transaction:self.transaction];
    return model;
}

#pragma mark - Private

- (void)setTransferState:(DWUpholdRequestTransferModelState)transferState {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    if (_transferState == transferState) {
        return;
    }

    _transferState = transferState;

    [self.stateNotifier upholdAmountModel:self didUpdateState:transferState];
}

- (void)createTransactionForAmount:(NSString *)amount feeWasDeductedFromAmount:(BOOL)feeWasDeductedFromAmount otpToken:(nullable NSString *)otpToken {
    NSString *receiveAddress = [DWEnvironment sharedInstance].currentAccount.receiveAddress;
    NSParameterAssert(receiveAddress);
    if (!receiveAddress) {
        return;
    }

    self.transferState = DWUpholdRequestTransferModelState_Loading;

    [self.createTransactionCancellationToken cancel];
    DWUpholdClient *client = [DWUpholdClient sharedInstance];
    __weak typeof(self) weakSelf = self;
    self.createTransactionCancellationToken = [client
        createTransactionForDashCard:self.card
                              amount:amount
                             address:receiveAddress
                            otpToken:otpToken
                          completion:^(DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired) {
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              if (!strongSelf) {
                                  return;
                              }

                              strongSelf.createTransactionCancellationToken = nil;

                              strongSelf.transaction = transaction;

                              if (otpRequired) {
                                  strongSelf.transferState = DWUpholdRequestTransferModelState_OTP;
                              }
                              else {
                                  if (transaction) {
                                      DWUpholdCardObject *card = strongSelf.card;
                                      BOOL notSufficientFunds = ([transaction.total compare:card.available] == NSOrderedDescending);
                                      if (notSufficientFunds) {
                                          NSDecimalNumber *amountNumber = [NSDecimalNumber decimalNumberWithString:amount];
                                          NSDecimalNumber *correctedAmountNumber = [amountNumber decimalNumberBySubtracting:transaction.fee];
                                          NSString *correctedAmount = [correctedAmountNumber descriptionWithLocale:[NSLocale currentLocale]];

                                          if (correctedAmountNumber.doubleValue <= 0.0) {
                                              strongSelf.transferState = DWUpholdRequestTransferModelState_FailInsufficientFunds;
                                          }
                                          else {
                                              [strongSelf createTransactionForAmount:correctedAmount
                                                            feeWasDeductedFromAmount:YES
                                                                            otpToken:nil];
                                          }

                                          return;
                                      }

                                      transaction.feeWasDeductedFromAmount = feeWasDeductedFromAmount;

                                      strongSelf.transferState = DWUpholdRequestTransferModelState_Success;
                                  }
                                  else {
                                      strongSelf.transferState = DWUpholdRequestTransferModelState_Fail;
                                  }
                              }
                          }];
}

- (BOOL)isSufficientDashForInput {
    NSDecimalNumber *decimalDash = [self decimalAmountNumber];
    if ([decimalDash compare:self.card.available] == NSOrderedDescending) {
        return NO;
    }

    return YES;
}

- (NSDecimalNumber *)decimalAmountNumber {
    NSDecimalNumber *duffs = (NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:DUFFS];
    NSDecimalNumber *dash = (NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:self.amount.plainAmount];
    NSDecimalNumber *result = [dash decimalNumberByDividingBy:duffs];

    return result;
}

- (DWAmountDescriptionViewModel *)availableDescriptionModel {
    if (_availableDescriptionModel == nil) {
        NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

        NSDictionary *attributes = @{
            NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCallout],
            NSForegroundColorAttributeName : [UIColor dw_secondaryTextColor],
        };
        NSAttributedString *description =
            [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Enter the amount to transfer", nil)
                                            attributes:attributes];

        [result beginEditing];
        [result appendAttributedString:description];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [result appendAttributedString:[self availableAttributedString]];
        [result endEditing];

        DWAmountDescriptionViewModel *model = [[DWAmountDescriptionViewModel alloc] init];
        model.attributedText = result;

        _availableDescriptionModel = model;
    }

    return _availableDescriptionModel;
}

- (DWAmountDescriptionViewModel *)insufficientFundsDescriptionModel {
    if (_insufficientFundsDescriptionModel == nil) {
        NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

        NSDictionary *attributes = @{
            NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCallout],
            NSForegroundColorAttributeName : [UIColor dw_redColor],
        };
        NSAttributedString *description =
            [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Insufficient funds", nil)
                                            attributes:attributes];

        [result beginEditing];
        [result appendAttributedString:description];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [result appendAttributedString:[self availableAttributedString]];
        [result endEditing];

        DWAmountDescriptionViewModel *model = [[DWAmountDescriptionViewModel alloc] init];
        model.attributedText = result;

        _insufficientFundsDescriptionModel = model;
    }

    return _insufficientFundsDescriptionModel;
}

- (NSAttributedString *)availableAttributedString {
    NSParameterAssert(self.card);
    if (!self.card) {
        return [[NSAttributedString alloc] init];
    }

    UIColor *color = [UIColor dw_secondaryTextColor];
    UIFont *availableFont = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    NSString *availableRaw = [self.card.available descriptionWithLocale:[NSLocale currentLocale]];
    NSAttributedString *available =
        [NSAttributedString dw_dashAttributedStringForFormattedAmount:availableRaw
                                                            tintColor:color
                                                                 font:availableFont];

    NSDictionary *attributes = @{
        NSFontAttributeName : availableFont,
        NSForegroundColorAttributeName : color,
    };
    NSAttributedString *suffix =
        [[NSAttributedString alloc] initWithString:NSLocalizedString(@"available", @"lowercase, ex. 4 Dash available")
                                        attributes:attributes];

    [result beginEditing];
    [result appendAttributedString:available];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    [result appendAttributedString:suffix];
    [result endEditing];

    return [result copy];
}

@end
