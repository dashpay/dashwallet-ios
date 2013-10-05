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

#define ADDRESSES_PER_QUERY 100 // maximum number of addresses to request in a single query

#define walletSyncStartedNotification  @"walletSyncStartedNotification"
#define walletSyncFinishedNotification @"walletSyncFinishedNotification"
#define walletSyncFailedNotification   @"walletSyncFailedNotification"
#define walletBalanceNotification      @"walletBalanceNotification"

// blockchain checkpoints for SPV mode
//
//( 11111, uint256("0x0000000069e244f73d78e8fd29ba2fd2ed618bd6fa2ee92559f542fdb26e7c1d"))
//( 33333, uint256("0x000000002dd5588a74784eaa7ab0507a18ad16a236e7b1ce69f00d7ddfb5d0a6"))
//( 74000, uint256("0x0000000000573993a3c9e41ce34471c079dcf5f52a0e824a81e7f953b8661a20"))
//(105000, uint256("0x00000000000291ce28027faea320c8d2b054b2e0fe44a773f3eefb151d6bdc97"))
//(134444, uint256("0x00000000000005b12ffd4cd315cd34ffd4a594f430ac814c91184a0d42d2b0fe"))
//(168000, uint256("0x000000000000099e61ea72015e79632f216fe6cb33d7899acb35b75c8303b763"))
//(193000, uint256("0x000000000000059f452a5f7340de6682a977387c17010ff6e6c3bd83ca8b1317"))
//(210000, uint256("0x000000000000048b95347e83192f69cf0366076336c639f9b7228e9ba171342e"))
//(216116, uint256("0x00000000000001b4f4b433e81ee46494af945cf96014816a4e2370f11b23df4e"))
//(225430, uint256("0x00000000000001c108384350f74090433e7fcf79a606b8e797f065b130575932"))
//(250000, uint256("0x000000000000003887df1f29024b06fc2200b55f8af8f35453d7be294df2d214"))
//
//static const CCheckpointData data = {
//    &mapCheckpoints,
//    1375533383, // * UNIX timestamp of last checkpoint block
//    21491097,   // * total number of transactions between genesis and last checkpoint
//                //   (the tx=... number in the SetBestChain debug.log lines)
//    60000.0     // * estimated number of transactions per day after checkpoint
//};

@class ZNTransaction;

@interface ZNWallet : NSObject

@property (nonatomic, strong) NSString *seedPhrase;
@property (nonatomic, strong) NSData *seed;
@property (nonatomic, readonly) NSData *masterPublicKey;
@property (nonatomic, readonly) uint64_t balance;
@property (nonatomic, readonly) NSString *receiveAddress;
@property (nonatomic, readonly) NSString *changeAddress;
@property (nonatomic, readonly) NSArray *recentTransactions; // ZNTransactionEntities sorted by date, most recent first
@property (nonatomic, readonly) uint32_t estimatedCurrentBlockHeight;
@property (nonatomic, readonly) uint32_t lastBlockHeight;
@property (nonatomic, readonly, getter = isSynchronizing) BOOL synchronizing;
@property (nonatomic, readonly) NSTimeInterval timeSinceLastSync;
@property (nonatomic, strong) NSNumberFormatter *format;

+ (instancetype)sharedInstance;

- (void)generateRandomSeed;
- (void)synchronize:(BOOL)fullSync;

- (BOOL)containsAddress:(NSString *)address;

// returns array of gapLimit unused ZNAddressEntity objects following the last used address
- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal;

- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee;
- (BOOL)signTransaction:(ZNTransaction *)transaction;
- (void)sweepPrivateKey:(NSString *)privKey withFee:(BOOL)fee
completion:(void (^)(ZNTransaction *tx, NSError *error))completion;
- (void)publishTransaction:(ZNTransaction *)transaction completion:(void (^)(NSError *error))completion;
- (void)registerTransaction:(ZNTransaction *)transaction;

@end