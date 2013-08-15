//
//  ZNWallet.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/12/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

#define WALLET_BIP32 1
//XXXX switch mnemonic to bip39
//#define WALLET_BIP39 1

#define ADDRESSES_PER_QUERY 100 // maximum number of addresses to request in a single query

#define walletSyncStartedNotification  @"walletSyncStartedNotification"
#define walletSyncFinishedNotification @"walletSyncFinishedNotification"
#define walletSyncFailedNotification   @"walletSyncFailedNotification"
#define walletBalanceNotification      @"walletBalanceNotification"

@class ZNTransaction;

@interface ZNWallet : NSObject

@property (nonatomic, strong) NSString *seedPhrase;
@property (nonatomic, strong) NSData *seed;
@property (nonatomic, readonly) uint64_t balance;
@property (nonatomic, readonly) NSString *receiveAddress;
@property (nonatomic, readonly) NSString *changeAddress;
@property (nonatomic, readonly) NSArray *recentTransactions; // sorted by date, most recent first
@property (nonatomic, readonly) NSUInteger estimatedCurrentBlockHeight;
@property (nonatomic, readonly) NSUInteger lastBlockHeight;
@property (nonatomic, readonly, getter = isSynchronizing) BOOL synchronizing;
@property (nonatomic, readonly) NSTimeInterval timeSinceLastSync;
@property (nonatomic, strong) NSNumberFormatter *format;

+ (ZNWallet *)sharedInstance;

- (instancetype)initWithSeedPhrase:(NSString *)phrase;
- (instancetype)initWithSeed:(NSData *)seed;

- (void)generateRandomSeed;
- (void)synchronize;

- (BOOL)containsAddress:(NSString *)address;
- (int64_t)amountForString:(NSString *)string;
- (NSString *)stringForAmount:(int64_t)amount;
- (NSString *)localCurrencyStringForAmount:(int64_t)amount;

- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee;
- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction;
- (uint64_t)transactionFee:(ZNTransaction *)transaction;
- (BOOL)signTransaction:(ZNTransaction *)transaction;
- (void)publishTransaction:(ZNTransaction *)transaction completion:(void (^)(NSError *error))completion;

@end
