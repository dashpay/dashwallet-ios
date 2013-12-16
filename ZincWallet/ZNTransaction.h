//
//  ZNTransaction.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import <Foundation/Foundation.h>

#if TX_FEE_07_RULES
#define TX_FEE_PER_KB        50000llu    // standard tx fee per kb of tx size, rounded up to the nearest kb (0.7 rules)
#else
#define TX_FEE_PER_KB        10000llu    // standard tx fee per kb of tx size, rounded up to the nearest kb
#endif

#define TX_FREE_MAX_SIZE     1000llu     // tx must not be larger than this size in bytes without a fee
#define TX_FREE_MIN_PRIORITY 57600000llu // tx must not have a priority below this value without a fee
#define TX_MAX_SIZE          100000llu   // no tx can be larger than this size in bytes
#define TX_MIN_OUTPUT_AMOUNT 5460llu     // no tx output can be below this amount (or it won't be relayed)
#define TX_UNCONFIRMED       INT32_MAX   // block height indicating transaction is unconfirmed

@interface ZNTransaction : NSObject

@property (nonatomic, readonly) NSArray *inputAddresses;
@property (nonatomic, readonly) NSArray *inputHashes;
@property (nonatomic, readonly) NSArray *inputIndexes;
@property (nonatomic, readonly) NSArray *inputScripts;
@property (nonatomic, readonly) NSArray *inputSignatures;
@property (nonatomic, readonly) NSArray *inputSequences;
@property (nonatomic, readonly) NSArray *outputAmounts;
@property (nonatomic, readonly) NSArray *outputAddresses;
@property (nonatomic, readonly) NSArray *outputScripts;

@property (nonatomic, assign) uint32_t version;
@property (nonatomic, strong) NSData *txHash; // hash of the signed transaction, little endian
@property (nonatomic, assign) uint32_t lockTime;
@property (nonatomic, assign) uint32_t blockHeight;
@property (nonatomic, readonly) size_t size;
@property (nonatomic, readonly) uint64_t standardFee;
@property (nonatomic, readonly) BOOL isSigned; // checks if all signatures exist, but does not verify them
@property (nonatomic, readonly, getter = toData) NSData *data;
@property (nonatomic, readonly, getter = toHex) NSString *hex;

// hashes are expected to already be little endian
- (instancetype)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts
outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts;

- (instancetype)initWithData:(NSData *)data;

- (void)addInputHash:(NSData *)hash index:(NSUInteger)index script:(NSData *)script;
- (void)addInputHash:(NSData *)hash index:(NSUInteger)index script:(NSData *)script signature:(NSData *)signature
sequence:(uint32_t)sequence;

- (void)addOutputAddress:(NSString *)address amount:(uint64_t)amount;
- (void)addOutputScript:(NSData *)script amount:(uint64_t)amount;

- (void)setInputAddress:(NSString *)address atIndex:(NSUInteger)index;

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys;

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/tx_size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages;

// the block height after which the transaction can be confirmed without a fee, or TX_UNCONFIRMED for never
- (NSUInteger)blockHeightUntilFreeForAmounts:(NSArray *)amounts withBlockHeights:(NSArray *)heights;

@end
