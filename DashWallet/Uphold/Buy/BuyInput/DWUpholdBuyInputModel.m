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

#import "DWUpholdBuyInputModel.h"

#import "DWUpholdAccountObject.h"
#import "DWUpholdCardObject.h"
#import "DWUpholdClient.h"
#import "DWDecimalInputValidator.h"
#import "DWUpholdTransactionObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdBuyInputModel ()

@property (strong, nonatomic) id<DWInputValidator> inputValidator;
@property (strong, nonatomic) DWUpholdCardObject *card;
@property (strong, nonatomic) DWUpholdAccountObject *account;
@property (assign, nonatomic) DWUpholdBuyInputModelState state;
@property (nullable, weak, nonatomic) DWUpholdCancellationToken createTransactionCancellationToken;
@property (nullable, strong, nonatomic) DWUpholdTransactionObject *transaction;

@end

@implementation DWUpholdBuyInputModel

- (instancetype)initWithCard:(DWUpholdCardObject *)card
                     account:(DWUpholdAccountObject *)account {
    self = [super init];
    if (self) {
        _card = card;
//        _account = account;
        _inputValidator = [[DWDecimalInputValidator alloc] init];
    }
    return self;
}

- (void)dealloc {
    [self.createTransactionCancellationToken cancel];
}

- (BOOL)isAmountInputValid:(NSString *)input {
    if (input.length == 0) {
        return NO;
    }

    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:input locale:[NSLocale currentLocale]];
    if (!number || [number compare:NSDecimalNumber.zero] == NSOrderedSame) {
        return NO;
    }

    return YES;
}

- (void)updateAmountWithReplacementString:(NSString *)string range:(NSRange)range {
#warning todo here
}

- (void)createTransactionForAmount:(NSString *)amount cvc:(NSString *)cvc otpToken:(nullable NSString *)otpToken {
    self.state = DWUpholdBuyInputModelStateLoading;

    DWUpholdClient *client = [DWUpholdClient sharedInstance];
    __weak typeof(self) weakSelf = self;
    self.createTransactionCancellationToken =
        [client createBuyTransactionForDashCard:self.card
                                        account:self.account
                                         amount:amount
                                   securityCode:cvc
                                       otpToken:otpToken
                                     completion:^(DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired) {
                                         __strong typeof(weakSelf) strongSelf = weakSelf;
                                         if (!strongSelf) {
                                             return;
                                         }

                                         strongSelf.createTransactionCancellationToken = nil;

                                         strongSelf.transaction = transaction;

                                         if (otpRequired) {
                                             strongSelf.state = DWUpholdBuyInputModelStateOTP;
                                         }
                                         else {
                                             if (transaction) {
                                                 strongSelf.state = DWUpholdBuyInputModelStateSuccess;
                                             }
                                             else {
                                                 strongSelf.state = DWUpholdBuyInputModelStateFail;
                                             }
                                         }
                                     }];
}

- (void)resetState {
    self.transaction = nil;
    self.state = DWUpholdBuyInputModelStateNone;
}

@end

NS_ASSUME_NONNULL_END
