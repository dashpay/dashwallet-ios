//
//  ZNWallet.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/12/13.
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

#define ZNWalletBalanceChangedNotification @"ZNWalletBalanceChangedNotification"

@class ZNTransaction;

@interface ZNWallet : NSObject

@property (nonatomic, strong) NSString *seedPhrase;
@property (nonatomic, strong) NSData *seed;
@property (nonatomic, readonly) NSData *masterPublicKey;
@property (nonatomic, readonly) NSTimeInterval seedCreationTime;
@property (nonatomic, readonly) uint64_t balance;
@property (nonatomic, readonly) NSString *receiveAddress;
@property (nonatomic, readonly) NSString *changeAddress;
@property (nonatomic, readonly) NSSet *addresses;
@property (nonatomic, readonly) NSArray *unspentOutputs;
@property (nonatomic, readonly) NSArray *recentTransactions; // ZNTransaction objects sorted by date, most recent first
@property (nonatomic, strong) NSNumberFormatter *format;

+ (instancetype)sharedInstance;

- (void)generateRandomSeed;

- (BOOL)containsAddress:(NSString *)address;

// returns array of gapLimit unused ZNAddressEntity objects following the last used address
- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal;

- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee;
- (BOOL)signTransaction:(ZNTransaction *)transaction;
- (void)sweepPrivateKey:(NSString *)privKey withFee:(BOOL)fee
completion:(void (^)(ZNTransaction *tx, NSError *error))completion;

// true if the given transaction is associated with the wallet, false otherwise
- (BOOL)containsTransaction:(ZNTransaction *)transaction;

// returns false if the transaction wasn't associated with the wallet
- (BOOL)registerTransaction:(ZNTransaction *)transaction;

- (void)setBlockHeight:(int32_t)height forTxHashes:(NSArray *)txHashes;

// returns the amount received to the wallet by the transaction (total outputs to change and/or recieve addresses)
- (uint64_t)amountReceivedFromTransaction:(ZNTransaction *)transaction;

// retuns the amount sent from the wallet by the trasaction (total wallet outputs consumed, change and fee included)
- (uint64_t)amountSentByTransaction:(ZNTransaction *)transaction;

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction:(ZNTransaction *)transaction;

// returns the first non-change transaction output address, or nil if there aren't any
- (NSString *)addressForTransaction:(ZNTransaction *)transaction;

// returns the block height after which the transaction is likely be processed without including a fee
- (uint32_t)blockHeightUntilFree:(ZNTransaction *)transaction;

- (int64_t)amountForString:(NSString *)string;
- (NSString *)stringForAmount:(int64_t)amount;
- (NSString *)localCurrencyStringForAmount:(int64_t)amount;

@end