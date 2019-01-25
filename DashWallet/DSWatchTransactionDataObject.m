//
//  DSWatchTransactionDataObject.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 30/10/2018.
//  Copyright © 2019 Dash Core. All rights reserved.
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
