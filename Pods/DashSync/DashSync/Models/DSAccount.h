//
//  DSWallet.h
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

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "DSTransaction.h"
#import "NSData+Bitcoin.h"
#import "DSDerivationPath.h"

@class DSDerivationPath,DSWallet;

@interface DSAccount : NSObject

// BIP 43 derivation paths
@property (nonatomic, readonly) NSArray<DSDerivationPath *> * derivationPaths;

@property (nonatomic, strong) DSDerivationPath * defaultDerivationPath;

@property (nonatomic, readonly) DSDerivationPath * bip44DerivationPath;

@property (nonatomic, readonly) DSDerivationPath * bip32DerivationPath;

@property (nonatomic, weak) DSWallet * wallet;

@property (nonatomic, readonly) uint32_t accountNumber;

// current wallet balance excluding transactions known to be invalid
@property (nonatomic, readonly) uint64_t balance;

// NSValue objects containing UTXO structs
@property (nonatomic, readonly) NSArray * _Nonnull unspentOutputs;

// latest 100 transactions sorted by date, most recent first
@property (nonatomic, readonly) NSArray * _Nonnull recentTransactions;

// all wallet transactions sorted by date, most recent first
@property (nonatomic, readonly) NSArray * _Nonnull allTransactions;

// returns the first unused external address
@property (nonatomic, readonly) NSString * _Nullable receiveAddress;

// returns the first unused internal address
@property (nonatomic, readonly) NSString * _Nullable changeAddress;

// all previously generated external addresses
@property (nonatomic, readonly) NSArray * _Nonnull externalAddresses;

// all previously generated internal addresses
@property (nonatomic, readonly) NSArray * _Nonnull internalAddresses;

-(NSArray * _Nullable)registerAddressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal;

+(DSAccount*)accountWithDerivationPaths:(NSArray<DSDerivationPath *> *)derivationPaths;

-(instancetype)initWithDerivationPaths:(NSArray<DSDerivationPath *> *)derivationPaths;

-(instancetype)initAsViewOnlyWithDerivationPaths:(NSArray<DSDerivationPath *> *)derivationPaths;

-(void)removeDerivationPath:(DSDerivationPath*)derivationPath;

-(void)addDerivationPath:(DSDerivationPath*)derivationPath;

-(void)addDerivationPathsFromArray:(NSArray<DSDerivationPath *> *)derivationPaths;

// largest amount that can be sent from the account after fees
- (uint64_t)maxOutputAmountUsingInstantSend:(BOOL)instantSend;

- (uint64_t)maxOutputAmountWithConfirmationCount:(uint64_t)confirmationCount usingInstantSend:(BOOL)instantSend;

// true if the address is controlled by the wallet
- (BOOL)containsAddress:(NSString *)address;

// true if the address was previously used as an input or output in any wallet transaction
- (BOOL)addressIsUsed:(NSString *)address;

// returns an unsigned transaction that sends the specified amount from the wallet to the given address
- (DSTransaction * _Nullable)transactionFor:(uint64_t)amount to:(NSString * _Nonnull)address withFee:(BOOL)fee;

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (DSTransaction * _Nullable)transactionForAmounts:(NSArray * _Nonnull)amounts
                                   toOutputScripts:(NSArray * _Nonnull)scripts withFee:(BOOL)fee;

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (DSTransaction * _Nullable)transactionForAmounts:(NSArray * _Nonnull)amounts toOutputScripts:(NSArray * _Nonnull)scripts withFee:(BOOL)fee  isInstant:(BOOL)isInstant;

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (DSTransaction * _Nullable)transactionForAmounts:(NSArray * _Nonnull)amounts toOutputScripts:(NSArray * _Nonnull)scripts withFee:(BOOL)fee isInstant:(BOOL)isInstant toShapeshiftAddress:(NSString* _Nullable)shapeshiftAddress;

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (void)signTransaction:(DSTransaction * _Nonnull)transaction withPrompt:(NSString * _Nonnull)authprompt completion:(_Nonnull TransactionValidityCompletionBlock)completion;

// true if the given transaction is associated with the account (even if it hasn't been registered), false otherwise
- (BOOL)containsTransaction:(DSTransaction * _Nonnull)transaction;

// adds a transaction to the account, or returns false if it isn't associated with the account
- (BOOL)registerTransaction:(DSTransaction * _Nonnull)transaction;

// removes a transaction from the account along with any transactions that depend on its outputs
- (void)removeTransaction:(UInt256)txHash;

// returns the transaction with the given hash if it's been registered in the account (might also return non-registered)
- (DSTransaction * _Nullable)transactionForHash:(UInt256)txHash;

// true if no previous account transaction spends any of the given transaction's inputs, and no inputs are invalid
- (BOOL)transactionIsValid:(DSTransaction * _Nonnull)transaction;

// true if transaction cannot be immediately spent (i.e. if it or an input tx can be replaced-by-fee, via BIP125)
- (BOOL)transactionIsPending:(DSTransaction * _Nonnull)transaction;

// true if tx is considered 0-conf safe (valid and not pending, timestamp is greater than 0, and no unverified inputs)
- (BOOL)transactionIsVerified:(DSTransaction * _Nonnull)transaction;

// returns the amount received by the account from the transaction (total outputs to change and/or receive addresses)
- (uint64_t)amountReceivedFromTransaction:(DSTransaction * _Nonnull)transaction;

// retuns the amount sent from the account by the trasaction (total account outputs consumed, change and fee included)
- (uint64_t)amountSentByTransaction:(DSTransaction * _Nonnull)transaction;

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction:(DSTransaction * _Nonnull)transaction;

// historical wallet balance after the given transaction, or current balance if transaction is not registered in wallet
- (uint64_t)balanceAfterTransaction:(DSTransaction * _Nonnull)transaction;

// returns the block height after which the transaction is likely to be processed without including a fee
- (uint32_t)blockHeightUntilFree:(DSTransaction * _Nonnull)transaction;

- (NSArray *)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes;

// This loads the derivation paths addresses once the account is set to a wallet
- (void)loadDerivationPaths;

// This loads transactions once the account is set to a wallet
- (void)loadTransactions;

//This removes all transactions from the account
- (void)wipeBlockchainInfo;

//This creates a proposal transaction
- (DSTransaction *)proposalCollateralTransactionWithData:(NSData*)data;

@end
