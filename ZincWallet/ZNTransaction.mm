//
//  ZNTransaction.mm
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNTransaction.h"

#include "bitcoinrpc.h"

@implementation ZNTransaction

- (id)initWithInputHashes:(NSArray *)inputHashes inputIndexes:(NSArray *)inputIndexes
outputAddresses:(NSArray *)outputAddresses andOutputAmounts:(NSArray *)outputAmounts
{
    if (! (self = [self init])) return nil;
    
    json_spirit::Array params;
    
    //createrawtransaction(params, 0);
    
    return self;
}

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys
{
    return NO;
}

@end
