//
//  ZNWallet.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/12/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

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
@property (nonatomic, strong) NSNumberFormatter *format;
@property (readonly, getter = isSynchronizing) BOOL synchronizing;

+ (ZNWallet *)sharedInstance;

- (instancetype)initWithSeedPhrase:(NSString *)phrase;
- (instancetype)initWithSeed:(NSData *)seed;

- (void)generateRandomSeed;
- (void)synchronize;

- (BOOL)containsAddress:(NSString *)address;
- (NSString *)stringForAmount:(uint64_t)amount;
- (uint64_t)amountForString:(NSString *)string;

- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee;
- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction;
- (uint64_t)transactionFee:(ZNTransaction *)transaction;
- (BOOL)signTransaction:(ZNTransaction *)transaction;

@end
