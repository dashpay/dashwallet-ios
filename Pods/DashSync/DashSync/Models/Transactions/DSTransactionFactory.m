//
//  DSTransactionFactory.m
//  DashSync
//
//  Created by Sam Westrich on 7/12/18.
//

#import "DSTransactionFactory.h"
#import "DSCoinbaseTransaction.h"
#import "NSData+Dash.h"
#import "NSData+Bitcoin.h"

@implementation DSTransactionFactory

+(DSTransaction*)transactionWithMessage:(NSData*)message onChain:(DSChain*)chain {
    uint16_t type = [message UInt16AtOffset:2];
    switch (type) {
        case DSTransactionType_Classic:
            return [DSTransaction transactionWithMessage:message onChain:chain];
        case DSTransactionType_Coinbase:
            return [DSCoinbaseTransaction transactionWithMessage:message onChain:chain];
        default:
            return nil;
    }
}

@end
