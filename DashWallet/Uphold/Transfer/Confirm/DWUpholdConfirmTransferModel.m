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

#import "DWUpholdConfirmTransferModel.h"

#import "DWUpholdCardObject.h"
#import "DWUpholdClient.h"
#import "DWUpholdTransactionObject.h"
#import <DashSync/UIImage+DSUtils.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdConfirmTransferModel ()

@property (strong, nonatomic) DWUpholdCardObject *card;
@property (assign, nonatomic) DWUpholdConfirmTransferModelState state;
@property (nullable, strong, nonatomic) NSNumberFormatter *depositNumberFormatter;

@end

@implementation DWUpholdConfirmTransferModel

- (instancetype)initWithCard:(DWUpholdCardObject *)card transaction:(DWUpholdTransactionObject *)transaction {
    self = [super init];
    if (self) {
        _card = card;
        _transaction = transaction;
        if (transaction.type == DWUpholdTransactionObjectTypeDeposit) {
            NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
            numberFormatter.lenient = YES;
            numberFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
            numberFormatter.generatesDecimalNumbers = YES;
            numberFormatter.currencyCode = transaction.currency;
            _depositNumberFormatter = numberFormatter;
        }
    }
    return self;
}

- (NSAttributedString *)amountString {
    NSDecimalNumber *amount = self.transaction.amount;
    if (self.transaction.type == DWUpholdTransactionObjectTypeWithdrawal) {
        return [self attributedDashStringForDash:amount];
    }
    else {
        return [self attributedStringForLocalCurrency:amount];
    }
}

- (NSAttributedString *)feeString {
    NSDecimalNumber *fee = self.transaction.fee;
    if (self.transaction.type == DWUpholdTransactionObjectTypeWithdrawal) {
        return [self attributedDashStringForDash:fee];
    }
    else {
        return [self attributedStringForLocalCurrency:fee];
    }
}

- (NSAttributedString *)totalString {
    NSDecimalNumber *total = self.transaction.total;
    if (self.transaction.type == DWUpholdTransactionObjectTypeWithdrawal) {
        return [self attributedDashStringForDash:total];
    }
    else{
        return [self attributedStringForLocalCurrency:total];
    }
}

- (BOOL)feeWasDeductedFromAmount {
    return self.transaction.feeWasDeductedFromAmount;
}

- (void)confirmWithOTPToken:(nullable NSString *)otpToken {
    self.state = DWUpholdConfirmTransferModelStateLoading;

    DWUpholdClient *client = [DWUpholdClient sharedInstance];
    __weak typeof(self) weakSelf = self;
    [client commitTransaction:self.transaction card:self.card otpToken:otpToken completion:^(BOOL success, BOOL otpRequired) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (otpRequired) {
            strongSelf.state = DWUpholdConfirmTransferModelStateOTP;
        }
        else {
            strongSelf.state = success ? DWUpholdConfirmTransferModelStateSuccess : DWUpholdConfirmTransferModelStateFail;
        }
    }];
}

- (void)cancel {
    [[DWUpholdClient sharedInstance] cancelTransaction:self.transaction card:self.card];
}

- (void)resetState {
    self.state = DWUpholdConfirmTransferModelStateNone;
}

#pragma mark - Private

- (NSAttributedString *)attributedDashStringForDash:(NSDecimalNumber *)number {
    NSTextAttachment *dashAttachmentSymbol = [[NSTextAttachment alloc] init];
    dashAttachmentSymbol.bounds = CGRectMake(0.0, -2.0, 19.0, 15.0);
    dashAttachmentSymbol.image = [[UIImage imageNamed:@"Dash-Light"] ds_imageWithTintColor:[UIColor blackColor]];
    NSAttributedString *dashSymbol = [NSAttributedString attributedStringWithAttachment:dashAttachmentSymbol];
    NSString *numberString = [number descriptionWithLocale:[NSLocale currentLocale]];
    NSString *numberStringFormatted = [NSString stringWithFormat:@" %@", numberString];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];
    [result appendAttributedString:dashSymbol];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:numberStringFormatted]];
    [result endEditing];
    return [result copy];
}

- (NSAttributedString *)attributedStringForLocalCurrency:(NSDecimalNumber *)number {
    NSString *formattedString = [self.depositNumberFormatter stringFromNumber:number];
    return [[NSAttributedString alloc] initWithString:formattedString];
}

@end

NS_ASSUME_NONNULL_END
