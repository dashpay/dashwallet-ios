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

#define WALLET_BIP32 1
#define WALLET_BIP39 1

#define ADDRESSES_PER_QUERY 100 // maximum number of addresses to request in a single query

#define walletSyncStartedNotification  @"walletSyncStartedNotification"
#define walletSyncFinishedNotification @"walletSyncFinishedNotification"
#define walletSyncFailedNotification   @"walletSyncFailedNotification"
#define walletBalanceNotification      @"walletBalanceNotification"

@class ZNTransaction;

@interface ZNWallet : NSObject

@property (nonatomic, strong) NSString *seedPhrase;
@property (nonatomic, strong) NSData *seed;
@property (nonatomic, readonly, getter = mpk) NSData *masterPublicKey;
@property (nonatomic, readonly) uint64_t balance;
@property (nonatomic, readonly) NSString *receiveAddress;
@property (nonatomic, readonly) NSString *changeAddress;
@property (nonatomic, readonly) NSArray *recentTransactions; // ZNTransactionEntities sorted by date, most recent first
@property (nonatomic, readonly) NSUInteger estimatedCurrentBlockHeight;
@property (nonatomic, readonly) NSUInteger lastBlockHeight;
@property (nonatomic, readonly, getter = isSynchronizing) BOOL synchronizing;
@property (nonatomic, readonly) NSTimeInterval timeSinceLastSync;
@property (nonatomic, strong) NSNumberFormatter *format;

+ (instancetype)sharedInstance;

- (void)generateRandomSeed;
- (void)synchronize;

- (BOOL)containsAddress:(NSString *)address;
- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal;

- (int64_t)amountForString:(NSString *)string;
- (NSString *)stringForAmount:(int64_t)amount;
- (NSString *)localCurrencyStringForAmount:(int64_t)amount;

- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee;
- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction;
- (uint64_t)transactionFee:(ZNTransaction *)transaction;
- (BOOL)signTransaction:(ZNTransaction *)transaction;
- (void)publishTransaction:(ZNTransaction *)transaction completion:(void (^)(NSError *error))completion;

@end