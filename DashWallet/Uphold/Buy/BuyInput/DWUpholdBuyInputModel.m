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

#import "DWUpholdCardObject.h"
#import "DWUpholdClient.h"
#import "DWDecimalInputValidator.h"
#import "DWUpholdTransactionObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdBuyInputModel ()

@property (strong, nonatomic) id<DWInputValidator> inputValidator;
@property (strong, nonatomic) DWUpholdCardObject *dashCard;
@property (strong, nonatomic) DWUpholdCardObject *card;
@property (assign, nonatomic) DWUpholdBuyInputModelState state;
@property (nullable, weak, nonatomic) DWUpholdCancellationToken createTransactionCancellationToken;
@property (nullable, strong, nonatomic) DWUpholdTransactionObject *transaction;

@end

@implementation DWUpholdBuyInputModel

- (instancetype)initWithDashCard:(DWUpholdCardObject *)dashCard fromCard:(DWUpholdCardObject *)card {
    self = [super init];
    if (self) {
        _dashCard = dashCard;
        _card = card;
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
    // TODO: validate and input
}

- (void)createTransactionForAmount:(NSString *)amount cvc:(NSString *)cvc otpToken:(nullable NSString *)otpToken {
    // TODO: send API request
}

- (void)resetState {
    self.transaction = nil;
    self.state = DWUpholdBuyInputModelStateNone;
}

@end

NS_ASSUME_NONNULL_END
