//
//  ZNWallet+Transaction.h
//  ZincWallet
//
//  Created by Aaron Voisine on 9/23/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import "ZNWallet.h"

@interface ZNWallet (Transaction)

- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction;
- (uint64_t)transactionAmount:(ZNTransaction *)transaction;
- (uint64_t)transactionFee:(ZNTransaction *)transaction;
- (uint64_t)transactionChange:(ZNTransaction *)transaction;
- (NSString *)transactionTo:(ZNTransaction *)transaction;

@end
