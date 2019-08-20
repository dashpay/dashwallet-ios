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

    DSSporkManager *sporkManager = [DWEnvironment sharedInstance].currentChainManager.sporkManager;
    if ([sporkManager llmqInstantSendEnabled]) {
        self.state = DWAmountSendOptionsModelState_AutoLocks;
        return;
    }

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    if (amount == 0) {
        self.state = DWAmountSendOptionsModelState_None;

        return;
    }

    uint32_t inputsWithInstantSend;
    uint32_t inputsWithoutInstantSend;

    uint64_t maxIXOutputAmountWithInstantSend =
        [account maxOutputAmountWithConfirmationCount:account.wallet.chain.ixPreviousConfirmationsNeeded
                                     usingInstantSend:YES
                                     returnInputCount:&inputsWithInstantSend];
    uint64_t maxIXOutputAmountWithoutInstantSend =
        [account maxOutputAmountWithConfirmationCount:0
                                     usingInstantSend:NO
                                     returnInputCount:&inputsWithoutInstantSend];

    uint64_t maxIXOutputAmount = MAX(maxIXOutputAmountWithInstantSend, maxIXOutputAmountWithoutInstantSend);
    BOOL isInstantSendAmountAvailable = maxIXOutputAmountWithInstantSend >= amount;
    BOOL isAmountAvailable = maxIXOutputAmountWithoutInstantSend >= amount;
    if (!isInstantSendAmountAvailable && isAmountAvailable && inputsWithoutInstantSend != inputsWithInstantSend) {
        _useInstantSend = NO;
        self.state = DWAmountSendOptionsModelState_Regular;

        return;
    }

    _useInstantSend = [[NSUserDefaults standardUserDefaults] boolForKey:SEND_INSTANTLY_KEY];

    BOOL canAutoLock = [account canUseAutoLocksForAmount:amount];
    if (!canAutoLock) {
        if (amount > maxIXOutputAmountWithInstantSend)
            amount = maxIXOutputAmountWithInstantSend;
        DSTransaction *tx = [account transactionForAmounts:@[ @(amount) ]
                                           toOutputScripts:@[ self.paymentDetails.outputScripts.firstObject ]
                                                   withFee:YES
                                                 isInstant:YES
                                       toShapeshiftAddress:nil];
        DSPriceManager *priceManager = [DSPriceManager sharedInstance];
        uint64_t instantSendExtraFee = MAX(0, tx.standardInstantFee - tx.standardFee);

        self.instantSendFee = [priceManager localCurrencyStringForDashAmount:instantSendExtraFee];
        self.state = DWAmountSendOptionsModelState_ProposeInstantSend;

        return;
    }

    self.state = DWAmountSendOptionsModelState_AutoLocks;
}

@end

NS_ASSUME_NONNULL_END
