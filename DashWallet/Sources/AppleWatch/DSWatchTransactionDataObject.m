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

#import "DSWatchTransactionDataObject.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DSWatchTransactionDataObject

@synthesize amountText = _amountText;
@synthesize amountTextInLocalCurrency = _amountTextInLocalCurrency;
@synthesize dateText = _dateText;
@synthesize type = _type;

- (nullable instancetype)initWithTransaction:(DSTransaction *)transaction {
    if (!transaction) {
        return nil;
    }
    self = [super init];
    if (self) {
        DSAccount *currentAccount = [DWEnvironment sharedInstance].currentAccount;
        _amountText = [transaction amountTextReceivedInAccount:currentAccount];
        _amountTextInLocalCurrency = [transaction localCurrencyTextForAmountReceivedInAccount:currentAccount];
        _dateText = transaction.dateText;

        switch ([transaction transactionStatusInAccount:currentAccount]) {
            case DSTransactionStatus_Sent: {
                _type = BRAWTransactionTypeSent;
                break;
            }
            case DSTransactionStatus_Receive: {
                _type = BRAWTransactionTypeReceive;
                break;
            }
            case DSTransactionStatus_Move: {
                _type = BRAWTransactionTypeMove;
                break;
            }
            case DSTransactionStatus_Invalid: {
                _type = BRAWTransactionTypeInvalid;
                break;
            }
        }
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
