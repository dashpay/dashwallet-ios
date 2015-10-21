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
#import "BRTxInputEntity.h"
#import "BRTxOutputEntity.h"
#import "BRKeySequence.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "NSManagedObject+Sugar.h"

// chain position of first tx output address that appears in chain
static NSUInteger txAddressIndex(BRTransaction *tx, NSArray *chain) {
    for (NSString *addr in tx.outputAddresses) {
        NSUInteger i = [chain indexOfObject:addr];
        
        if (i != NSNotFound) return i;
    }
    
    return NSNotFound;
}

@interface BRWallet ()

@property (nonatomic, strong) id<BRKeySequence> sequence;
@property (nonatomic, strong) NSData *masterPublicKey;
@property (nonatomic, strong) NSMutableArray *internalAddresses, *externalAddresses;
@property (nonatomic, strong) NSMutableSet *allAddresses, *usedAddresses, *allTxHashes;
@property (nonatomic, strong) NSSet *spentOutputs, *invalidTx;
@property (nonatomic, strong) NSMutableOrderedSet *transactions;
@property (nonatomic, strong) NSOrderedSet *utxos;
@property (nonatomic, strong) NSMutableDictionary *allTx;
@property (nonatomic, strong) NSArray *balanceHistory;
@property (nonatomic, strong) NSData *(^seed)(NSString *authprompt, uint64_t amount);
@property (nonatomic, strong) NSManagedObjectContext *moc;

@end

@implementation BRWallet

- (instancetype)initWithContext:(NSManagedObjectContext *)context sequence:(id<BRKeySequence>)sequence
masterPublicKey:(NSData *)masterPublicKey seed:(NSData *(^)(NSString *authprompt, uint64_t amount))seed
{
    if (! (self = [super init])) return nil;

    self.moc = context;
    self.sequence = sequence;
    self.masterPublicKey = masterPublicKey;
    self.seed = seed;
    self.allTx = [NSMutableDictionary dictionary];
    self.transactions = [NSMutableOrderedSet orderedSet];
    self.allTxHashes = [NSMutableSet set];
    self.internalAddresses = [NSMutableArray array];
    self.externalAddresses = [NSMutableArray array];
    self.allAddresses = [NSMutableSet set];
    self.usedAddresses = [NSMutableSet set];

    [self.moc performBlockAndWait:^{
        [BRAddressEntity setContext:self.moc];
        [BRTransactionEntity setContext:self.moc];

        for (BRAddressEntity *e in [BRAddressEntity allObjects]) {
            NSMutableArray *a = (e.internal) ? self.internalAddresses : self.externalAddresses;

            while (e.index >= a.count) [a addObject:[NSNull null]];
            a[e.index] = e.address;
            [self.allAddresses addObject:e.address];
        }

        // pre-fetch transaction inputs and outputs
        [BRTxInputEntity allObjects];
        [BRTxOutputEntity allObjects];
        
        for (BRTransactionEntity *e in [BRTransactionEntity allObjects]) {
            BRTransaction *tx = e.transaction;
            NSValue *hash = (tx) ? uint256_obj(tx.txHash) : nil;

            if (! tx) continue;
            self.allTx[hash] = tx;
            [self.allTxHashes addObject:hash];
            [self.transactions addObject:tx];
            [self.usedAddresses addObjectsFromArray:tx.inputAddresses];
            [self.usedAddresses addObjectsFromArray:tx.outputAddresses];
        }
    }];

    [self sortTransactions];
    _balance = UINT64_MAX; // trigger balance changed notification even if balance is zero
    [self updateBalance];

    return self;
}

- (NSData *)masterPublicKey
{
    if (! _masterPublicKey) {
        @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
            _masterPublicKey = [self.sequence masterPublicKeyFromSeed:self.seed(nil, 0)];
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
    NSMutableArray *a = [NSMutableArray arrayWithArray:(internal) ? self.internalAddresses : self.externalAddresses];
    NSUInteger i = a.count;

    // keep only the trailing contiguous block of addresses with no transactions
    while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
        i--;
    }

    if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
    if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];

    if (gapLimit > 1) { // get receiveAddress and changeAddress first to avoid blocking
        [self receiveAddress];
        [self changeAddress];
    }

    @synchronized(self) {
        [a setArray:(internal) ? self.internalAddresses : self.externalAddresses];
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
            NSString *addr = [BRKey keyWithPublicKey:pubKey].address;
        
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
            [(internal) ? self.internalAddresses : self.externalAddresses addObject:addr];
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
    BOOL (^isAscending)(id, id);
    __block __weak BOOL (^_isAscending)(id, id) = isAscending = ^BOOL(BRTransaction *tx1, BRTransaction *tx2) {
        if (! tx1 || ! tx2) return NO;
        if (tx1.blockHeight > tx2.blockHeight) return YES;
        if (tx1.blockHeight < tx2.blockHeight) return NO;
        if ([tx1.inputHashes containsObject:uint256_obj(tx2.txHash)]) return YES;
        if ([tx2.inputHashes containsObject:uint256_obj(tx1.txHash)]) return NO;
        
        for (NSValue *hash in tx1.inputHashes) {
            if (_isAscending(self.allTx[hash], tx2)) return YES;
        }
                
        return NO;
    };

    [self.transactions sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id tx1, id tx2) {
        if (isAscending(tx1, tx2)) return NSOrderedAscending;
        if (isAscending(tx2, tx1)) return NSOrderedDescending;

        NSUInteger i = txAddressIndex(tx1, self.internalAddresses),
                   j = txAddressIndex(tx2, (i == NSNotFound) ? self.externalAddresses : self.internalAddresses);

        if (i == NSNotFound && j != NSNotFound) i = txAddressIndex(tx1, self.externalAddresses);
        if (i == NSNotFound || j == NSNotFound || i == j) return NSOrderedSame;
        return (i > j) ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (void)updateBalance
{
    uint64_t balance = 0, prevBalance = 0, totalSent = 0, totalReceived = 0;
    NSMutableOrderedSet *utxos = [NSMutableOrderedSet orderedSet];
    NSMutableSet *spentOutputs = [NSMutableSet set], *invalidTx = [NSMutableSet set];
    NSMutableArray *balanceHistory = [NSMutableArray array];

    for (BRTransaction *tx in [self.transactions reverseObjectEnumerator]) {
        NSMutableSet *spent = [NSMutableSet set];
        uint32_t i = 0, n = 0;
        BRTransaction *transaction;
        UInt256 h;
        BRUTXO o;

        for (NSValue *hash in tx.inputHashes) {
            n = [tx.inputIndexes[i++] unsignedIntValue];
            [hash getValue:&h];
            [spent addObject:brutxo_obj(((BRUTXO) { h, n }))];
        }

        // check if any inputs are invalid or already spent
        if (tx.blockHeight == TX_UNCONFIRMED &&
            ([spent intersectsSet:spentOutputs] || [[NSSet setWithArray:tx.inputHashes] intersectsSet:invalidTx])) {
            [invalidTx addObject:uint256_obj(tx.txHash)];
            [balanceHistory insertObject:@(balance) atIndex:0];
            continue;
        }

        [spentOutputs unionSet:spent]; // add inputs to spent output set
        n = 0;

        //TODO: don't add outputs below TX_MIN_OUTPUT_AMOUNT
        //TODO: don't add coin generation outputs < 100 blocks deep, or non-final lockTime > 1 block/10min in future
        //NOTE: balance/UTXOs will then need to be recalculated when last block changes
        for (NSString *address in tx.outputAddresses) { // add outputs to UTXO set
            if ([self containsAddress:address]) {
                [utxos addObject:brutxo_obj(((BRUTXO) { tx.txHash, n }))];
                balance += [tx.outputAmounts[n] unsignedLongLongValue];
            }
            
            n++;
        }

        // transaction ordering is not guaranteed, so check the entire UTXO set against the entire spent output set
        [spent setSet:utxos.set];
        [spent intersectSet:spentOutputs];
        
        for (NSValue *output in spent) { // remove any spent outputs from UTXO set
            [output getValue:&o];
            transaction = self.allTx[uint256_obj(o.hash)];
            [utxos removeObject:output];
            balance -= [transaction.outputAmounts[o.n] unsignedLongLongValue];
        }
        
        if (prevBalance < balance) totalReceived += balance - prevBalance;
        if (balance < prevBalance) totalSent += prevBalance - balance;
        [balanceHistory insertObject:@(balance) atIndex:0];
        prevBalance = balance;
    }

    self.invalidTx = invalidTx;
    self.spentOutputs = spentOutputs;
    self.utxos = utxos;
    self.balanceHistory = balanceHistory;
    _totalSent = totalSent;
    _totalReceived = totalReceived;

    if (balance != _balance) {
        _balance = balance;

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletBalanceChangedNotification object:nil];
        });
    }
}

#pragma mark - wallet info

// returns the first unused external address
- (NSString *)receiveAddress
{
    NSString *addr = [self addressesWithGapLimit:1 internal:NO].lastObject;

    //TODO: limit to 10,000 total addresses and utxos for practical usability with bloom filters
    return (addr) ? addr : self.externalAddresses.lastObject;
}

// returns the first unused internal address
- (NSString *)changeAddress
{
    //TODO: limit to 10,000 total addresses and utxos for practical usability with bloom filters
    return [self addressesWithGapLimit:1 internal:YES].lastObject;
}

// all previously generated internal and external addresses
- (NSSet *)addresses
{
    return self.allAddresses;
}

// NSData objects containing serialized UTXOs
- (NSArray *)unspentOutputs
{
    return self.utxos.array;
}

// BRTransaction objects sorted by date, most recent first
- (NSArray *)recentTransactions
{
    //TODO: don't include receive transactions that don't have at least one wallet output >= TX_MIN_OUTPUT_AMOUNT
    return self.transactions.array;
}

// hashes of all wallet transactions
- (NSSet *)txHashes
{
    return self.allTxHashes;
}

// true if the address is controlled by the wallet
- (BOOL)containsAddress:(NSString *)address
{
    return (address && [self.allAddresses containsObject:address]) ? YES : NO;
}

// true if the address was previously used as an input or output in any wallet transaction
- (BOOL)addressIsUsed:(NSString *)address
{
    return (address && [self.usedAddresses containsObject:address]) ? YES : NO;
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
    uint64_t amount = 0, balance = 0, feeAmount = 0;
    BRTransaction *transaction = [BRTransaction new], *tx;
    NSUInteger i = 0, cpfpSize = 0;
    BRUTXO o;

    for (NSData *script in scripts) {
        if (script.length == 0) return nil;
        [transaction addOutputScript:script amount:[amounts[i] unsignedLongLongValue]];
        amount += [amounts[i++] unsignedLongLongValue];
    }

    //TODO: make sure transaction is less than TX_MAX_SIZE
    //TODO: use up all UTXOs for all used addresses to avoid leaving funds in addresses whose public key is revealed
    //TODO: avoid combining addresses in a single transaction when possible to reduce information leakage
    //TODO: use any UTXOs received from output addresses to mitigate an attacker double spending and requesting a refund
    for (NSValue *output in self.utxos) {
        [output getValue:&o];
        tx = self.allTx[uint256_obj(o.hash)];
        if (! tx) continue;
        [transaction addInputHash:tx.txHash index:o.n script:tx.outputScripts[o.n]];
        balance += [tx.outputAmounts[o.n] unsignedLongLongValue];
        
        // add up size of unconfirmed, non-change inputs for child-pays-for-parent fee calculation
        if (tx.blockHeight == TX_UNCONFIRMED && [self amountSentByTransaction:tx] == 0) cpfpSize += tx.size;
        
        if (fee) feeAmount = [self feeForTxSize:transaction.size + 34 + cpfpSize]; // assume we will add a change output
        if (balance == amount + feeAmount || balance >= amount + feeAmount + self.minOutputAmount) break;
    }
    
    if (balance < amount + feeAmount) { // insufficient funds
        NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + feeAmount);
        return nil;
    }
    
    if (balance - (amount + feeAmount) >= self.minOutputAmount) {
        [transaction addOutputAddress:self.changeAddress amount:balance - (amount + feeAmount)];
        [transaction shuffleOutputOrder];
    }
    
    return transaction;
}

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (BOOL)signTransaction:(BRTransaction *)transaction withPrompt:(NSString *)authprompt
{
    int64_t amount = [self amountSentByTransaction:transaction] - [self amountReceivedFromTransaction:transaction];
    NSMutableOrderedSet *externalIndexes = [NSMutableOrderedSet orderedSet],
                        *internalIndexes = [NSMutableOrderedSet orderedSet];

    for (NSString *addr in transaction.inputAddresses) {
        [internalIndexes addObject:@([self.internalAddresses indexOfObject:addr])];
        [externalIndexes addObject:@([self.externalAddresses indexOfObject:addr])];
    }

    [internalIndexes removeObject:@(NSNotFound)];
    [externalIndexes removeObject:@(NSNotFound)];

    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        NSMutableArray *privkeys = [NSMutableArray array];
        NSData *seed = self.seed(authprompt, (amount > 0) ? amount : 0);

        if (! seed) return YES; // user canceled authentication
        [privkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexes.array internal:NO fromSeed:seed]];
        [privkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexes.array internal:YES fromSeed:seed]];
        
        return [transaction signWithPrivateKeys:privkeys];
    }
}

// true if the given transaction is associated with the wallet (even if it hasn't been registered), false otherwise
- (BOOL)containsTransaction:(BRTransaction *)transaction
{
    if ([[NSSet setWithArray:transaction.outputAddresses] intersectsSet:self.allAddresses]) return YES;
    
    NSInteger i = 0;
    
    for (NSValue *txHash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[txHash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];

        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) return YES;
    }
        
    return NO;
}

// records the transaction in the wallet, or returns false if it isn't associated with the wallet
- (BOOL)registerTransaction:(BRTransaction *)transaction
{
    UInt256 txHash = transaction.txHash;
    NSValue *hash = uint256_obj(txHash);
    
    if (uint256_is_zero(txHash)) return NO;
    if (self.allTx[hash] != nil) return YES;
    if (! [self containsTransaction:transaction]) return NO;

    //TODO: verify signatures when possible
    //TODO: handle tx replacement with input sequence numbers (now replacements appear invalid until confirmation)
    
    self.allTx[hash] = transaction;
    [self.allTxHashes addObject:hash];
    [self.transactions insertObject:transaction atIndex:0];
    [self.usedAddresses addObjectsFromArray:transaction.inputAddresses];
    [self.usedAddresses addObjectsFromArray:transaction.outputAddresses];
    [self updateBalance];

    // when a wallet address is used in a transaction, generate a new address to replace it
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO];
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];

    [self.moc performBlock:^{ // add the transaction to core data
        if ([BRTransactionEntity countObjectsMatching:@"txHash == %@",
             [NSData dataWithBytes:&txHash length:sizeof(txHash)]] == 0) {
            [[BRTransactionEntity managedObject] setAttributesFromTx:transaction];
        }
    }];
    
    if ((self.allTx.count % 100) == 0) [BRTransactionEntity saveContext];
    return YES;
}

// removes a transaction from the wallet along with any transactions that depend on its outputs
- (void)removeTransaction:(UInt256)txHash
{
    BRTransaction *transaction = self.allTx[uint256_obj(txHash)];
    NSMutableSet *hashes = [NSMutableSet set];

    for (BRTransaction *tx in self.transactions) { // remove dependent transactions
        if (tx.blockHeight < transaction.blockHeight) break;

        if (! uint256_eq(txHash, tx.txHash) && [tx.inputHashes containsObject:uint256_obj(txHash)]) {
            [hashes addObject:uint256_obj(tx.txHash)];
        }
    }

    for (NSValue *hash in hashes) {
        UInt256 h;

        [hash getValue:&h];
        [self removeTransaction:h];
    }

    [self.allTx removeObjectForKey:uint256_obj(txHash)];
    [self.allTxHashes removeObject:uint256_obj(txHash)];
    if (transaction) [self.transactions removeObject:transaction];
    [self updateBalance];

    [self.moc performBlock:^{ // remove transaction from core data
        [BRTransactionEntity deleteObjects:[BRTransactionEntity objectsMatching:@"txHash == %@",
                                            [NSData dataWithBytes:&txHash length:sizeof(txHash)]]];
    }];
}

// returns the transaction with the given hash if it's been registered in the wallet
- (BRTransaction *)transactionForHash:(UInt256)txHash
{
    return self.allTx[uint256_obj(txHash)];
}

// true if no previous wallet transactions spend any of the given transaction's inputs, and no input tx is invalid
- (BOOL)transactionIsValid:(BRTransaction *)transaction
{
    //TODO: XXX attempted double spends should cause conflicted tx to remain unverified until they're confirmed
    //TODO: XXX conflicted tx with the same wallet outputs should be presented as the same tx to the user
    if (transaction.blockHeight != TX_UNCONFIRMED) return YES;

    if (self.allTx[uint256_obj(transaction.txHash)] != nil) {
        return ([self.invalidTx containsObject:uint256_obj(transaction.txHash)]) ? NO : YES;
    }

    uint32_t i = 0;

    for (NSValue *hash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        UInt256 h;

        [hash getValue:&h];
        if ((tx && ! [self transactionIsValid:tx]) ||
            [self.spentOutputs containsObject:brutxo_obj(((BRUTXO) { h, n }))]) return NO;
    }

    return YES;
}

// returns true if transaction won't be valid by blockHeight + 1 or within the next 10 minutes
- (BOOL)transactionIsPostdated:(BRTransaction *)transaction atBlockHeight:(uint32_t)blockHeight
{
    if (transaction.blockHeight != TX_UNCONFIRMED) return NO; // confirmed transactions are not postdated

    // TODO: XXX consider marking any unconfirmed transaction with a non-final sequence number as postdated
    // TODO: XXX notify that transactions with dust outputs are unlikely to confirm
    for (NSValue *txHash in transaction.inputHashes) { // check if any inputs are known to be postdated
        if ([self transactionIsPostdated:self.allTx[txHash] atBlockHeight:blockHeight]) return YES;
    }

    if (transaction.lockTime <= blockHeight + 1) return NO;

    if (transaction.lockTime >= TX_MAX_LOCK_HEIGHT &&
        transaction.lockTime < [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970 + 10*60) return NO;

    for (NSNumber *sequence in transaction.inputSequences) { // lockTime is ignored if all sequence numbers are final
        if (sequence.unsignedIntValue < UINT32_MAX) return YES;
    }

    return NO;
}

// set the block heights and timestamps for the given transactions
- (void)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes
{
    NSMutableArray *hashes = [NSMutableArray array];

    for (NSValue *hash in txHashes) {
        BRTransaction *tx = self.allTx[hash];
        UInt256 h;

        if (! tx || (tx.blockHeight == height && tx.timestamp == timestamp)) continue;
        tx.blockHeight = height;
        tx.timestamp = timestamp;
        [hash getValue:&h];
        [hashes addObject:[NSData dataWithBytes:&h length:sizeof(h)]];
    }

    if (hashes.count > 0) {
        [self sortTransactions];
        [self updateBalance];

        [self.moc performBlock:^{
            for (BRTransactionEntity *e in [BRTransactionEntity objectsMatching:@"txHash in %@", hashes]) {
                e.blockHeight = height;
                e.timestamp = timestamp;
            }
        }];
    }
}

// returns the amount received by the wallet from the transaction (total outputs to change and/or receive addresses)
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

    for (NSValue *hash in transaction.inputHashes) {
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

    for (NSValue *hash in transaction.inputHashes) {
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

// historical wallet balance after the given transaction, or current balance if transaction is not registered in wallet
- (uint64_t)balanceAfterTransaction:(BRTransaction *)transaction
{
    NSUInteger i = [self.transactions indexOfObject:transaction];
    
    return (i < self.balanceHistory.count) ? [self.balanceHistory[i] unsignedLongLongValue] : self.balance;
}

// Returns the block height after which the transaction is likely to be processed without including a fee. This is based
// on the default satoshi client settings, but on the real network it's way off. In testing, a 0.01btc transaction that
// was expected to take an additional 90 days worth of blocks to confirm was confirmed in under an hour by Eligius pool.
- (uint32_t)blockHeightUntilFree:(BRTransaction *)transaction
{
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger i = 0;

    for (NSValue *hash in transaction.inputHashes) { // get the amounts and block heights of all the transaction inputs
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];

        if (n >= tx.outputAmounts.count) break;
        [amounts addObject:tx.outputAmounts[n]];
        [heights addObject:@(tx.blockHeight)];
    };

    return [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
}

// fee that will be added for a transaction of the given size in bytes
- (uint64_t)feeForTxSize:(NSUInteger)size
{
    uint64_t standardFee = ((size + 999)/1000)*TX_FEE_PER_KB, // standard fee based on tx size rounded up to nearest kb
             fee = (((size*self.feePerKb/1000) + 99)/100)*100; // fee using feePerKb, rounded up to nearest 100 satoshi
    
    return (fee > standardFee) ? fee : standardFee;
}

// outputs below this amount are uneconomical due to fees
- (uint64_t)minOutputAmount
{
    return self.feePerKb*3*(34 + 148)/1000;
}

@end
