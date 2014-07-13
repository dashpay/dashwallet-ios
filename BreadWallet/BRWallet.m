//
//  BRWallet.m
//  BreadWallet
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

#import "BRWallet.h"
#import "BRKey.h"
#import "BRAddressEntity.h"
#import "BRTransaction.h"
#import "BRTransactionEntity.h"
#import "BRKeySequence.h"
#import "BRBIP32Sequence.h"
#import "NSData+Hash.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "NSManagedObject+Sugar.h"

static NSData *txOutput(NSData *txHash, uint32_t n)
{
    NSMutableData *d = [NSMutableData dataWithCapacity:CC_SHA256_DIGEST_LENGTH + sizeof(uint32_t)];

    [d appendData:txHash];
    [d appendUInt32:n];
    return d;
}

@interface BRWallet ()

@property (nonatomic, strong) id<BRKeySequence> sequence;
@property (nonatomic, strong) NSData *masterPublicKey;
@property (nonatomic, strong) NSMutableArray *internalAddresses, *externalAddresses;
@property (nonatomic, strong) NSMutableSet *allAddresses, *usedAddresses, *spentOutputs, *invalidTx;
@property (nonatomic, strong) NSMutableOrderedSet *transactions, *utxos;
@property (nonatomic, strong) NSMutableDictionary *allTx;
@property (nonatomic, strong) NSData *(^seed)();
@property (nonatomic, strong) NSManagedObjectContext *moc;

@end

@implementation BRWallet

- (instancetype)initWithContext:(NSManagedObjectContext *)context andSeed:(NSData *(^)())seed
{
    if (! (self = [super init])) return nil;

    self.moc = context;
    self.seed = seed;
    self.sequence = [BRBIP32Sequence new];
    self.allTx = [NSMutableDictionary dictionary];
    self.transactions = [NSMutableOrderedSet orderedSet];
    self.internalAddresses = [NSMutableArray array];
    self.externalAddresses = [NSMutableArray array];
    self.allAddresses = [NSMutableSet set];
    self.usedAddresses = [NSMutableSet set];
    self.invalidTx = [NSMutableSet set];
    self.spentOutputs = [NSMutableSet set];
    self.utxos = [NSMutableOrderedSet orderedSet];

    //BUG: when switching networks or when installing a developement build overtop an appstore build,
    // the core data store can be inconsistent with the keychain, need to add a consistency check

    [self.moc performBlockAndWait:^{
        [BRAddressEntity setContext:self.moc];
        [BRTransactionEntity setContext:self.moc];

        for (BRAddressEntity *e in [BRAddressEntity allObjects]) {
            NSMutableArray *a = e.internal ? self.internalAddresses : self.externalAddresses;

            while (e.index >= a.count) [a addObject:[NSNull null]];
            [a replaceObjectAtIndex:e.index withObject:e.address];
            [self.allAddresses addObject:e.address];
        }

        for (BRTransactionEntity *e in [BRTransactionEntity allObjects]) {
            BRTransaction *tx = e.transaction;

            self.allTx[tx.txHash] = tx;
            [self.transactions addObject:tx];
            [self.usedAddresses addObjectsFromArray:tx.outputAddresses];
        }
    }];

    [self sortTransactions];
    [self updateBalance];

    return self;
}

- (NSData *)masterPublicKey
{
    if (! _masterPublicKey) {
        @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
            _masterPublicKey = [self.sequence masterPublicKeyFromSeed:self.seed()];
        }
    }
    return _masterPublicKey;
}

// Wallets are composed of chains of addresses. Each chain is traversed until a gap of a certain number of addresses is
// found that haven't been used in any transactions. This method returns an array of <gapLimit> unused addresses
// following the last used address in the chain. The internal chain is used for change addresses and the external chain
// for receive addresses.
- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    NSMutableArray *a = [NSMutableArray arrayWithArray:internal ? self.internalAddresses : self.externalAddresses];
    NSUInteger i = a.count;

    // keep only the trailing contiguous block of addresses with no transactions
    while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
        i--;
    }

    if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
    if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];

    // get a single address first to avoid blocking receiveAddress and changeAddress
    if (a.count == 0 && gapLimit > 1) [self addressesWithGapLimit:1 internal:internal];

    @synchronized(self) {
        [a setArray:internal ? self.internalAddresses : self.externalAddresses];
        i = a.count;

        unsigned n = (unsigned)i;

        // keep only the trailing contiguous block of addresses with no transactions
        while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
            i--;
        }

        if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
        if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];

        while (a.count < gapLimit) { // generate new addresses up to gapLimit
            NSData *pubKey = [self.sequence publicKey:n internal:internal masterPublicKey:self.masterPublicKey];
            NSString *addr = [[BRKey keyWithPublicKey:pubKey] address];
        
            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }

            [self.moc performBlock:^{ // store new address in core data
                BRAddressEntity *e = [BRAddressEntity managedObject];

                e.address = addr;
                e.index = n;
                e.internal = internal;
            }];

            [self.allAddresses addObject:addr];
            [internal ? self.internalAddresses : self.externalAddresses addObject:addr];
            [a addObject:addr];
            n++;
        }
    
        return a;
    }
}

// this sorts transactions by block height in descending order, and makes a best attempt at ordering transactions within
// each block, however correct transaction ordering cannot be relied upon for determining wallet balance or UTXO set
- (void)sortTransactions
{
    [self.transactions sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        if ([obj1 blockHeight] > [obj2 blockHeight]) return NSOrderedAscending;
        if ([obj1 blockHeight] < [obj2 blockHeight]) return NSOrderedDescending;
        if ([[obj1 inputHashes] containsObject:[obj2 txHash]]) return NSOrderedAscending;
        if ([[obj2 inputHashes] containsObject:[obj1 txHash]]) return NSOrderedDescending;
        // TODO: recursively compare transactions for input hashes that are in the wallet
        return NSOrderedSame;
    }];
}

- (void)updateBalance
{
    uint64_t balance = 0;
    NSMutableOrderedSet *utxos = [NSMutableOrderedSet orderedSet];
    NSMutableSet *spentOutputs = [NSMutableSet set], *invalidTx = [NSMutableSet set];

    for (BRTransaction *tx in [self.transactions reverseObjectEnumerator]) {
        NSMutableSet *spent = [NSMutableSet set];
        uint32_t i = 0, n = 0;

        for (NSData *hash in tx.inputHashes) {
            n = [tx.inputIndexes[i++] unsignedIntValue];
            [spent addObject:txOutput(hash, n)];
        }

        // check if any inputs are invalid or already spent
        if (tx.blockHeight == TX_UNCONFIRMED &&
            ([spent intersectsSet:spentOutputs] || [[NSSet setWithArray:tx.inputHashes] intersectsSet:invalidTx])) {
            [invalidTx addObject:tx.txHash];
            continue;
        }

        [spentOutputs unionSet:spent]; // add inputs to spent output set
        n = 0;

        //TODO: don't add outputs below TX_MIN_OUTPUT_AMOUNT
        //TODO: don't add coin generation outputs < 100 blocks deep, or non-final lockTime > 1 block/10min in future
        //NOTE: balance/UTXOs will then need to be recalculated when last block changes
        for (NSString *address in tx.outputAddresses) { // add outputs to UTXO set
            if ([self containsAddress:address]) {
                [utxos addObject:txOutput(tx.txHash, n)];
                balance += [tx.outputAmounts[n] unsignedLongLongValue];
            }
            n++;
        }

        // transaction ordering is not guaranteed, so check the entire UTXO set against the entire spent output set
        [spent setSet:[utxos set]];
        [spent intersectSet:spentOutputs];
        
        for (NSData *o in spent) { // remove any spent outputs from UTXO set
            BRTransaction *transaction = self.allTx[[o hashAtOffset:0]];
            uint32_t n = [o UInt32AtOffset:CC_SHA256_DIGEST_LENGTH];
            
            [utxos removeObject:o];
            balance -= [transaction.outputAmounts[n] unsignedLongLongValue];
        }
    }

    self.invalidTx = invalidTx;
    self.spentOutputs = spentOutputs;
    self.utxos = utxos;

    if (balance != _balance) {
        _balance = balance;

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletBalanceChangedNotification object:nil];
        });
    }
}

#pragma mark - wallet info

- (NSString *)receiveAddress
{
    return [self addressesWithGapLimit:1 internal:NO].lastObject;
}

- (NSString *)changeAddress
{
    return [self addressesWithGapLimit:1 internal:YES].lastObject;
}

- (NSSet *)addresses
{
    return self.allAddresses;
}

- (NSArray *)unspentOutputs
{
    return [self.utxos array];
}

- (NSArray *)recentTransactions
{
    //TODO: don't include receive transactions that don't have at least one wallet output >= TX_MIN_OUTPUT_AMOUNT
    return [self.transactions array];
}

// true if the address is known to belong to the wallet
- (BOOL)containsAddress:(NSString *)address
{
    return (address && [self.allAddresses containsObject:address]) ? YES : NO;
}

#pragma mark - transactions

// returns an unsigned transaction that sends the specified amount from the wallet to the given address
- (BRTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    NSMutableData *script = [NSMutableData data];

    [script appendScriptPubKeyForAddress:address];

    return [self transactionForAmounts:@[@(amount)] toOutputScripts:@[script] withFee:fee];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee;
{
    uint64_t amount = 0, balance = 0, standardFee = 0;
    BRTransaction *transaction = [BRTransaction new];
    NSUInteger i = 0;

    for (NSData *script in scripts) {
        if (! script.length) return nil;
        [transaction addOutputScript:script amount:[amounts[i] unsignedLongLongValue]];
        amount += [amounts[i++] unsignedLongLongValue];
    }

    //TODO: make sure transaction is less than TX_MAX_SIZE
    //TODO: use up all inputs for all used addresses to avoid leaving funds in addresses whose public key is revealed
    //TODO: avoid combining addresses in a single transaction when possible to reduce information leakage
    for (NSData *o in self.utxos) {
        BRTransaction *tx = self.allTx[[o hashAtOffset:0]];
        uint32_t n = [o UInt32AtOffset:CC_SHA256_DIGEST_LENGTH];

        if (! tx) continue;

        [transaction addInputHash:tx.txHash index:n script:tx.outputScripts[n]];
        balance += [tx.outputAmounts[n] unsignedLongLongValue];
            
        // assume we will be adding a change output (additional 34 bytes)
        //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
        //NOTE: consider feedback effects if everyone uses the same algorithm to calculate fees, maybe add noise
        if (fee) standardFee = ((transaction.size + 34 + 999)/1000)*TX_FEE_PER_KB;
            
        if (balance == amount + standardFee || balance >= amount + standardFee + TX_MIN_OUTPUT_AMOUNT) break;
    }
    
    if (balance < amount + standardFee) { // insufficent funds
        NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + standardFee);
        return nil;
    }
    
    //TODO: randomly swap order of outputs so the change address isn't publicy known
    if (balance - (amount + standardFee) >= TX_MIN_OUTPUT_AMOUNT) {
        [transaction addOutputAddress:self.changeAddress amount:balance - (amount + standardFee)];
    }
    
    return transaction;
}

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (BOOL)signTransaction:(BRTransaction *)transaction
{
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        NSData *seed = self.seed();
        NSMutableArray *pkeys = [NSMutableArray array];
        NSMutableOrderedSet *externalIndexes = [NSMutableOrderedSet orderedSet],
                            *internalIndexes = [NSMutableOrderedSet orderedSet];

        for (NSString *addr in transaction.inputAddresses) {
            [internalIndexes addObject:@([self.internalAddresses indexOfObject:addr])];
            [externalIndexes addObject:@([self.externalAddresses indexOfObject:addr])];
        }
        
        [internalIndexes removeObject:@(NSNotFound)];
        [externalIndexes removeObject:@(NSNotFound)];
        [pkeys addObjectsFromArray:[self.sequence privateKeys:[externalIndexes array] internal:NO fromSeed:seed]];
        [pkeys addObjectsFromArray:[self.sequence privateKeys:[internalIndexes array] internal:YES fromSeed:seed]];
        
        [transaction signWithPrivateKeys:pkeys];
        
        return [transaction isSigned];
    }
}

// true if the given transaction is associated with the wallet (even if it hasn't been registered), false otherwise
- (BOOL)containsTransaction:(BRTransaction *)transaction
{
    if ([[NSSet setWithArray:transaction.outputAddresses] intersectsSet:self.allAddresses]) return YES;
    
    NSInteger i = 0;
    
    for (NSData *txHash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[txHash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];

        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) return YES;
    }
        
    return NO;
}

// records the transaction in the wallet, or returns false if it isn't associated with the wallet
- (BOOL)registerTransaction:(BRTransaction *)transaction
{
    if (transaction.txHash == nil) return NO;
    if (self.allTx[transaction.txHash] != nil) return YES;
    if (! [self containsTransaction:transaction]) return NO;

    [self.usedAddresses addObjectsFromArray:transaction.outputAddresses];
    self.allTx[transaction.txHash] = transaction;
    [self.transactions insertObject:transaction atIndex:0];
    [self updateBalance];

    // when a wallet address is used in a transaction, generate a new address to replace it
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO];
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];

    [self.moc performBlock:^{ // add the transaction to core data
        if ([BRTransactionEntity countObjectsMatching:@"txHash == %@", transaction.txHash] == 0) {
            [[BRTransactionEntity managedObject] setAttributesFromTx:transaction];
        }
    }];

    return YES;
}

// removes a transaction from the wallet along with any transactions that depend on its outputs
- (void)removeTransaction:(NSData *)txHash
{
    BRTransaction *transaction = self.allTx[txHash];
    NSMutableSet *hashes = [NSMutableSet set];

    for (BRTransaction *tx in self.transactions) { // remove dependent transactions
        if (tx.blockHeight < transaction.blockHeight) break;
        if (! [txHash isEqual:tx.txHash] && [tx.inputHashes containsObject:txHash]) [hashes addObject:tx.txHash];
    }

    for (NSData *hash in hashes) {
        [self removeTransaction:hash];
    }

    [self.allTx removeObjectForKey:txHash];
    if (transaction) [self.transactions removeObject:transaction];
    [self updateBalance];

    [self.moc performBlock:^{ // remove transaction from core data
        [BRTransactionEntity deleteObjects:[BRTransactionEntity objectsMatching:@"txHash == %@", txHash]];
    }];
}

// true if the given transaction has been added to the wallet
- (BOOL)transactionIsRegistered:(NSData *)txHash
{
    return (self.allTx[txHash] != nil) ? YES : NO;
}

// true if no previous wallet transactions spend any of the given transaction's inputs, and no input tx is invalid
- (BOOL)transactionIsValid:(BRTransaction *)transaction
{
    if (transaction.blockHeight != TX_UNCONFIRMED) return YES;
    if (self.allTx[transaction.txHash] != nil) return [self.invalidTx containsObject:transaction.txHash] ? NO : YES;

    uint32_t i = 0;

    for (NSData *hash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];

        if ((tx && ! [self transactionIsValid:tx]) || [self.spentOutputs containsObject:txOutput(hash, n)]) return NO;
    }

    return YES;
}

// returns true if transaction won't be valid by blockHeight + 1 or within the next 10 minutes
- (BOOL)transactionIsPending:(BRTransaction *)transaction atBlockHeight:(uint32_t)blockHeight
{
    if (transaction.blockHeight <= blockHeight + 1) return NO; // confirmed transactions are not pending

    for (NSData *txHash in transaction.inputHashes) { // check if any inputs are known to be pending
        if ([self transactionIsPending:self.allTx[txHash] atBlockHeight:blockHeight]) return YES;
    }

    if (transaction.lockTime <= blockHeight + 1) return NO;

    if (transaction.lockTime >= TX_MAX_LOCK_HEIGHT &&
        transaction.lockTime < [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970 + 10*60) return NO;

    for (NSNumber *sequence in transaction.inputSequences) { // lockTime is ignored if all sequence numbers are final
        if (sequence.unsignedIntValue < UINT32_MAX) return YES;
    }

    return NO;
}

- (void)setBlockHeight:(int32_t)height forTxHashes:(NSArray *)txHashes
{
    BOOL set = NO;

    for (NSData *hash in txHashes) {
        BRTransaction *tx = self.allTx[hash];

        if (! tx || tx.blockHeight == height) continue;
        tx.blockHeight = height;
        set = YES;
    }

    if (set) {
        [self sortTransactions];
        [self updateBalance];

        [self.moc performBlock:^{
            for (BRTransactionEntity *e in [BRTransactionEntity objectsMatching:@"txHash in %@", txHashes]) {
                e.blockHeight = height;
            }
        }];
    }
}

// returns the amount received to the wallet by the transaction (total outputs to change and/or recieve addresses)
- (uint64_t)amountReceivedFromTransaction:(BRTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger n = 0;

    //TODO: don't include outputs below TX_MIN_OUTPUT_AMOUNT
    for (NSString *address in transaction.outputAddresses) {
        if ([self containsAddress:address]) amount += [transaction.outputAmounts[n] unsignedLongLongValue];
        n++;
    }

    return amount;
}

// retuns the amount sent from the wallet by the trasaction (total wallet outputs consumed, change and fee included)
- (uint64_t)amountSentByTransaction:(BRTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;

    for (NSData *hash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] intValue];

        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) {
            amount += [tx.outputAmounts[n] unsignedLongLongValue];
        }
    }

    return amount;
}

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction:(BRTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;

    for (NSData *hash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] intValue];

        if (n >= tx.outputAmounts.count) return UINT64_MAX;
        amount += [tx.outputAmounts[n] unsignedLongLongValue];
    }

    for (NSNumber *amt in transaction.outputAmounts) {
        amount -= amt.unsignedLongLongValue;
    }
    
    return amount;
}

// returns the first non-change output address for sends, first input address for receives, or nil if unkown
- (NSString *)addressForTransaction:(BRTransaction *)transaction
{
    uint64_t sent = [self amountSentByTransaction:transaction];
    NSArray *addrs = (sent > 0) ? transaction.outputAddresses : transaction.inputAddresses;

    for (NSString *address in addrs) {
        if (address != (id)[NSNull null] && ! [self containsAddress:address]) return address;
    }

    return nil;
}

// Returns the block height after which the transaction is likely to be processed without including a fee. This is based
// on the default satoshi client settings, but on the real network it's way off. In testing, a 0.01btc transaction that
// was expected to take an additional 90 days worth of blocks to confirm was confirmed in under an hour by Eligius pool.
- (uint32_t)blockHeightUntilFree:(BRTransaction *)transaction
{
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger i = 0;

    for (NSData *hash in transaction.inputHashes) { // get the amounts and block heights of all the transaction inputs
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];

        if (n >= tx.outputAmounts.count) break;
        [amounts addObject:tx.outputAmounts[n]];
        [heights addObject:@(tx.blockHeight)];
    };

    return [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
}

@end
