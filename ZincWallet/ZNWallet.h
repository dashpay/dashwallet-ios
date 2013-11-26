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

#define balanceChangedNotification @"balanceChangedNotification"

@class ZNTransaction;

@interface ZNWallet : NSObject

@property (nonatomic, strong) NSString *seedPhrase;
@property (nonatomic, strong) NSData *seed;
@property (nonatomic, readonly) NSData *masterPublicKey;
@property (nonatomic, readonly) NSTimeInterval seedCreationTime;
@property (nonatomic, readonly) uint64_t balance;
@property (nonatomic, readonly) NSString *receiveAddress;
@property (nonatomic, readonly) NSString *changeAddress;
@property (nonatomic, readonly) NSArray *recentTransactions; // ZNTransaction objects sorted by date, most recent first
@property (nonatomic, readonly) uint32_t estimatedCurrentBlockHeight;
@property (nonatomic, readonly) uint32_t lastBlockHeight;
@property (nonatomic, readonly, getter = isSynchronizing) BOOL synchronizing;
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

// returns the estimated time in seconds until the transaction will be processed without a fee.
// this is based on the default satoshi client settings, but on the real network it's way off. in testing, a 0.01btc
// transaction with a 90 day time until free was confirmed in under an hour by Eligius pool.
- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction;

// retuns the total amount tendered in the trasaction (total unspent outputs consumed, change included)
- (uint64_t)transactionAmount:(ZNTransaction *)transaction;

// returns the transaction fee for the given transaction
- (uint64_t)transactionFee:(ZNTransaction *)transaction;

// returns the amount that the given transaction returns to a change address
- (uint64_t)transactionChange:(ZNTransaction *)transaction;

// returns the first transaction output address not contained in the wallet
- (NSString *)transactionTo:(ZNTransaction *)transaction;

- (int64_t)amountForString:(NSString *)string;
- (NSString *)stringForAmount:(int64_t)amount;
- (NSString *)localCurrencyStringForAmount:(int64_t)amount;

@end