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
#import "BRTxMetadataEntity.h"
#import "BRPeerManager.h"
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
@property (nonatomic, strong) NSData *masterPublicKey,*masterBIP32PublicKey;
@property (nonatomic, strong) NSMutableArray *internalBIP44Addresses,*internalBIP32Addresses, *externalBIP44Addresses,*externalBIP32Addresses;
@property (nonatomic, strong) NSMutableSet *allAddresses, *usedAddresses;
@property (nonatomic, strong) NSSet *spentOutputs, *invalidTx, *pendingTx;
@property (nonatomic, strong) NSMutableOrderedSet *transactions;
@property (nonatomic, strong) NSOrderedSet *utxos;
@property (nonatomic, strong) NSMutableDictionary *allTx;
@property (nonatomic, strong) NSArray *balanceHistory;
@property (nonatomic, assign) uint32_t bestBlockHeight;
@property (nonatomic, strong) SeedRequestBlock seed;
@property (nonatomic, strong) NSManagedObjectContext *moc;

@end

@implementation BRWallet

- (instancetype)initWithContext:(NSManagedObjectContext *)context sequence:(id<BRKeySequence>)sequence
                masterPublicKey:(NSData *)masterPublicKey masterBIP32PublicKey:(NSData *)masterBIP32PublicKey seed:(SeedRequestBlock)seed
{
    if (! (self = [super init])) return nil;
    
    NSMutableSet *updateTx = [NSMutableSet set];
    
    self.moc = context;
    self.sequence = sequence;
    self.masterPublicKey = masterPublicKey;
    self.masterBIP32PublicKey = masterBIP32PublicKey;
    self.seed = seed;
    self.allTx = [NSMutableDictionary dictionary];
    self.transactions = [NSMutableOrderedSet orderedSet];
    self.internalBIP32Addresses = [NSMutableArray array];
    self.internalBIP44Addresses = [NSMutableArray array];
    self.externalBIP32Addresses = [NSMutableArray array];
    self.externalBIP44Addresses = [NSMutableArray array];
    self.allAddresses = [NSMutableSet set];
    self.usedAddresses = [NSMutableSet set];
    
    [self.moc performBlockAndWait:^{
        [BRAddressEntity setContext:self.moc];
        [BRTransactionEntity setContext:self.moc];
        [BRTxMetadataEntity setContext:self.moc];
        
        for (BRAddressEntity *e in [BRAddressEntity allObjects]) {
            @autoreleasepool {
                NSMutableArray *a = (e.purpose == 44)?((e.internal) ? self.internalBIP44Addresses : self.externalBIP44Addresses) : ((e.internal) ? self.internalBIP32Addresses : self.externalBIP32Addresses);
                
                while (e.index >= a.count) [a addObject:[NSNull null]];
                a[e.index] = e.address;
                [self.allAddresses addObject:e.address];
            }
        }
        
        for (BRTxMetadataEntity *e in [BRTxMetadataEntity allObjects]) {
            @autoreleasepool {
                if (e.type != TX_MDTYPE_MSG) continue;
                
                BRTransaction *tx = e.transaction;
                NSValue *hash = (tx) ? uint256_obj(tx.txHash) : nil;
                
                if (! tx) continue;
                self.allTx[hash] = tx;
                [self.transactions addObject:tx];
                [self.usedAddresses addObjectsFromArray:tx.inputAddresses];
                [self.usedAddresses addObjectsFromArray:tx.outputAddresses];
            }
        }
        
        if ([BRTransactionEntity countAllObjects] > self.allTx.count) {
            // pre-fetch transaction inputs and outputs
            [BRTxInputEntity allObjects];
            [BRTxOutputEntity allObjects];
            
            for (BRTransactionEntity *e in [BRTransactionEntity allObjects]) {
                @autoreleasepool {
                    BRTransaction *tx = e.transaction;
                    NSValue *hash = (tx) ? uint256_obj(tx.txHash) : nil;
                    
                    if (! tx || self.allTx[hash] != nil) continue;
                    
                    [updateTx addObject:tx];
                    self.allTx[hash] = tx;
                    [self.transactions addObject:tx];
                    [self.usedAddresses addObjectsFromArray:tx.inputAddresses];
                    [self.usedAddresses addObjectsFromArray:tx.outputAddresses];
                }
            }
        }
    }];
    
    if (updateTx.count > 0) {
        [self.moc performBlock:^{
            for (BRTransaction *tx in updateTx) {
                [[BRTxMetadataEntity managedObject] setAttributesFromTx:tx];
            }
            
            [BRTxMetadataEntity saveContext];
        }];
    }
    
    [self sortTransactions];
    _balance = UINT64_MAX; // trigger balance changed notification even if balance is zero
    [self updateBalance];
    
    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

-(NSArray*)internalAddresses {
    return [self.internalBIP32Addresses arrayByAddingObjectsFromArray:self.internalBIP44Addresses];
}

-(NSArray*)externalAddresses {
    return [self.externalBIP32Addresses arrayByAddingObjectsFromArray:self.externalBIP44Addresses];
}

// Wallets are composed of chains of addresses. Each chain is traversed until a gap of a certain number of addresses is
// found that haven't been used in any transactions. This method returns an array of <gapLimit> unused addresses
// following the last used address in the chain. The internal chain is used for change addresses and the external chain
// for receive addresses.
- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    NSMutableArray *a = [NSMutableArray arrayWithArray:(internal) ? self.internalBIP44Addresses : self.externalBIP44Addresses];
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
        [a setArray:(internal) ? self.internalBIP44Addresses : self.externalBIP44Addresses];
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
                e.purpose = 44;
                e.account = 0;
                e.address = addr;
                e.index = n;
                e.internal = internal;
            }];
            
            [self.allAddresses addObject:addr];
            [(internal) ? self.internalBIP44Addresses : self.externalBIP44Addresses addObject:addr];
            [a addObject:addr];
            n++;
        }
        
        return a;
    }
}

- (NSArray *)addressesBIP32NoPurposeWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    @synchronized(self) {
        NSMutableArray *a = [NSMutableArray arrayWithArray:(internal) ? self.internalBIP32Addresses : self.externalBIP32Addresses];
        NSUInteger i = a.count;
        
        unsigned n = (unsigned)i;
        
        // keep only the trailing contiguous block of addresses with no transactions
        while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
            i--;
        }
        
        if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
        if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];
        
        while (a.count < gapLimit) { // generate new addresses up to gapLimit
            NSData *pubKey = [self.sequence publicKey:n internal:internal masterPublicKey:self.masterBIP32PublicKey];
            NSString *addr = [BRKey keyWithPublicKey:pubKey].address;
            
            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }
            
            [self.moc performBlock:^{ // store new address in core data
                BRAddressEntity *e = [BRAddressEntity managedObject];
                e.purpose = 0;
                e.account = 0;
                e.address = addr;
                e.index = n;
                e.internal = internal;
            }];
            
            [self.allAddresses addObject:addr];
            [(internal) ? self.internalBIP32Addresses : self.externalBIP32Addresses addObject:addr];
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
        
        NSValue *hash1 = uint256_obj(tx1.txHash), *hash2 = uint256_obj(tx2.txHash);
        
        if ([tx1.inputHashes containsObject:hash2]) return YES;
        if ([tx2.inputHashes containsObject:hash1]) return NO;
        if ([self.invalidTx containsObject:hash1] && ! [self.invalidTx containsObject:hash2]) return YES;
        if ([self.pendingTx containsObject:hash1] && ! [self.pendingTx containsObject:hash2]) return YES;
        
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
    NSMutableSet *spentOutputs = [NSMutableSet set], *invalidTx = [NSMutableSet set], *pendingTx = [NSMutableSet set];
    NSMutableArray *balanceHistory = [NSMutableArray array];
    uint32_t now = [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970;
    
    for (BRTransaction *tx in [self.transactions reverseObjectEnumerator]) {
        @autoreleasepool {
            NSMutableSet *spent = [NSMutableSet set];
            NSSet *inputs;
            uint32_t i = 0, n = 0;
            BOOL pending = NO;
            UInt256 h;
            
            for (NSValue *hash in tx.inputHashes) {
                n = [tx.inputIndexes[i++] unsignedIntValue];
                [hash getValue:&h];
                [spent addObject:brutxo_obj(((BRUTXO) { h, n }))];
            }
            
            inputs = [NSSet setWithArray:tx.inputHashes];
            
            // check if any inputs are invalid or already spent
            if (tx.blockHeight == TX_UNCONFIRMED &&
                ([spent intersectsSet:spentOutputs] || [inputs intersectsSet:invalidTx])) {
                [invalidTx addObject:uint256_obj(tx.txHash)];
                [balanceHistory insertObject:@(balance) atIndex:0];
                continue;
            }
            
            [spentOutputs unionSet:spent]; // add inputs to spent output set
            n = 0;
            
            // check if any inputs are pending
            if (tx.blockHeight == TX_UNCONFIRMED) {
                if (tx.size > TX_MAX_SIZE) pending = YES; // check transaction size is under TX_MAX_SIZE
                
                for (NSNumber *sequence in tx.inputSequences) {
                    if (sequence.unsignedIntValue < UINT32_MAX - 1) pending = YES; // check for replace-by-fee
                    if (sequence.unsignedIntValue < UINT32_MAX && tx.lockTime < TX_MAX_LOCK_HEIGHT &&
                        tx.lockTime > self.bestBlockHeight + 1) pending = YES; // future lockTime
                    if (sequence.unsignedIntValue < UINT32_MAX && tx.lockTime >= TX_MAX_LOCK_HEIGHT &&
                        tx.lockTime > now) pending = YES; // future locktime
                }
                
                for (NSNumber *amount in tx.outputAmounts) { // check that no outputs are dust
                    if (amount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) pending = YES;
                }
                
                if (pending || [inputs intersectsSet:pendingTx]) {
                    [pendingTx addObject:uint256_obj(tx.txHash)];
                    [balanceHistory insertObject:@(balance) atIndex:0];
                    continue;
                }
            }
            
            //TODO: don't add outputs below TX_MIN_OUTPUT_AMOUNT
            //TODO: don't add coin generation outputs < 100 blocks deep
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
                BRTransaction *transaction;
                BRUTXO o;
                
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
    }
    
    self.invalidTx = invalidTx;
    self.pendingTx = pendingTx;
    self.spentOutputs = spentOutputs;
    self.utxos = utxos;
    self.balanceHistory = balanceHistory;
    _totalSent = totalSent;
    _totalReceived = totalReceived;
    
    if (balance != _balance) {
        _balance = balance;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(balanceNotification) object:nil];
            [self performSelector:@selector(balanceNotification) withObject:nil afterDelay:0.1];
        });
    }
}

- (void)balanceNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletBalanceChangedNotification object:nil];
}

// MARK: - wallet info

// returns the first unused external address
- (NSString *)receiveAddress
{
    //TODO: limit to 10,000 total addresses and utxos for practical usability with bloom filters
#if ADDRESS_DEFAULT == BIP32_PURPOSE
    NSString *addr = [self addressesBIP32NoPurposeWithGapLimit:1 internal:NO].lastObject;
    return (addr) ? addr : self.externalBIP32Addresses.lastObject;
#else
    NSString *addr = [self addressesWithGapLimit:1 internal:NO].lastObject;
    return (addr) ? addr : self.externalBIP44Addresses.lastObject;
#endif
}

// returns the first unused internal address
- (NSString *)changeAddress
{
    //TODO: limit to 10,000 total addresses and utxos for practical usability with bloom filters
#if ADDRESS_DEFAULT == BIP32_PURPOSE
    return [self addressesBIP32NoPurposeWithGapLimit:1 internal:YES].lastObject;
#else
    return [self addressesWithGapLimit:1 internal:YES].lastObject;
#endif
}

// all previously generated external addresses
- (NSSet *)allReceiveAddresses
{
    return [NSSet setWithArray:[self.externalBIP32Addresses arrayByAddingObjectsFromArray:self.externalBIP44Addresses]];
}

// all previously generated external addresses
- (NSSet *)allChangeAddresses
{
    return [NSSet setWithArray:[self.internalBIP32Addresses arrayByAddingObjectsFromArray:self.internalBIP44Addresses]];
}

// NSData objects containing serialized UTXOs
- (NSArray *)unspentOutputs
{
    return self.utxos.array;
}

// last 100 transactions sorted by date, most recent first
- (NSArray *)recentTransactions
{
    //TODO: don't include receive transactions that don't have at least one wallet output >= TX_MIN_OUTPUT_AMOUNT
    return [self.transactions.array subarrayWithRange:NSMakeRange(0, (self.transactions.count > 100) ? 100 :
                                                                  self.transactions.count)];
}

// all wallet transactions sorted by date, most recent first
- (NSArray *)allTransactions
{
    return self.transactions.array;
}

// true if the address is controlled by the wallet
- (BOOL)containsAddress:(NSString *)address
{
    return (address && [self.allAddresses containsObject:address]) ? YES : NO;
}

// gives the purpose of the address (either 0 or 44 for now)
-(NSUInteger)addressPurpose:(NSString *)address
{
    if ([self.internalBIP44Addresses containsObject:address] || [self.externalBIP44Addresses containsObject:address]) return BIP44_PURPOSE;
    if ([self.internalBIP32Addresses containsObject:address] || [self.externalBIP32Addresses containsObject:address]) return BIP32_PURPOSE;
    return NSIntegerMax;
}

// true if the address was previously used as an input or output in any wallet transaction
- (BOOL)addressIsUsed:(NSString *)address
{
    return (address && [self.usedAddresses containsObject:address]) ? YES : NO;
}

// MARK: - transactions

// returns an unsigned transaction that sends the specified amount from the wallet to the given address
- (BRTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    NSMutableData *script = [NSMutableData data];
    
    [script appendScriptPubKeyForAddress:address];
    
    return [self transactionForAmounts:@[@(amount)] toOutputScripts:@[script] withFee:fee];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee {
    return [self transactionForAmounts:amounts toOutputScripts:scripts withFee:fee isInstant:FALSE toShapeshiftAddress:nil];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee  isInstant:(BOOL)isInstant {
    return [self transactionForAmounts:amounts toOutputScripts:scripts withFee:fee isInstant:isInstant toShapeshiftAddress:nil];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee isInstant:(BOOL)isInstant toShapeshiftAddress:(NSString*)shapeshiftAddress
{
    
    uint64_t amount = 0, balance = 0, feeAmount = 0;
    BRTransaction *transaction = [BRTransaction new], *tx;
    NSUInteger i = 0, cpfpSize = 0;
    BRUTXO o;
    
    if (amounts.count != scripts.count || amounts.count < 1) return nil; // sanity check
    
    for (NSData *script in scripts) {
        if (script.length == 0) return nil;
        [transaction addOutputScript:script amount:[amounts[i] unsignedLongLongValue]];
        amount += [amounts[i++] unsignedLongLongValue];
    }
    
    //TODO: use up all UTXOs for all used addresses to avoid leaving funds in addresses whose public key is revealed
    //TODO: avoid combining addresses in a single transaction when possible to reduce information leakage
    //TODO: use up UTXOs received from any of the output scripts that this transaction sends funds to, to mitigate an
    //      attacker double spending and requesting a refund
    for (NSValue *output in self.utxos) {
        [output getValue:&o];
        tx = self.allTx[uint256_obj(o.hash)];
        if (! tx) continue;
        //for example the tx block height is 25, can only send after the chain block height is 31 for previous confirmations needed of 6
        if (isInstant && (tx.blockHeight >= (self.blockHeight - IX_PREVIOUS_CONFIRMATIONS_NEEDED))) continue;
        [transaction addInputHash:tx.txHash index:o.n script:tx.outputScripts[o.n]];
        
        if (transaction.size + 34 > TX_MAX_SIZE) { // transaction size-in-bytes too large
            NSUInteger txSize = 10 + self.utxos.count*148 + (scripts.count + 1)*34;
            
            // check for sufficient total funds before building a smaller transaction
            if (self.balance < amount + [self feeForTxSize:txSize + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]) {
                NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", self.balance,
                      amount + [self feeForTxSize:txSize + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]);
                return nil;
            }
            
            uint64_t lastAmount = [amounts.lastObject unsignedLongLongValue];
            NSArray *newAmounts = [amounts subarrayWithRange:NSMakeRange(0, amounts.count - 1)],
            *newScripts = [scripts subarrayWithRange:NSMakeRange(0, scripts.count - 1)];
            
            if (lastAmount > amount + feeAmount + self.minOutputAmount - balance) { // reduce final output amount
                newAmounts = [newAmounts arrayByAddingObject:@(lastAmount - (amount + feeAmount - balance))];
                newScripts = [newScripts arrayByAddingObject:scripts.lastObject];
            }
            
            return [self transactionForAmounts:newAmounts toOutputScripts:newScripts withFee:fee];
        }
        
        balance += [tx.outputAmounts[o.n] unsignedLongLongValue];
        
        // add up size of unconfirmed, non-change inputs for child-pays-for-parent fee calculation
        // don't include parent tx with more than 10 inputs or 10 outputs
        if (tx.blockHeight == TX_UNCONFIRMED && tx.inputHashes.count <= 10 && tx.outputAmounts.count <= 10 &&
            [self amountSentByTransaction:tx] == 0) cpfpSize += tx.size;
        
        if (fee) {
            feeAmount = [self feeForTxSize:transaction.size + 34 + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]; // assume we will add a change output
            if (self.balance > amount) feeAmount += (self.balance - amount) % 100; // round off balance to 100 satoshi
        }
        
        if (balance == amount + feeAmount || balance >= amount + feeAmount + self.minOutputAmount) break;
    }
    
    transaction.isInstant = isInstant;
    
    if (balance < amount + feeAmount) { // insufficient funds
        NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + feeAmount);
        return nil;
    }
    
    if (shapeshiftAddress) {
        [transaction addOutputShapeshiftAddress:shapeshiftAddress];
    }
    
    if (balance - (amount + feeAmount) >= self.minOutputAmount) {
        [transaction addOutputAddress:self.changeAddress amount:balance - (amount + feeAmount)];
        [transaction shuffleOutputOrder];
    }
    
    return transaction;
    
    
}

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (void)signTransaction:(BRTransaction *)transaction withPrompt:(NSString *)authprompt completion:(TransactionValidityCompletionBlock)completion;
{
    int64_t amount = [self amountSentByTransaction:transaction] - [self amountReceivedFromTransaction:transaction];
    NSMutableOrderedSet *externalIndexesPurpose44 = [NSMutableOrderedSet orderedSet],
    *internalIndexesPurpose44 = [NSMutableOrderedSet orderedSet],
    *externalIndexesNoPurpose = [NSMutableOrderedSet orderedSet],
    *internalIndexesNoPurpose = [NSMutableOrderedSet orderedSet];
    
    for (NSString *addr in transaction.inputAddresses) {
        NSInteger index = [self.internalBIP44Addresses indexOfObject:addr];
        if (index != NSNotFound) {
            [internalIndexesPurpose44 addObject:@(index)];
            continue;
        }
        index = [self.externalBIP44Addresses indexOfObject:addr];
        if (index != NSNotFound) {
            [externalIndexesPurpose44 addObject:@(index)];
            continue;
        }
        index = [self.internalBIP32Addresses indexOfObject:addr];
        if (index != NSNotFound) {
            [internalIndexesNoPurpose addObject:@(index)];
            continue;
        }
        index = [self.externalBIP32Addresses indexOfObject:addr];
        if (index != NSNotFound) {
            [externalIndexesNoPurpose addObject:@(index)];
            continue;
        }
    }
    
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        self.seed(authprompt, (amount > 0) ? amount : 0,^void (NSData * _Nullable seed) {
            if (! seed) {
                completion(YES);
            } else {
                NSMutableArray *privkeys = [NSMutableArray array];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexesPurpose44.array purpose:BIP44_PURPOSE internal:NO fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexesPurpose44.array purpose:BIP44_PURPOSE internal:YES fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexesNoPurpose.array purpose:BIP32_PURPOSE internal:NO fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexesNoPurpose.array purpose:BIP32_PURPOSE internal:YES fromSeed:seed]];
                
                BOOL signedSuccessfully = [transaction signWithPrivateKeys:privkeys];
                completion(signedSuccessfully);
            }
        });
    }
}

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (void)signBIP32Transaction:(BRTransaction *)transaction withPrompt:(NSString *)authprompt completion:(TransactionValidityCompletionBlock)completion;
{
    int64_t amount = [self amountSentByTransaction:transaction] - [self amountReceivedFromTransaction:transaction];
    NSMutableOrderedSet *externalIndexes = [NSMutableOrderedSet orderedSet],
    *internalIndexes = [NSMutableOrderedSet orderedSet];
    
    for (NSString *addr in transaction.inputAddresses) {
        [internalIndexes addObject:@([self.internalBIP32Addresses indexOfObject:addr])];
        [externalIndexes addObject:@([self.externalBIP32Addresses indexOfObject:addr])];
    }
    
    [internalIndexes removeObject:@(NSNotFound)];
    [externalIndexes removeObject:@(NSNotFound)];
    
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        self.seed(authprompt, (amount > 0) ? amount : 0,^void (NSData * _Nullable seed) {
            if (! seed) {
                completion(YES);
            } else {
                NSMutableArray *privkeys = [NSMutableArray array];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexes.array purpose:BIP32_PURPOSE internal:NO fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexes.array purpose:BIP32_PURPOSE internal:YES fromSeed:seed]];
                
                BOOL signedSuccessfully = [transaction signWithPrivateKeys:privkeys];
                completion(signedSuccessfully);
            }
        });
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
    
    if (! [self containsTransaction:transaction]) {
        if (transaction.blockHeight == TX_UNCONFIRMED) self.allTx[hash] = transaction;
        return NO;
    }
    
    if (self.allTx[hash] != nil) return YES;
    
    //TODO: handle tx replacement with input sequence numbers (now replacements appear invalid until confirmation)
    NSLog(@"[BRWallet] received unseen transaction %@", transaction);
    
    self.allTx[hash] = transaction;
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
        
        if ([BRTxMetadataEntity countObjectsMatching:@"txHash == %@ && type == %d",
             [NSData dataWithBytes:&txHash length:sizeof(txHash)], TX_MDTYPE_MSG] == 0) {
            [[BRTxMetadataEntity managedObject] setAttributesFromTx:transaction];
        }
    }];
    
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
    if (transaction) [self.transactions removeObject:transaction];
    [self updateBalance];
    
    [self.moc performBlock:^{ // remove transaction from core data
        [BRTransactionEntity deleteObjects:[BRTransactionEntity objectsMatching:@"txHash == %@",
                                            [NSData dataWithBytes:&txHash length:sizeof(txHash)]]];
        [BRTxMetadataEntity deleteObjects:[BRTxMetadataEntity objectsMatching:@"txHash == %@",
                                           [NSData dataWithBytes:&txHash length:sizeof(txHash)]]];
    }];
}

// returns the transaction with the given hash if it's been registered in the wallet (might also return non-registered)
- (BRTransaction *)transactionForHash:(UInt256)txHash
{
    return self.allTx[uint256_obj(txHash)];
}

// true if no previous wallet transactions spend any of the given transaction's inputs, and no input tx is invalid
- (BOOL)transactionIsValid:(BRTransaction *)transaction
{
    //TODO: XXX attempted double spends should cause conflicted tx to remain unverified until they're confirmed
    //TODO: XXX verify signatures for spends
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

// true if transaction cannot be immediately spent (i.e. if it or an input tx can be replaced-by-fee)
- (BOOL)transactionIsPending:(BRTransaction *)transaction
{
    if (transaction.blockHeight != TX_UNCONFIRMED) return NO; // confirmed transactions are not pending
    if (transaction.size > TX_MAX_SIZE) return YES; // check transaction size is under TX_MAX_SIZE
    
    // check for future lockTime or replace-by-fee: https://github.com/bitcoin/bips/blob/master/bip-0125.mediawiki
    for (NSNumber *sequence in transaction.inputSequences) {
        if (sequence.unsignedIntValue < UINT32_MAX - 1) return YES;
        if (sequence.unsignedIntValue < UINT32_MAX && transaction.lockTime < TX_MAX_LOCK_HEIGHT &&
            transaction.lockTime > self.bestBlockHeight + 1) return YES;
        if (sequence.unsignedIntValue < UINT32_MAX && transaction.lockTime >= TX_MAX_LOCK_HEIGHT &&
            transaction.lockTime > [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970) return YES;
    }
    
    for (NSNumber *amount in transaction.outputAmounts) { // check that no outputs are dust
        if (amount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) return YES;
    }
    
    for (NSValue *txHash in transaction.inputHashes) { // check if any inputs are known to be pending
        if ([self transactionIsPending:self.allTx[txHash]]) return YES;
    }
    
    return NO;
}

// true if tx is considered 0-conf safe (valid and not pending, timestamp is greater than 0, and no unverified inputs)
- (BOOL)transactionIsVerified:(BRTransaction *)transaction
{
    if (transaction.blockHeight != TX_UNCONFIRMED) return YES; // confirmed transactions are always verified
    if (transaction.timestamp == 0) return NO; // a timestamp of 0 indicates transaction is to remain unverified
    if (! [self transactionIsValid:transaction] || [self transactionIsPending:transaction]) return NO;
    
    for (NSValue *txHash in transaction.inputHashes) { // check if any inputs are known to be unverfied
        if (! self.allTx[txHash]) continue;
        if (! [self transactionIsVerified:self.allTx[txHash]]) return NO;
    }
    
    return YES;
}

// set the block heights and timestamps for the given transactions, use a height of TX_UNCONFIRMED and timestamp of 0 to
// indicate a transaction and it's dependents should remain marked as unverified (not 0-conf safe)
- (NSArray *)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes
{
    NSMutableArray *hashes = [NSMutableArray array], *updated = [NSMutableArray array];
    BOOL needsUpdate = NO;
    
    if (height != TX_UNCONFIRMED && height > self.bestBlockHeight) self.bestBlockHeight = height;
    
    for (NSValue *hash in txHashes) {
        BRTransaction *tx = self.allTx[hash];
        UInt256 h;
        
        if (! tx || (tx.blockHeight == height && tx.timestamp == timestamp)) continue;
        tx.blockHeight = height;
        tx.timestamp = timestamp;
        
        if ([self containsTransaction:tx]) {
            [hash getValue:&h];
            [hashes addObject:[NSData dataWithBytes:&h length:sizeof(h)]];
            [updated addObject:hash];
            if ([self.pendingTx containsObject:hash] || [self.invalidTx containsObject:hash]) needsUpdate = YES;
        }
        else if (height != TX_UNCONFIRMED) [self.allTx removeObjectForKey:hash]; // remove confirmed non-wallet tx
    }
    
    if (hashes.count > 0) {
        if (needsUpdate) {
            [self sortTransactions];
            [self updateBalance];
        }
        
        [self.moc performBlockAndWait:^{
            @autoreleasepool {
                NSMutableSet *entities = [NSMutableSet set];
                
                for (BRTransactionEntity *e in [BRTransactionEntity objectsMatching:@"txHash in %@", hashes]) {
                    e.blockHeight = height;
                    e.timestamp = timestamp;
                    [entities addObject:e];
                }
                
                for (BRTxMetadataEntity *e in [BRTxMetadataEntity objectsMatching:@"txHash in %@ && type == %d", hashes,
                                               TX_MDTYPE_MSG]) {
                    @autoreleasepool {
                        BRTransaction *tx = e.transaction;
                        
                        tx.blockHeight = height;
                        tx.timestamp = timestamp;
                        [e setAttributesFromTx:tx];
                        [entities addObject:e];
                    }
                }
                
                if (height != TX_UNCONFIRMED) {
                    // BUG: XXX saving the tx.blockHeight and the block it's contained in both need to happen together
                    // as an atomic db operation. If the tx.blockHeight is saved but the block isn't when the app exits,
                    // then a re-org that happens afterward can potentially result in an invalid tx showing as confirmed
                    [BRTxMetadataEntity saveContext];
                    
                    for (NSManagedObject *e in entities) {
                        [self.moc refreshObject:e mergeChanges:NO];
                    }
                }
            }
        }];
    }
    
    return updated;
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
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
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
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
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
- (uint64_t)feeForTxSize:(NSUInteger)size isInstant:(BOOL)isInstant inputCount:(NSInteger)inputCount
{
    if (isInstant) {
        return TX_FEE_PER_INPUT*inputCount;
    } else {
        uint64_t standardFee = ((size + 999)/1000)*TX_FEE_PER_KB, // standard fee based on tx size rounded up to nearest kb
        fee = (((size*self.feePerKb/1000) + 99)/100)*100; // fee using feePerKb, rounded up to nearest 100 satoshi
        
        return (fee > standardFee) ? fee : standardFee;
    }
}

// outputs below this amount are uneconomical due to fees
- (uint64_t)minOutputAmount
{
    uint64_t amount = (TX_MIN_OUTPUT_AMOUNT*self.feePerKb + MIN_FEE_PER_KB - 1)/MIN_FEE_PER_KB;
    
    return (amount > TX_MIN_OUTPUT_AMOUNT) ? amount : TX_MIN_OUTPUT_AMOUNT;
}

- (uint64_t)maxOutputAmountUsingInstantSend:(BOOL)instantSend
{
    return [self maxOutputAmountWithConfirmationCount:0 usingInstantSend:instantSend];
}

- (uint32_t)blockHeight
{
    static uint32_t height = 0;
    uint32_t h = [BRPeerManager sharedInstance].lastBlockHeight;
    
    if (h > height) height = h;
    return height;
}

- (uint64_t)maxOutputAmountWithConfirmationCount:(uint64_t)confirmationCount usingInstantSend:(BOOL)instantSend
{
    BRUTXO o;
    BRTransaction *tx;
    NSUInteger inputCount = 0;
    uint64_t amount = 0, fee;
    size_t cpfpSize = 0, txSize;
    
    for (NSValue *output in self.utxos) {
        [output getValue:&o];
        tx = self.allTx[uint256_obj(o.hash)];
        if (o.n >= tx.outputAmounts.count) continue;
        if (confirmationCount && (tx.blockHeight >= (self.blockHeight - confirmationCount))) continue;
        inputCount++;
        amount += [tx.outputAmounts[o.n] unsignedLongLongValue];
        
        // size of unconfirmed, non-change inputs for child-pays-for-parent fee
        // don't include parent tx with more than 10 inputs or 10 outputs
        if (tx.blockHeight == TX_UNCONFIRMED && tx.inputHashes.count <= 10 && tx.outputAmounts.count <= 10 &&
            [self amountSentByTransaction:tx] == 0) cpfpSize += tx.size;
    }
    
    
    txSize = 8 + [NSMutableData sizeOfVarInt:inputCount] + TX_INPUT_SIZE*inputCount +
    [NSMutableData sizeOfVarInt:2] + TX_OUTPUT_SIZE*2;
    fee = [self feeForTxSize:txSize + cpfpSize isInstant:instantSend inputCount:inputCount];
    return (amount > fee) ? amount - fee : 0;
}

@end
