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
#define TX_FREE_MAX_SIZE     10000llu    // tx must not be larger than this size in bytes without a fee
#define TX_FREE_MIN_PRIORITY 57600000llu // tx must not have a priority below this value without a fee

#define TX_MAX_SIZE          100000llu // no tx can be larger than this size in bytes
#define TX_MIN_OUTPUT_AMOUNT 5460llu   // no tx output can be below this amount (or it won't be relayed)

@interface ZNTransaction : NSObject

@property (nonatomic, readonly) NSArray *inputAddresses;
@property (nonatomic, readonly) NSArray *inputHashes;
@property (nonatomic, readonly) NSArray *inputIndexes;
@property (nonatomic, readonly) NSArray *inputScripts;
@property (nonatomic, readonly) NSArray *outputAddresses;
@property (nonatomic, readonly) NSArray *outputAmounts;

@property (nonatomic, readonly) size_t size;
@property (nonatomic, readonly) uint64_t standardFee;
@property (nonatomic, readonly) BOOL isSigned;
@property (nonatomic, readonly, getter = toData) NSData *data;
@property (nonatomic, readonly, getter = toHex) NSString *hex;

// hashes are expected to already be little endian
- (instancetype)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts
outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts;

- (void)addInputHash:(NSData *)hash index:(NSUInteger)index script:(NSData *)script;

- (void)addOutputAddress:(NSString *)address amount:(uint64_t)amount;

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys;

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/tx_size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages;

// the block height after which the transaction can be confirmed without a fee, or NSNotFound for never
- (NSUInteger)blockHeightUntilFreeForAmounts:(NSArray *)amounts withBlockHeights:(NSArray *)heights;

@end
