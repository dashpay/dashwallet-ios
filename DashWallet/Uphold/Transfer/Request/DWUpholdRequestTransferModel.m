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

#import "DWUpholdRequestTransferModel.h"

#import "DWUpholdCardObject.h"
#import "DWUpholdClient.h"
#import <DashSync/UIImage+DSUtils.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdRequestTransferModel ()

@property (strong, nonatomic) DWUpholdCardObject *card;
@property (assign, nonatomic) DWUpholdRequestTransferModelState state;
@property (nullable, weak, nonatomic) id<DWUpholdClientCancellationToken> createTransactionRequest;

@end

@implementation DWUpholdRequestTransferModel

- (instancetype)initWithCard:(DWUpholdCardObject *)card {
    self = [super init];
    if (self) {
        _card = card;
        _availableString = [card.available descriptionWithLocale:[NSLocale currentLocale]];
    }
    return self;
}

- (NSAttributedString *)availableDashString {
    NSTextAttachment *dashAttachmentSymbol = [[NSTextAttachment alloc] init];
    dashAttachmentSymbol.bounds = CGRectMake(0.0, -2.0, 19.0, 15.0);
    dashAttachmentSymbol.image = [[UIImage imageNamed:@"Dash-Light"] ds_imageWithTintColor:[UIColor darkGrayColor]];
    NSAttributedString *dashSymbol = [NSAttributedString attributedStringWithAttachment:dashAttachmentSymbol];
    NSString *available = self.availableString;
    NSString *availableFormatted = [NSString stringWithFormat:@" %@ %@", available, NSLocalizedString(@"available", nil)];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];
    [result appendAttributedString:dashSymbol];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:availableFormatted]];
    [result endEditing];
    return result;
}

- (DWUpholdTransferModelValidationResult)validateInput:(NSString *)input {
    if (input.length == 0) {
        return DWUpholdTransferModelValidationResultValid;
    }

    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:input];
    if ([number compare:NSDecimalNumber.zero] == NSOrderedSame) {
        return DWUpholdTransferModelValidationResultInvalid;
    }

    if ([number compare:self.card.available] == NSOrderedDescending) {
        return DWUpholdTransferModelValidationResultAvailableLimit;
    }

    return DWUpholdTransferModelValidationResultValid;
}

- (void)createTransactionForAmount:(NSString *)amount otpToken:(nullable NSString *)otpToken {
    if (amount.length == 0) {
        amount = self.availableString;
    }

    NSString *receiveAddress = [DWEnvironment sharedInstance].currentAccount.receiveAddress;
    NSParameterAssert(receiveAddress);
    if (!receiveAddress) {
        return;
    }

    self.state = DWUpholdRequestTransferModelStateLoading;

    DWUpholdClient *client = [DWUpholdClient sharedInstance];
    __weak typeof(self) weakSelf = self;
    self.createTransactionRequest = [client
        createTransactionForDashCard:self.card
                              amount:amount
                             address:receiveAddress
                            otpToken:otpToken
                          completion:^(DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired) {
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              if (!strongSelf) {
                                  return;
                              }

                              strongSelf.createTransactionRequest = nil;

                              if (otpRequired) {
                                  strongSelf.state = DWUpholdRequestTransferModelStateOTP;
                              }
                              else {
                                  strongSelf.state = transaction ? DWUpholdRequestTransferModelStateSuccess : DWUpholdRequestTransferModelStateFail;
                              }
                          }];
}

- (void)resetState {
    self.state = DWUpholdRequestTransferModelStateNone;
}

@end

NS_ASSUME_NONNULL_END
