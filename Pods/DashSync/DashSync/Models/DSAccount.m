//
//  DSWallet.m
//  DashSync
//
//  Created by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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

#import "DSDerivationPath.h"
#import "DSAccount.h"
#import "DSWallet.h"
#import "DSKey.h"
#import "DSAddressEntity+CoreDataClass.h"
#import "DSChain.h"
#import "DSTransaction.h"
#import "DSTransactionEntity+CoreDataClass.h"
#import "DSTxInputEntity+CoreDataClass.h"
#import "DSTxOutputEntity+CoreDataClass.h"
#import "DSDerivationPathEntity+CoreDataClass.h"
#import "DSChainPeerManager.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Dash.h"
#import "NSManagedObject+Sugar.h"
#import "DSWalletManager.h"
#import "DSGovernanceSyncManager.h"
#import "DSAccountEntity+CoreDataClass.h"

@class DSDerivationPath,DSAccount;

@interface DSAccount()

// BIP 43 derivation paths
@property (nonatomic, strong) NSMutableArray<DSDerivationPath *> * mDerivationPaths;

@property (nonatomic, strong) NSArray *balanceHistory;

@property (nonatomic, strong) NSSet *spentOutputs, *invalidTx, *pendingTx;
@property (nonatomic, strong) NSMutableOrderedSet *transactions;

@property (nonatomic, strong) NSOrderedSet *utxos;
@property (nonatomic, strong) NSMutableDictionary *allTx;

@property (nonatomic, strong) NSManagedObjectContext * moc;

// the total amount spent from the account (excluding change)
@property (nonatomic, readonly) uint64_t totalSent;

// the total amount received to the account (excluding change)
@property (nonatomic, readonly) uint64_t totalReceived;

@property (nonatomic, strong) DSDerivationPath * bip44DerivationPath;

@property (nonatomic, strong) DSDerivationPath * bip32DerivationPath;

@property (nonatomic, assign) BOOL isViewOnlyAccount;


@end

@implementation DSAccount : NSObject

+(DSAccount*)accountWithDerivationPaths:(NSArray<DSDerivationPath *> *)derivationPaths {
    return [[self alloc] initWithDerivationPaths:derivationPaths];
}

-(void)verifyAndAssignAddedDerivationPaths:(NSArray<DSDerivationPath *> *)derivationPaths {
    if (![self.mDerivationPaths count])
        _accountNumber = (uint32_t)[[derivationPaths firstObject] indexAtPosition:[[derivationPaths firstObject] length] - 1];
    for (int i = 0;i<[derivationPaths count];i++) {
        DSDerivationPath * derivationPath = [derivationPaths objectAtIndex:i];
        if (derivationPath.reference == DSDerivationPathReference_BIP32) {
            if (self.bip32DerivationPath) {
                NSAssert(TRUE,@"There should only be one BIP 32 derivation path");
            }
            self.bip32DerivationPath = derivationPath;
        } else if (derivationPath.reference == DSDerivationPathReference_BIP44) {
            if (self.bip44DerivationPath) {
                NSAssert(TRUE,@"There should only be one BIP 44 derivation path");
            }
            self.bip44DerivationPath = derivationPath;
        }
        for (int j = i + 1;j<[derivationPaths count];j++) {
            DSDerivationPath * derivationPath2 = [derivationPaths objectAtIndex:j];
            NSAssert(![derivationPath isDerivationPathEqual:derivationPath2],@"Derivation paths should all be different");
        }
        for (DSDerivationPath * derivationPath3 in self.mDerivationPaths) {
            NSAssert(![derivationPath isDerivationPathEqual:derivationPath3],@"Added derivation paths should be different from existing ones on account");
        }
        if ([self.mDerivationPaths count] || i != 0) {
            NSAssert([derivationPath indexAtPosition:[derivationPath length] - 1] == _accountNumber, @"all derivationPaths need to be on same account");
        }
    }
}

-(instancetype)initWithDerivationPaths:(NSArray<DSDerivationPath *> *)derivationPaths {
    if (! (self = [super init])) return nil;
    NSAssert([derivationPaths count], @"derivationPaths can not be empty");
    [self verifyAndAssignAddedDerivationPaths:derivationPaths];
    self.mDerivationPaths = [derivationPaths mutableCopy];
    for (DSDerivationPath * derivationPath in derivationPaths) {
        derivationPath.account = self;
    }
    self.transactions = [NSMutableOrderedSet orderedSet];
    self.allTx = [NSMutableDictionary dictionary];
    self.moc = [NSManagedObject context];
    self.isViewOnlyAccount = FALSE;
    return self;
}

-(instancetype)initAsViewOnlyWithDerivationPaths:(NSArray<DSDerivationPath *> *)derivationPaths {
    if (! (self = [super init])) return nil;
    self.mDerivationPaths = [derivationPaths mutableCopy];
    for (DSDerivationPath * derivationPath in derivationPaths) {
        derivationPath.account = self;
    }
    self.transactions = [NSMutableOrderedSet orderedSet];
    self.allTx = [NSMutableDictionary dictionary];
    self.moc = [NSManagedObject context];
    self.isViewOnlyAccount = TRUE;
    
    return self;
}

-(void)loadTransactions {
    [self.moc performBlockAndWait:^{
        [DSTransactionEntity setContext:self.moc];
        [DSAccountEntity setContext:self.moc];
        [DSTxInputEntity setContext:self.moc];
        [DSTxOutputEntity setContext:self.moc];
        [DSDerivationPathEntity setContext:self.moc];
        if ([DSTransactionEntity countAllObjects] > self.allTx.count) {
            // pre-fetch transaction inputs and outputs
            [DSTxInputEntity allObjects];
            [DSTxOutputEntity allObjects];
            DSAccountEntity * accountEntity = [DSAccountEntity accountEntityForWalletUniqueID:self.wallet.uniqueID index:self.accountNumber];
            for (DSTxOutputEntity *e in accountEntity.transactionOutputs) {
                @autoreleasepool {
                    
                    DSTransaction *transaction = [e.transaction transactionForChain:self.wallet.chain];
                    NSValue *hash = (transaction) ? uint256_obj(transaction.txHash) : nil;
                    
                    if (! transaction || self.allTx[hash] != nil) continue;
                    self.allTx[hash] = transaction;
                    [self.transactions addObject:transaction];
                }
            }
        }
    }];
    
    [self sortTransactions];
    _balance = UINT64_MAX; // trigger balance changed notification even if balance is zero
    [self updateBalance];
}

-(void)removeDerivationPath:(DSDerivationPath*)derivationPath {
    if ([self.mDerivationPaths containsObject:derivationPath]) {
        [self.mDerivationPaths removeObject:derivationPath];
    }
}

-(void)addDerivationPath:(DSDerivationPath*)derivationPath {
    if (!_isViewOnlyAccount) {
        [self verifyAndAssignAddedDerivationPaths:@[derivationPath]];
    }
    [self.mDerivationPaths addObject:derivationPath];
}

-(void)addDerivationPathsFromArray:(NSArray<DSDerivationPath *> *)derivationPaths {
    if (!_isViewOnlyAccount) {
        [self verifyAndAssignAddedDerivationPaths:derivationPaths];
    }
    [self.mDerivationPaths addObjectsFromArray:derivationPaths];
}

-(NSArray*)derivationPaths {
    return [self.mDerivationPaths copy];
}

-(void)setDefaultDerivationPath:(DSDerivationPath *)defaultDerivationPath {
    NSAssert([self.mDerivationPaths containsObject:defaultDerivationPath], @"The derivationPath is not in the account");
    _defaultDerivationPath = defaultDerivationPath;
}

-(void)setWallet:(DSWallet *)wallet {
    if (!_wallet) {
        _wallet = wallet;
        [self loadDerivationPaths];
        [self loadTransactions];
    }
}

- (void)loadDerivationPaths {
    for (DSDerivationPath * derivationPath in self.derivationPaths) {
        [derivationPath loadAddresses];
    }
    if (!self.isViewOnlyAccount) {
    if (self.bip44DerivationPath) {
        self.defaultDerivationPath = self.bip44DerivationPath;
    } else if (self.bip32DerivationPath) {
        self.defaultDerivationPath = self.bip32DerivationPath;
    } else {
        self.defaultDerivationPath = [self.derivationPaths objectAtIndex:0];
    }
    }
}

// MARK: - Combining Derivation Paths

-(NSArray *)registerAddressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal {
    NSMutableArray * mArray = [NSMutableArray array];
    for (DSDerivationPath * derivationPath in self.derivationPaths) {
        [mArray addObjectsFromArray:[derivationPath registerAddressesWithGapLimit:gapLimit internal:internal]];
    }
    return [mArray copy];
}

// all previously generated external addresses
-(NSArray *)externalAddresses {
    NSMutableSet * mSet = [NSMutableSet set];
    for (DSDerivationPath * derivationPath in self.derivationPaths) {
        [mSet addObjectsFromArray:[derivationPath allReceiveAddresses]];
    }
    return [mSet allObjects];
}

// all previously generated internal addresses
-(NSArray *)internalAddresses {
    NSMutableSet * mSet = [NSMutableSet set];
    for (DSDerivationPath * derivationPath in self.derivationPaths) {
        [mSet addObjectsFromArray:[derivationPath allChangeAddresses]];
    }
    return [mSet allObjects];
}

-(NSSet *)allAddresses {
    NSMutableSet * mSet = [NSMutableSet set];
    for (DSDerivationPath * derivationPath in self.derivationPaths) {
        [mSet addObjectsFromArray:[[derivationPath allAddresses] allObjects]];
    }
    return [mSet copy];
}

-(NSSet *)usedAddresses {
    NSMutableSet * mSet = [NSMutableSet set];
    for (DSDerivationPath * derivationPath in self.derivationPaths) {
        [mSet addObjectsFromArray:[[derivationPath usedAddresses] allObjects]];
    }
    return [mSet copy];
}

- (NSString *)receiveAddress
{
    return self.defaultDerivationPath.receiveAddress;
}

// returns the first unused internal address
- (NSString *)changeAddress {
    return self.defaultDerivationPath.changeAddress;
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
- (BOOL)containsAddress:(NSString *)address {
    for (DSDerivationPath * derivationPath in self.derivationPaths) {
        if ([derivationPath containsAddress:address]) return TRUE;
    }
    return FALSE;
}

// true if the address was previously used as an input or output in any wallet transaction
- (BOOL)addressIsUsed:(NSString *)address {
    for (DSDerivationPath * derivationPath in self.derivationPaths) {
        if ([derivationPath addressIsUsed:address]) return TRUE;
    }
    return FALSE;
}

// MARK: - Balance

- (void)updateBalance
{
    uint64_t balance = 0, prevBalance = 0, totalSent = 0, totalReceived = 0;
    NSMutableOrderedSet *utxos = [NSMutableOrderedSet orderedSet];
    NSMutableSet *spentOutputs = [NSMutableSet set], *invalidTx = [NSMutableSet set], *pendingTx = [NSMutableSet set];
    NSMutableArray *balanceHistory = [NSMutableArray array];
    uint32_t now = [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970;
    
    for (DSTransaction *tx in [self.transactions reverseObjectEnumerator]) {
        @autoreleasepool {
            NSMutableSet *spent = [NSMutableSet set];
            NSSet *inputs;
            uint32_t i = 0, n = 0;
            BOOL pending = NO;
            UInt256 h;
            
            for (NSValue *hash in tx.inputHashes) {
                n = [tx.inputIndexes[i++] unsignedIntValue];
                [hash getValue:&h];
                [spent addObject:dsutxo_obj(((DSUTXO) { h, n }))];
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
                if (tx.size > TX_MAX_SIZE) {
                    pending = YES; // check transaction size is under TX_MAX_SIZE
                }
                
                for (NSNumber *sequence in tx.inputSequences) {
                    if (sequence.unsignedIntValue < UINT32_MAX - 1) {
                        pending = YES; // check for replace-by-fee
                    }
                    if (sequence.unsignedIntValue < UINT32_MAX && tx.lockTime < TX_MAX_LOCK_HEIGHT &&
                        tx.lockTime > self.wallet.chain.bestBlockHeight + 1) {
                        pending = YES; // future lockTime
                    }
                    if (sequence.unsignedIntValue < UINT32_MAX && tx.lockTime >= TX_MAX_LOCK_HEIGHT &&
                        tx.lockTime > now) {
                        pending = YES; // future locktime
                    }
                }
                
                for (NSNumber *amount in tx.outputAmounts) { // check that no outputs are dust
                    if (amount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) {
                        pending = YES;
                    }
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
                for (DSDerivationPath * derivationPath in self.derivationPaths) {
                    if ([derivationPath containsAddress:address]) {
                        derivationPath.balance += [tx.outputAmounts[n] unsignedLongLongValue];
                        [utxos addObject:dsutxo_obj(((DSUTXO) { tx.txHash, n }))];
                        balance += [tx.outputAmounts[n] unsignedLongLongValue];
                    }
                }
                
                n++;
            }
            
            // transaction ordering is not guaranteed, so check the entire UTXO set against the entire spent output set
            [spent setSet:utxos.set];
            [spent intersectSet:spentOutputs];
            
            for (NSValue *output in spent) { // remove any spent outputs from UTXO set
                DSTransaction *transaction;
                DSUTXO o;
                
                [output getValue:&o];
                transaction = self.allTx[uint256_obj(o.hash)];
                [utxos removeObject:output];
                balance -= [transaction.outputAmounts[o.n] unsignedLongLongValue];
                for (DSDerivationPath * derivationPath in self.derivationPaths) {
                    if ([derivationPath containsAddress:transaction.outputAddresses[o.n]]) {
                        derivationPath.balance -= [transaction.outputAmounts[o.n] unsignedLongLongValue];
                        break;
                    }
                }
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
    [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletBalanceChangedNotification object:nil];
}

// MARK: - Transactions

// chain position of first tx output address that appears in chain
static NSUInteger transactionAddressIndex(DSTransaction *transaction, NSArray *addressChain) {
    for (NSString *address in transaction.outputAddresses) {
        NSUInteger i = [addressChain indexOfObject:address];
        
        if (i != NSNotFound) return i;
    }
    
    return NSNotFound;
}


// this sorts transactions by block height in descending order, and makes a best attempt at ordering transactions within
// each block, however correct transaction ordering cannot be relied upon for determining wallet balance or UTXO set
- (void)sortTransactions
{
    BOOL (^isAscending)(id, id);
    __block __weak BOOL (^_isAscending)(id, id) = isAscending = ^BOOL(DSTransaction *tx1, DSTransaction *tx2) {
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
        
        NSUInteger i = transactionAddressIndex(tx1, self.internalAddresses);
        NSUInteger j = transactionAddressIndex(tx2, (i == NSNotFound) ? self.externalAddresses : self.internalAddresses);
        
        if (i == NSNotFound && j != NSNotFound) i = transactionAddressIndex(tx1, self.externalAddresses);
        if (i == NSNotFound || j == NSNotFound || i == j) return NSOrderedSame;
        return (i > j) ? NSOrderedAscending : NSOrderedDescending;
    }];
}


// returns an unsigned transaction that sends the specified amount from the wallet to the given address
- (DSTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    NSMutableData *script = [NSMutableData data];
    
    [script appendScriptPubKeyForAddress:address forChain:self.wallet.chain];
    
    return [self transactionForAmounts:@[@(amount)] toOutputScripts:@[script] withFee:fee];
}

- (DSTransaction *)proposalCollateralTransactionWithData:(NSData*)data
{
    NSMutableData *script = [NSMutableData data];
    
    [script appendProposalInfo:data];
    
    return [self transactionForAmounts:@[@(PROPOSAL_COST)] toOutputScripts:@[script] withFee:TRUE];
}


// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (DSTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee {
    return [self transactionForAmounts:amounts toOutputScripts:scripts withFee:fee isInstant:FALSE toShapeshiftAddress:nil];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (DSTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee  isInstant:(BOOL)isInstant {
    return [self transactionForAmounts:amounts toOutputScripts:scripts withFee:fee isInstant:isInstant toShapeshiftAddress:nil];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (DSTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee isInstant:(BOOL)isInstant toShapeshiftAddress:(NSString*)shapeshiftAddress
{
    
    uint64_t amount = 0, balance = 0, feeAmount = 0;
    DSTransaction *transaction = [[DSTransaction alloc] initOnChain:self.wallet.chain], *tx;
    NSUInteger i = 0, cpfpSize = 0;
    DSUTXO o;
    
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
            if (self.balance < amount + [self.wallet.chain feeForTxSize:txSize + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]) {
                NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", self.balance,
                      amount + [self.wallet.chain feeForTxSize:txSize + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]);
                return nil;
            }
            
            uint64_t lastAmount = [amounts.lastObject unsignedLongLongValue];
            NSArray *newAmounts = [amounts subarrayWithRange:NSMakeRange(0, amounts.count - 1)],
            *newScripts = [scripts subarrayWithRange:NSMakeRange(0, scripts.count - 1)];
            
            if (lastAmount > amount + feeAmount + self.wallet.chain.minOutputAmount - balance) { // reduce final output amount
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
            feeAmount = [self.wallet.chain feeForTxSize:transaction.size + 34 + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]; // assume we will add a change output
            if (self.balance > amount) feeAmount += (self.balance - amount) % 100; // round off balance to 100 satoshi
        }
        
        if (balance == amount + feeAmount || balance >= amount + feeAmount + self.wallet.chain.minOutputAmount) break;
    }
    
    transaction.isInstant = isInstant;
    
    if (balance < amount + feeAmount) { // insufficient funds
        NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + feeAmount);
        return nil;
    }
    
    if (shapeshiftAddress) {
        [transaction addOutputShapeshiftAddress:shapeshiftAddress];
    }
    
    if (balance - (amount + feeAmount) >= self.wallet.chain.minOutputAmount) {
        [transaction addOutputAddress:self.changeAddress amount:balance - (amount + feeAmount)];
        [transaction shuffleOutputOrder];
    }
    
    return transaction;
    
    
}

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (void)signTransaction:(DSTransaction *)transaction withPrompt:(NSString *)authprompt completion:(TransactionValidityCompletionBlock)completion;
{
    if (_isViewOnlyAccount) return;
    int64_t amount = [self amountSentByTransaction:transaction] - [self amountReceivedFromTransaction:transaction];
    NSMutableOrderedSet *externalIndexes = [NSMutableOrderedSet orderedSet],
    *internalIndexes = [NSMutableOrderedSet orderedSet];
    
    for (NSString *addr in transaction.inputAddresses) {
        NSInteger index = [self.defaultDerivationPath.allChangeAddresses indexOfObject:addr];
        if (index != NSNotFound) {
            [internalIndexes addObject:@(index)];
            continue;
        }
        index = [self.defaultDerivationPath.allReceiveAddresses indexOfObject:addr];
        if (index != NSNotFound) {
            [externalIndexes addObject:@(index)];
            continue;
        }
    }
    
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        self.wallet.seedRequestBlock(authprompt, (amount > 0) ? amount : 0,^void (NSData * _Nullable seed) {
            if (! seed) {
                if (completion) completion(YES);
            } else {
                NSMutableArray *privkeys = [NSMutableArray array];
                [privkeys addObjectsFromArray:[self.defaultDerivationPath privateKeys:externalIndexes.array internal:NO fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.defaultDerivationPath privateKeys:internalIndexes.array internal:YES fromSeed:seed]];
                
                BOOL signedSuccessfully = [transaction signWithPrivateKeys:privkeys];
                if (completion) completion(signedSuccessfully);
            }
        });
    }
}

// true if the given transaction is associated with the account (even if it hasn't been registered), false otherwise
- (BOOL)containsTransaction:(DSTransaction *)transaction
{
    if ([[NSSet setWithArray:transaction.outputAddresses] intersectsSet:self.allAddresses]) return YES;
    
    NSInteger i = 0;
    
    for (NSValue *txHash in transaction.inputHashes) {
        DSTransaction *tx = self.allTx[txHash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) return YES;
    }
    
    return NO;
}

// records the transaction in the account, or returns false if it isn't associated with the wallet
- (BOOL)registerTransaction:(DSTransaction *)transaction
{
    UInt256 txHash = transaction.txHash;
    NSValue *hash = uint256_obj(txHash);
    
    if (uint256_is_zero(txHash)) return NO;
    
    if (![self containsTransaction:transaction]) {
        if (transaction.blockHeight == TX_UNCONFIRMED) self.allTx[hash] = transaction;
        return NO;
    }
    
    if (self.allTx[hash] != nil) return YES;
    
    //TODO: handle tx replacement with input sequence numbers (now replacements appear invalid until confirmation)
    NSLog(@"[DSWallet] received unseen transaction %@", transaction);
    
    self.allTx[hash] = transaction;
    [self.transactions insertObject:transaction atIndex:0];
    for (NSString * address in transaction.inputAddresses) {
        for (DSDerivationPath * derivationPath in self.derivationPaths) {
            if ([derivationPath containsAddress:address]) {
                [derivationPath registerTransactionAddress:address];
            }
        }
    }
    for (NSString * address in transaction.outputAddresses) {
        for (DSDerivationPath * derivationPath in self.derivationPaths) {
            if ([derivationPath containsAddress:address]) {
                [derivationPath registerTransactionAddress:address];
            }
        }
    }
    [self updateBalance];
    
    // when a wallet address is used in a transaction, generate a new address to replace it
    [self registerAddressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO];
    [self registerAddressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];
    
    [self.moc performBlock:^{ // add the transaction to core data
        if ([DSTransactionEntity countObjectsMatching:@"txHash == %@",
             [NSData dataWithBytes:&txHash length:sizeof(txHash)]] == 0) {
            [[DSTransactionEntity managedObject] setAttributesFromTx:transaction];
            [DSTransactionEntity saveContext];
        }
    }];
    
    return YES;
}

// removes a transaction from the wallet along with any transactions that depend on its outputs
- (void)removeTransaction:(UInt256)txHash
{
    DSTransaction *transaction = self.allTx[uint256_obj(txHash)];
    NSMutableSet *hashes = [NSMutableSet set];
    
    for (DSTransaction *tx in self.transactions) { // remove dependent transactions
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
        [DSTransactionEntity deleteObjects:[DSTransactionEntity objectsMatching:@"txHash == %@",
                                            [NSData dataWithBytes:&txHash length:sizeof(txHash)]]];
    }];
}

// returns the transaction with the given hash if it's been registered in the wallet (might also return non-registered)
- (DSTransaction *)transactionForHash:(UInt256)txHash
{
    return self.allTx[uint256_obj(txHash)];
}

// true if no previous wallet transactions spend any of the given transaction's inputs, and no input tx is invalid
- (BOOL)transactionIsValid:(DSTransaction *)transaction
{
    //TODO: XXX attempted double spends should cause conflicted tx to remain unverified until they're confirmed
    //TODO: XXX verify signatures for spends
    if (transaction.blockHeight != TX_UNCONFIRMED) return YES;
    
    if (self.allTx[uint256_obj(transaction.txHash)] != nil) {
        return ([self.invalidTx containsObject:uint256_obj(transaction.txHash)]) ? NO : YES;
    }
    
    uint32_t i = 0;
    
    for (NSValue *hash in transaction.inputHashes) {
        DSTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        UInt256 h;
        
        [hash getValue:&h];
        if ((tx && ! [self transactionIsValid:tx]) ||
            [self.spentOutputs containsObject:dsutxo_obj(((DSUTXO) { h, n }))]) return NO;
    }
    
    return YES;
}

// true if transaction cannot be immediately spent (i.e. if it or an input tx can be replaced-by-fee)
- (BOOL)transactionIsPending:(DSTransaction *)transaction
{
    if (transaction.blockHeight != TX_UNCONFIRMED) return NO; // confirmed transactions are not pending
    if (transaction.size > TX_MAX_SIZE) return YES; // check transaction size is under TX_MAX_SIZE
    
    // check for future lockTime or replace-by-fee: https://github.com/bitcoin/bips/blob/master/bip-0125.mediawiki
    for (NSNumber *sequence in transaction.inputSequences) {
        if (sequence.unsignedIntValue < UINT32_MAX - 1) return YES;
        if (sequence.unsignedIntValue < UINT32_MAX && transaction.lockTime < TX_MAX_LOCK_HEIGHT &&
            transaction.lockTime > self.wallet.chain.bestBlockHeight + 1) return YES;
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
- (BOOL)transactionIsVerified:(DSTransaction *)transaction
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

// returns the amount received by the wallet from the transaction (total outputs to change and/or receive addresses)
- (uint64_t)amountReceivedFromTransaction:(DSTransaction *)transaction
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
- (uint64_t)amountSentByTransaction:(DSTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;
    
    for (NSValue *hash in transaction.inputHashes) {
        DSTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) {
            amount += [tx.outputAmounts[n] unsignedLongLongValue];
        }
    }
    
    return amount;
}

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction:(DSTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;
    
    for (NSValue *hash in transaction.inputHashes) {
        DSTransaction *tx = self.allTx[hash];
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
- (uint64_t)balanceAfterTransaction:(DSTransaction *)transaction
{
    NSUInteger i = [self.transactions indexOfObject:transaction];
    
    return (i < self.balanceHistory.count) ? [self.balanceHistory[i] unsignedLongLongValue] : self.balance;
}

// Returns the block height after which the transaction is likely to be processed without including a fee. This is based
// on the default satoshi client settings, but on the real network it's way off. In testing, a 0.01btc transaction that
// was expected to take an additional 90 days worth of blocks to confirm was confirmed in under an hour by Eligius pool.
- (uint32_t)blockHeightUntilFree:(DSTransaction *)transaction
{
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger i = 0;
    
    for (NSValue *hash in transaction.inputHashes) { // get the amounts and block heights of all the transaction inputs
        DSTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
        if (n >= tx.outputAmounts.count) break;
        [amounts addObject:tx.outputAmounts[n]];
        [heights addObject:@(tx.blockHeight)];
    };
    
    return [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
}

- (uint64_t)maxOutputAmountUsingInstantSend:(BOOL)instantSend
{
    return [self maxOutputAmountWithConfirmationCount:0 usingInstantSend:instantSend];
}

- (uint32_t)blockHeight
{
    static uint32_t height = 0;
    uint32_t h = self.wallet.chain.lastBlockHeight;
    
    if (h > height) height = h;
    return height;
}

- (uint64_t)maxOutputAmountWithConfirmationCount:(uint64_t)confirmationCount usingInstantSend:(BOOL)instantSend
{
    DSUTXO o;
    DSTransaction *tx;
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
    fee = [self.wallet.chain feeForTxSize:txSize + cpfpSize isInstant:instantSend inputCount:inputCount];
    return (amount > fee) ? amount - fee : 0;
}

// set the block heights and timestamps for the given transactions, use a height of TX_UNCONFIRMED and timestamp of 0 to
// indicate a transaction and it's dependents should remain marked as unverified (not 0-conf safe)
- (NSArray *)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes
{
    NSMutableArray *hashes = [NSMutableArray array], *updated = [NSMutableArray array];
    BOOL needsUpdate = NO;
    
    for (NSValue *hash in txHashes) {
        DSTransaction *tx = self.allTx[hash];
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
                
                for (DSTransactionEntity *e in [DSTransactionEntity objectsMatching:@"txHash in %@", hashes]) {
                    e.blockHeight = height;
                    e.timestamp = timestamp;
                    [entities addObject:e];
                }
                
                if (height != TX_UNCONFIRMED) {
                    // BUG: XXX saving the tx.blockHeight and the block it's contained in both need to happen together
                    // as an atomic db operation. If the tx.blockHeight is saved but the block isn't when the app exits,
                    // then a re-org that happens afterward can potentially result in an invalid tx showing as confirmed
                    
                    for (NSManagedObject *e in entities) {
                        [self.moc refreshObject:e mergeChanges:NO];
                    }
                }
            }
        }];
    }
    
    return updated;
}

- (void)wipeBlockchainInfo {
    [self.transactions removeAllObjects];
    [self.allTx removeAllObjects];
    [self updateBalance];
}

@end
