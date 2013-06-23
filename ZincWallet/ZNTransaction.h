//
//  ZNTransaction.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

#define TX_MAX_SIZE          100000 // no tx can be larger than this size
#define TX_MIN_OUTPUT_AMOUNT 5430 // no tx output can be below this amount (or the tx won't be relayed)

#ifndef TX_FEE_07_RULES
#define TX_FEE_PER_KB        10000 // standard tx fee per kb of tx size, rounded up to the nearest kb
#else
#define TX_FEE_PER_KB        50000 // standard tx fee per kb of tx size, rounded up to the nearest kb (0.7 rules)
#endif

#define TX_FREE_MIN_OUTPUT   1000000 // no tx output can be below this amount without a fee
#define TX_FREE_MAX_SIZE     10000 // tx must not be larger than this size without a fee
#define TX_FREE_MIN_PRIORITY 57600000.0 // tx must not have a priority below this value without a fee

@interface ZNTransaction : NSObject

@property (nonatomic, readonly) size_t size;

// inputHashes are expected to already be little endian
- (id)initWithInputHashes:(NSArray *)inputHashes inputIndexes:(NSArray *)inputIndexes
inputScripts:(NSArray *)inputScripts outputAddresses:(NSArray *)outputAddresses
andOutputAmounts:(NSArray *)outputAmounts;

- (BOOL)isSigned;

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys;

- (NSData *)toData;

- (NSString *)toHex;

// priority = sum(input_value_in_satoshis*input_age_in_blocks)/tx_size_in_bytes
- (uint64_t)priorityFor:(NSArray *)amounts ages:(NSArray *)ages;

@end
