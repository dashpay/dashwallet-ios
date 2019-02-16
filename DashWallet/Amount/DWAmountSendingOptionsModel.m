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

#import "DWAmountSendingOptionsModel.h"

#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

#define SEND_INSTANTLY_KEY @"SEND_INSTANTLY_KEY"

@interface DWAmountSendingOptionsModel ()

@property (strong, nonatomic) DSPaymentProtocolDetails *paymentDetails;
@property (assign, nonatomic) DWAmountSendOptionsModelState state;
@property (nullable, copy, nonatomic) NSString *instantSendFee;

@end

@implementation DWAmountSendingOptionsModel

- (instancetype)initWithSendingDestination:(NSString *)sendingDestination paymentDetails:(DSPaymentProtocolDetails *)paymentDetails {
    self = [super init];
    if (self) {
        _sendingDestination = [sendingDestination copy];
        _paymentDetails = paymentDetails;
        _useInstantSend = [[NSUserDefaults standardUserDefaults] boolForKey:SEND_INSTANTLY_KEY];
    }
    return self;
}

- (void)setUseInstantSend:(BOOL)useInstantSend {
    _useInstantSend = useInstantSend;

    [[NSUserDefaults standardUserDefaults] setBool:useInstantSend forKey:SEND_INSTANTLY_KEY];
}

- (void)updateWithAmount:(uint64_t)amount {
    self.instantSendFee = nil;

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    if (amount == 0 || amount > account.balance) {
        self.state = DWAmountSendOptionsModelStateNone;

        return;
    }

    uint64_t maxIXOutputAmount = [account maxOutputAmountWithConfirmationCount:IX_PREVIOUS_CONFIRMATIONS_NEEDED
                                                              usingInstantSend:YES];
    BOOL isInstantSendAvailable = maxIXOutputAmount >= amount;
    if (!isInstantSendAvailable) {
        self.state = DWAmountSendOptionsModelStateRegular;

        return;
    }

    BOOL canAutoLock = [account canUseAutoLocksForAmount:amount];
    if (!canAutoLock) {
        DSTransaction *tx = [account transactionForAmounts:@[ @(amount) ]
                                           toOutputScripts:@[ self.paymentDetails.outputScripts.firstObject ]
                                                   withFee:YES
                                                 isInstant:YES
                                       toShapeshiftAddress:nil];
        DSPriceManager *priceManager = [DSPriceManager sharedInstance];
        uint64_t instantSendFee = tx.standardInstantFee - tx.standardFee;
        NSAssert(instantSendFee > 0, @"Invalid instant send extra fee");
        if (instantSendFee <= 0) {
            self.state = DWAmountSendOptionsModelStateRegular;

            return;
        }

        self.instantSendFee = [priceManager localCurrencyStringForDashAmount:instantSendFee];
        self.state = DWAmountSendOptionsModelStateInstantSend;

        return;
    }

    self.state = DWAmountSendOptionsModelStateAutoLocks;
}

@end

NS_ASSUME_NONNULL_END
