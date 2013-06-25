//
//  ZNTransaction.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef TX_FEE_07_RULES
#define TX_FEE_PER_KB 10000llu // standard tx fee per kb of tx size, rounded up to the nearest kb
#else
#define TX_FEE_PER_KB 50000llu // standard tx fee per kb of tx size, rounded up to the nearest kb (0.7 rules)
#endif

#define TX_FREE_MIN_OUTPUT   1000000llu  // no tx output can be below this amount without a fee
#define TX_FREE_MAX_SIZE     10000llu    // tx must not be larger than this size without a fee
//#define TX_FREE_MIN_PRIORITY (SATOSHIS*144/250) // tx must not have a priority below this value without a fee
#define TX_FREE_MIN_PRIORITY 57600000llu // tx must not have a priority below this value without a fee

#define TX_MAX_SIZE          100000llu // no tx can be larger than this size
#define TX_MIN_OUTPUT_AMOUNT 5460llu   // no tx output can be below this amount (or it won't be relayed)

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

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/tx_size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages;

// returns the block height after which the transaction can be confirmed without a fee, given the amounts and block
// heights of the inputs. returns NSNotFound for never.
- (NSUInteger)heightUntilFreeForAmounts:(NSArray *)amounts atHeights:(NSArray *)heights;

- (uint64_t)standardFee;

@end
