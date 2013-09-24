//
//  ZNWallet+Transaction.m
//  ZincWallet
//
//  Created by Aaron Voisine on 9/23/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import "ZNWallet+Transaction.h"
#import "ZNTransaction.h"
#import "ZNKey.h"
#import "ZNUnspentOutputEntity.h"
#import "ZNAddressEntity.h"
#import "NSManagedObject+Utils.h"
#import "AFNetworking.h"

@implementation ZNWallet (Transaction)

#pragma mark - ZNTransaction helpers

// returns the estimated time in seconds until the transaction will be processed without a fee.
// this is based on the default satoshi client settings, but on the real network it's way off. in testing, a 0.01btc
// transaction with a 90 day time until free was confirmed in under an hour by Eligius pool.
- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction
{
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger currentHeight = self.lastBlockHeight;
    
    if (! currentHeight) return DBL_MAX;
    
    // get the heights (which block in the blockchain it's in) of all the transaction inputs
    [transaction.inputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        ZNUnspentOutputEntity *o = [ZNUnspentOutputEntity objectsMatching:@"txHash == %@ && n == %d",
                                    transaction.inputHashes[idx], [transaction.inputIndexes[idx] intValue]].lastObject;
        
        if (o) {
            [amounts addObject:@(o.value)];
            [heights addObject:@(currentHeight - o.confirmations)];
        }
        else *stop = YES;
    }];
    
    NSUInteger height = [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
    
    if (height == NSNotFound) return DBL_MAX;
    
    currentHeight = [self estimatedCurrentBlockHeight];
    
    return height > currentHeight + 1 ? (height - currentHeight)*600 : 0;
}

// retuns the total amount tendered in the trasaction (total unspent outputs consumed)
- (uint64_t)transactionAmount:(ZNTransaction *)transaction
{
    __block uint64_t amount = 0;
    
    [transaction.inputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        ZNUnspentOutputEntity *o = [ZNUnspentOutputEntity objectsMatching:@"txHash == %@ && n == %d",
                                    transaction.inputHashes[idx], [transaction.inputIndexes[idx] intValue]].lastObject;
        
        if (! o) {
            amount = 0;
            *stop = YES;
        }
        else amount += o.value;
    }];
    
    return amount;
}

// returns the transaction fee for the given transaction
- (uint64_t)transactionFee:(ZNTransaction *)transaction
{
    __block uint64_t amount = [self transactionAmount:transaction];
    
    if (amount == 0) return UINT64_MAX;
    
    [transaction.outputAmounts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        amount -= [obj unsignedLongLongValue];
    }];
    
    return amount;
}

// returns the amount that the given transaction returns to a change address
- (uint64_t)transactionChange:(ZNTransaction *)transaction
{
    __block uint64_t amount = 0;
    
    [transaction.outputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([self containsAddress:obj]) amount += [transaction.outputAmounts[idx] unsignedLongLongValue];
    }];
    
    return amount;
}

// returns the first trasnaction output address not contained in the wallet
- (NSString *)transactionTo:(ZNTransaction *)transaction
{
    __block NSString *address = nil;
    
    [transaction.outputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([self containsAddress:obj]) return;
        address = obj;
        *stop = YES;
    }];
    
    return address;
}

@end
