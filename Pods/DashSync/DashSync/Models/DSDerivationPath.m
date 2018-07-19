//
//  DSDerivationPath.m
//  DashSync
//
//  Created by Sam Westrich on 5/20/18.
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
#import "DSKeySequence.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Dash.h"
#import "NSManagedObject+Sugar.h"
#import "DSWalletManager.h"
#import "NSString+Bitcoin.h"
#import "NSString+Dash.h"
#import "NSData+Bitcoin.h"


// BIP32 is a scheme for deriving chains of addresses from a seed value
// https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki

// Private parent key -> private child key
//
// CKDpriv((kpar, cpar), i) -> (ki, ci) computes a child extended private key from the parent extended private key:
//
// - Check whether i >= 2^31 (whether the child is a hardened key).
//     - If so (hardened child): let I = HMAC-SHA512(Key = cpar, Data = 0x00 || ser256(kpar) || ser32(i)).
//       (Note: The 0x00 pads the private key to make it 33 bytes long.)
//     - If not (normal child): let I = HMAC-SHA512(Key = cpar, Data = serP(point(kpar)) || ser32(i)).
// - Split I into two 32-byte sequences, IL and IR.
// - The returned child key ki is parse256(IL) + kpar (mod n).
// - The returned chain code ci is IR.
// - In case parse256(IL) >= n or ki = 0, the resulting key is invalid, and one should proceed with the next value for i
//   (Note: this has probability lower than 1 in 2^127.)
//
static void CKDpriv(UInt256 *k, UInt256 *c, uint32_t i)
{
    uint8_t buf[sizeof(DSECPoint) + sizeof(i)];
    UInt512 I;
    
    if (i & BIP32_HARD) {
        buf[0] = 0;
        *(UInt256 *)&buf[1] = *k;
    }
    else DSSecp256k1PointGen((DSECPoint *)buf, k);
    
    *(uint32_t *)&buf[sizeof(DSECPoint)] = CFSwapInt32HostToBig(i);
    
    HMAC(&I, SHA512, sizeof(UInt512), c, sizeof(*c), buf, sizeof(buf)); // I = HMAC-SHA512(c, k|P(k) || i)
    
    DSSecp256k1ModAdd(k, (UInt256 *)&I); // k = IL + k (mod n)
    *c = *(UInt256 *)&I.u8[sizeof(UInt256)]; // c = IR
    
    memset(buf, 0, sizeof(buf));
    memset(&I, 0, sizeof(I));
}

// Public parent key -> public child key
//
// CKDpub((Kpar, cpar), i) -> (Ki, ci) computes a child extended public key from the parent extended public key.
// It is only defined for non-hardened child keys.
//
// - Check whether i >= 2^31 (whether the child is a hardened key).
//     - If so (hardened child): return failure
//     - If not (normal child): let I = HMAC-SHA512(Key = cpar, Data = serP(Kpar) || ser32(i)).
// - Split I into two 32-byte sequences, IL and IR.
// - The returned child key Ki is point(parse256(IL)) + Kpar.
// - The returned chain code ci is IR.
// - In case parse256(IL) >= n or Ki is the point at infinity, the resulting key is invalid, and one should proceed with
//   the next value for i.
//
static void CKDpub(DSECPoint *K, UInt256 *c, uint32_t i)
{
    if (i & BIP32_HARD) return; // can't derive private child key from public parent key
    
    uint8_t buf[sizeof(*K) + sizeof(i)];
    UInt512 I;
    
    *(DSECPoint *)buf = *K;
    *(uint32_t *)&buf[sizeof(*K)] = CFSwapInt32HostToBig(i);
    
    HMAC(&I, SHA512, sizeof(UInt512), c, sizeof(*c), buf, sizeof(buf)); // I = HMAC-SHA512(c, P(K) || i)
    
    *c = *(UInt256 *)&I.u8[sizeof(UInt256)]; // c = IR
    DSSecp256k1PointAdd(K, (UInt256 *)&I); // K = P(IL) + K
    
    memset(buf, 0, sizeof(buf));
    memset(&I, 0, sizeof(I));
}

#define DERIVATION_PATH_EXTENDED_PUBLIC_KEY_WALLET_BASED_LOCATION @"DP_EPK_WBL"
#define DERIVATION_PATH_EXTENDED_PUBLIC_KEY_STANDALONE_BASED_LOCATION @"DP_EPK_SBL"
#define DERIVATION_PATH_STANDALONE_INFO_DICTIONARY_LOCATION @"DP_SIDL"
#define DERIVATION_PATH_STANDALONE_INFO_CHILD @"DP_SI_CHILD"
#define DERIVATION_PATH_STANDALONE_INFO_DEPTH @"DP_SI_DEPTH"

@interface DSDerivationPath()

@property (nonatomic, copy) NSString * walletBasedExtendedPublicKeyLocationString;
@property (nonatomic, strong) NSMutableArray *internalAddresses, *externalAddresses;
@property (nonatomic, strong) NSMutableSet *allAddresses, *usedAddresses;
@property (nonatomic, weak) DSAccount * account;
@property (nonatomic, strong) NSManagedObjectContext * moc;
@property (nonatomic, strong) NSData * extendedPublicKey;//master public key used to generate wallet addresses
@property (nonatomic, assign) BOOL addressesLoaded;
@property (nonatomic, strong) DSChain * chain;
@property (nonatomic, strong) NSNumber * depth;
@property (nonatomic, assign) NSNumber * child;
@property (nonatomic, strong) NSString * standaloneExtendedPublicKeyUniqueID;
@property (nonatomic, strong) NSString * stringRepresentation;

@end

@implementation DSDerivationPath


// MARK: - Account initialization

+ (instancetype _Nonnull)bip32DerivationPathOnChain:(DSChain*)chain forAccountNumber:(uint32_t)accountNumber {
    NSUInteger indexes[] = {accountNumber};
    return [self derivationPathWithIndexes:indexes length:1 type:DSDerivationPathFundsType_Clear reference:DSDerivationPathReference_BIP32 onChain:chain];
}
+ (instancetype _Nonnull)bip44DerivationPathOnChain:(DSChain*)chain forAccountNumber:(uint32_t)accountNumber {
    if (chain.chainType == DSChainType_MainNet) {
        NSUInteger indexes[] = {44,5,accountNumber};
        return [self derivationPathWithIndexes:indexes length:3 type:DSDerivationPathFundsType_Clear reference:DSDerivationPathReference_BIP44 onChain:chain];
    } else {
        NSUInteger indexes[] = {44,1,accountNumber};
        return [self derivationPathWithIndexes:indexes length:3 type:DSDerivationPathFundsType_Clear reference:DSDerivationPathReference_BIP44 onChain:chain];
    }
}

+ (instancetype _Nullable)derivationPathWithIndexes:(NSUInteger *)indexes length:(NSUInteger)length
                                               type:(DSDerivationPathFundsType)type reference:(DSDerivationPathReference)reference onChain:(DSChain*)chain {
    return [[self alloc] initWithIndexes:indexes length:length type:type reference:reference onChain:chain];
}

+ (instancetype _Nullable)derivationPathWithSerializedExtendedPrivateKey:(NSString*)serializedExtendedPrivateKey fundsType:(DSDerivationPathFundsType)fundsType onChain:(DSChain*)chain {
    NSData * extendedPrivateKey = [self deserializedExtendedPrivateKey:serializedExtendedPrivateKey onChain:chain];
    NSUInteger indexes[] = {};
    DSDerivationPath * derivationPath = [[self alloc] initWithIndexes:indexes length:0 type:fundsType reference:DSDerivationPathReference_Unknown onChain:chain];
    derivationPath.extendedPublicKey = [DSKey keyWithSecret:*(UInt256*)extendedPrivateKey.bytes compressed:YES].publicKey;
    [derivationPath standaloneSaveExtendedPublicKeyToKeyChain];
    return derivationPath;
}

+ (instancetype _Nullable)derivationPathWithSerializedExtendedPublicKey:(NSString*)serializedExtendedPublicKey onChain:(DSChain*)chain {
    uint8_t depth = 0;
    uint32_t child = 0;
    NSData * extendedPublicKey = [self deserializedExtendedPublicKey:serializedExtendedPublicKey onChain:chain rDepth:&depth rChild:&child];
    NSUInteger indexes[] = {};
    DSDerivationPath * derivationPath = [[self alloc] initWithIndexes:indexes length:0 type:DSDerivationPathFundsType_ViewOnly reference:DSDerivationPathReference_Unknown onChain:chain];
    derivationPath.extendedPublicKey = extendedPublicKey;
    derivationPath.depth = @(depth);
    derivationPath.child = @(child);
    [derivationPath standaloneSaveExtendedPublicKeyToKeyChain];
    [derivationPath loadAddresses];
    return derivationPath;
}

- (instancetype _Nullable)initWithExtendedPublicKeyIdentifier:(NSString* _Nonnull)extendedPublicKeyIdentifier onChain:(DSChain* _Nonnull)chain {
    NSUInteger indexes[] = {};
    if (!(self = [self initWithIndexes:indexes length:0 type:DSDerivationPathFundsType_ViewOnly reference:DSDerivationPathReference_Unknown onChain:chain])) return nil;
    NSError * error = nil;
    _walletBasedExtendedPublicKeyLocationString = extendedPublicKeyIdentifier;
    _extendedPublicKey = getKeychainData([DSDerivationPath standaloneExtendedPublicKeyLocationStringForUniqueID:extendedPublicKeyIdentifier], &error);
    if (error) return nil;
    NSDictionary * infoDictionary = getKeychainDict([DSDerivationPath standaloneInfoDictionaryLocationStringForUniqueID:extendedPublicKeyIdentifier], &error);
    if (error) return nil;
    _depth = infoDictionary[DERIVATION_PATH_STANDALONE_INFO_DEPTH];
    _child = infoDictionary[DERIVATION_PATH_STANDALONE_INFO_CHILD];

    [self loadAddresses];
    return self;
}

- (instancetype)initWithIndexes:(NSUInteger *)indexes length:(NSUInteger)length
                           type:(DSDerivationPathFundsType)type reference:(DSDerivationPathReference)reference onChain:(DSChain*)chain {
    if (length) {
        if (! (self = [super initWithIndexes:indexes length:length])) return nil;
    } else {
        if (! (self = [super init])) return nil;
    }
    
    _chain = chain;
    _reference = reference;
    _type = type;
    _derivationPathIsKnown = YES;
    _addressesLoaded = FALSE;
    self.allAddresses = [NSMutableSet set];
    self.usedAddresses = [NSMutableSet set];
    self.internalAddresses = [NSMutableArray array];
    self.externalAddresses = [NSMutableArray array];
    self.moc = [NSManagedObject context];
    
    return self;
}

-(void)loadAddresses {
    if (!_addressesLoaded) {
    [self.moc performBlockAndWait:^{
        [DSAddressEntity setContext:self.moc];
        [DSTransactionEntity setContext:self.moc];
        DSDerivationPathEntity * derivationPathEntity = [DSDerivationPathEntity derivationPathEntityMatchingDerivationPath:self];
        self->_syncBlockHeight = derivationPathEntity.syncBlockHeight;
        for (DSAddressEntity *e in derivationPathEntity.addresses) {
            @autoreleasepool {
                NSMutableArray *a = (e.internal) ? self.internalAddresses : self.externalAddresses;
                
                while (e.index >= a.count) [a addObject:[NSNull null]];
                a[e.index] = e.address;
                [self->_allAddresses addObject:e.address];
                if ([e.usedInInputs count] || [e.usedInOutputs count]) {
                    [self->_usedAddresses addObject:e.address];
                }
            }
        }
    }];
        _addressesLoaded = TRUE;
        [self registerAddressesWithGapLimit:100 internal:YES];
        [self registerAddressesWithGapLimit:100 internal:NO];
        
    }
}

- (void)setAccount:(DSAccount *)account {
    if (!_account) {
        NSAssert(account.accountNumber == [self accountNumber], @"account number doesn't match derivation path ending");
        _account = account;
        //when we set the account load addresses
        
    }
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

-(NSNumber*)depth {
    if (_depth) return _depth;
    else return @(self.length);
}

-(DSChain*)chain {
    if (_chain) return _chain;
    return self.chain;
}

-(NSUInteger)accountNumber {
    return [self indexAtPosition:[self length] - 1];
}

-(NSString*)stringRepresentation {
    if (_stringRepresentation) return _stringRepresentation;
    NSMutableString * mutableString = [NSMutableString stringWithFormat:@"m"];
    if (self.length) {
    for (NSInteger i = 0;i<self.length;i++) {
        [mutableString appendFormat:@"/%lu'",(unsigned long)[self indexAtPosition:i]];
    }
    } else if ([self.depth integerValue]) {
        for (NSInteger i = 0;i<[self.depth integerValue] - 1;i++) {
            [mutableString appendFormat:@"/?'"];
        }
        if (self.child) {
            if ([self.child unsignedIntValue] & BIP32_HARD) {
                [mutableString appendFormat:@"/%lu'",[self.child unsignedIntegerValue] - BIP32_HARD];
            } else {
                [mutableString appendFormat:@"/%lu",[self.child unsignedIntegerValue]];
            }
        } else {
            [mutableString appendFormat:@"/?'"];
        }
        
    }
    _stringRepresentation = [mutableString copy];
    return _stringRepresentation;
}

-(NSData*)extendedPublicKey {
    if (!_extendedPublicKey) {
        if (self.account.wallet) {
            _extendedPublicKey = getKeychainData([self walletBasedExtendedPublicKeyLocationString], nil);
        }
    }
    NSAssert(_extendedPublicKey, @"extended public key not set");
    return _extendedPublicKey;
}

-(void)standaloneSaveExtendedPublicKeyToKeyChain {
    if (!_extendedPublicKey) return;
    setKeychainData(_extendedPublicKey, [self standaloneExtendedPublicKeyLocationString], NO);
    setKeychainDict(@{DERIVATION_PATH_STANDALONE_INFO_CHILD:self.child,DERIVATION_PATH_STANDALONE_INFO_DEPTH:self.depth}, [self standaloneInfoDictionaryLocationString], NO);
    [self.moc performBlockAndWait:^{
        [DSDerivationPathEntity setContext:self.moc];
        [DSDerivationPathEntity derivationPathEntityMatchingDerivationPath:self];
    }];
}

// Wallets are composed of chains of addresses. Each chain is traversed until a gap of a certain number of addresses is
// found that haven't been used in any transactions. This method returns an array of <gapLimit> unused addresses
// following the last used address in the chain. The internal chain is used for change addresses and the external chain
// for receive addresses.
- (NSArray *)registerAddressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    NSAssert(_addressesLoaded, @"addresses must be loaded before calling this function");
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
            NSData *pubKey = [self generatePublicKeyAtIndex:n internal:internal];
            NSString *addr = [[DSKey keyWithPublicKey:pubKey] addressForChain:self.chain];
            
            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }
            
            [self.moc performBlock:^{ // store new address in core data
                [DSDerivationPathEntity setContext:self.moc];
                DSDerivationPathEntity * derivationPathEntity = [DSDerivationPathEntity derivationPathEntityMatchingDerivationPath:self];
                DSAddressEntity *e = [DSAddressEntity managedObject];
                e.derivationPath = derivationPathEntity;
                e.address = addr;
                e.index = n;
                e.internal = internal;
                e.standalone = NO;
            }];
            
            [_allAddresses addObject:addr];
            [(internal) ? self.internalAddresses : self.externalAddresses addObject:addr];
            [a addObject:addr];
            n++;
        }
        
        return a;
    }
}

- (NSArray *)addressesForExportWithInternalRange:(NSRange)exportInternalRange externalCount:(NSRange)exportExternalRange
{
    NSMutableArray * addresses = [NSMutableArray array];
    for (NSUInteger i = exportInternalRange.location;i<exportInternalRange.length + exportInternalRange.location;i++) {
            NSData *pubKey = [self generatePublicKeyAtIndex:(uint32_t)i internal:YES];
            NSString *addr = [[DSKey keyWithPublicKey:pubKey] addressForChain:self.chain];
        [addresses addObject:addr];
    }
    
    for (NSUInteger i = exportExternalRange.location;i<exportExternalRange.location + exportExternalRange.length;i++) {
        NSData *pubKey = [self generatePublicKeyAtIndex:(uint32_t)i internal:NO];
        NSString *addr = [[DSKey keyWithPublicKey:pubKey] addressForChain:self.chain];
        [addresses addObject:addr];
    }
    
    return [addresses copy];
}

// MARK: - Identifiers

//Derivation paths can be stored based on the wallet and derivation or based solely on the public key


-(NSString *)standaloneExtendedPublicKeyUniqueID {
    if (!_standaloneExtendedPublicKeyUniqueID) _standaloneExtendedPublicKeyUniqueID = [NSData dataWithUInt256:[[self extendedPublicKey] SHA256]].shortHexString;
    return _standaloneExtendedPublicKeyUniqueID;
}

+(NSString*)standaloneExtendedPublicKeyLocationStringForUniqueID:(NSString*)uniqueID {
    return [NSString stringWithFormat:@"%@_%@",DERIVATION_PATH_EXTENDED_PUBLIC_KEY_STANDALONE_BASED_LOCATION,uniqueID];
}

-(NSString*)standaloneExtendedPublicKeyLocationString {
    return [DSDerivationPath standaloneExtendedPublicKeyLocationStringForUniqueID:self.standaloneExtendedPublicKeyUniqueID];
}

+(NSString*)standaloneInfoDictionaryLocationStringForUniqueID:(NSString*)uniqueID {
    return [NSString stringWithFormat:@"%@_%@",DERIVATION_PATH_STANDALONE_INFO_DICTIONARY_LOCATION,uniqueID];
}

-(NSString*)standaloneInfoDictionaryLocationString {
    return [DSDerivationPath standaloneInfoDictionaryLocationStringForUniqueID:self.standaloneExtendedPublicKeyUniqueID];
}

+(NSString*)walletBasedExtendedPublicKeyLocationStringForUniqueID:(NSString*)uniqueID {
    return [NSString stringWithFormat:@"%@_%@",DERIVATION_PATH_EXTENDED_PUBLIC_KEY_WALLET_BASED_LOCATION,uniqueID];
}

-(NSString*)walletBasedExtendedPublicKeyLocationStringForWalletUniqueID:(NSString*)uniqueID {
    NSMutableString * mutableString = [NSMutableString string];
    for (NSInteger i = 0;i<self.length;i++) {
        [mutableString appendFormat:@"_%lu",(unsigned long)[self indexAtPosition:i]];
    }
    return [NSString stringWithFormat:@"%@%@",[DSDerivationPath walletBasedExtendedPublicKeyLocationStringForUniqueID:uniqueID],mutableString];
}

-(NSString*)walletBasedExtendedPublicKeyLocationString {
    if (_walletBasedExtendedPublicKeyLocationString) return _walletBasedExtendedPublicKeyLocationString;
    _walletBasedExtendedPublicKeyLocationString = [self walletBasedExtendedPublicKeyLocationStringForWalletUniqueID:self.account.wallet.uniqueID];
    return _walletBasedExtendedPublicKeyLocationString;
}


// MARK: - Derivation Path Info

// returns the first unused external address
- (NSString *)receiveAddress
{
    //TODO: limit to 10,000 total addresses and utxos for practical usability with bloom filters
    NSString *addr = [self registerAddressesWithGapLimit:1 internal:NO].lastObject;
    return (addr) ? addr : self.externalAddresses.lastObject;
}

// returns the first unused internal address
- (NSString *)changeAddress
{
    //TODO: limit to 10,000 total addresses and utxos for practical usability with bloom filters
    return [self registerAddressesWithGapLimit:1 internal:YES].lastObject;
}

// all previously generated external addresses
- (NSArray *)allReceiveAddresses
{
    return [self.externalAddresses copy];
}

// all previously generated external addresses
- (NSArray *)allChangeAddresses
{
    return [self.internalAddresses copy];
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

- (void)registerTransactionAddress:(NSString * _Nonnull)address {
    [_usedAddresses addObject:address];
}

-(BOOL)isDerivationPathEqual:(id)object {
    return [super isEqual:object];
}

-(BOOL)isEqual:(id)object {
    return [self.standaloneExtendedPublicKeyUniqueID isEqualToString:((DSDerivationPath*)object).standaloneExtendedPublicKeyUniqueID];
}

-(NSUInteger)hash {
    return [self.standaloneExtendedPublicKeyUniqueID hash];
}

// MARK: - authentication key

//this is for upgrade purposes only
- (NSData *)deprecatedIncorrectExtendedPublicKeyFromSeed:(NSData *)seed
{
    if (! seed) return nil;
    if (![self length]) return nil; //there needs to be at least 1 length
    NSMutableData *mpk = [NSMutableData secureData];
    UInt512 I;
    
    HMAC(&I, SHA512, sizeof(UInt512), BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length);
    
    UInt256 secret = *(UInt256 *)&I, chain = *(UInt256 *)&I.u8[sizeof(UInt256)];
    
    [mpk appendBytes:[DSKey keyWithSecret:secret compressed:YES].hash160.u32 length:4];
    
    for (NSInteger i = 0;i<[self length];i++) {
        uint32_t derivation = (uint32_t)[self indexAtPosition:i];
        CKDpriv(&secret, &chain, derivation | BIP32_HARD);
    }
    
    [mpk appendBytes:&chain length:sizeof(chain)];
    [mpk appendData:[DSKey keyWithSecret:secret compressed:YES].publicKey];
    
    return mpk;
}

// master public key format is: 4 byte parent fingerprint || 32 byte chain code || 33 byte compressed public key
// the values are taken from BIP32 account m/44H/5H/0H
- (NSData *)generateExtendedPublicKeyFromSeed:(NSData *)seed storeUnderWalletUniqueId:(NSString*)walletUniqueId
{
    if (! seed) return nil;
    if (![self length]) return nil; //there needs to be at least 1 length
    NSMutableData *mpk = [NSMutableData secureData];
    UInt512 I;
    
    HMAC(&I, SHA512, sizeof(UInt512), BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length);
    
    UInt256 secret = *(UInt256 *)&I, chain = *(UInt256 *)&I.u8[sizeof(UInt256)];
    
    for (NSInteger i = 0;i<[self length] - 1;i++) {
        uint32_t derivation = (uint32_t)[self indexAtPosition:i];
        CKDpriv(&secret, &chain, derivation | BIP32_HARD);
    }
    [mpk appendBytes:[DSKey keyWithSecret:secret compressed:YES].hash160.u32 length:4];
    CKDpriv(&secret, &chain, (uint32_t)[self indexAtPosition:[self length] - 1] | BIP32_HARD); // account 0H
    
    [mpk appendBytes:&chain length:sizeof(chain)];
    [mpk appendData:[DSKey keyWithSecret:secret compressed:YES].publicKey];
    
    _extendedPublicKey = mpk;
    if (walletUniqueId) {
        setKeychainData(mpk,[self walletBasedExtendedPublicKeyLocationStringForWalletUniqueID:walletUniqueId],NO);
    }
    
    return mpk;
}

- (NSData *)generatePublicKeyAtIndex:(uint32_t)n internal:(BOOL)internal
{
    if (self.extendedPublicKey.length < 4 + sizeof(UInt256) + sizeof(DSECPoint)) return nil;
    
    UInt256 chain = *(const UInt256 *)((const uint8_t *)self.extendedPublicKey.bytes + 4);
    DSECPoint pubKey = *(const DSECPoint *)((const uint8_t *)self.extendedPublicKey.bytes + 36);
    
    CKDpub(&pubKey, &chain, internal ? 1 : 0); // internal or external chain
    CKDpub(&pubKey, &chain, n); // nth key in chain
    
    return [NSData dataWithBytes:&pubKey length:sizeof(pubKey)];
}

- (NSString *)privateKey:(uint32_t)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    return seed ? [self privateKeys:@[@(n)] internal:internal fromSeed:seed].lastObject : nil;
}

- (NSArray *)privateKeys:(NSArray *)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    if (! seed || ! n) return nil;
    if (n.count == 0) return @[];
    
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:n.count];
    UInt512 I;
    
    HMAC(&I, SHA512, sizeof(UInt512), BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length);
    
    UInt256 secret = *(UInt256 *)&I, chain = *(UInt256 *)&I.u8[sizeof(UInt256)];
    uint8_t version;
    if ([self.chain isMainnet]) {
        version = DASH_PRIVKEY;
    } else {
        version = DASH_PRIVKEY_TEST;
    }
    
    for (NSInteger i = 0;i<[self length];i++) {
        uint32_t derivation = (uint32_t)[self indexAtPosition:i];
        CKDpriv(&secret, &chain, derivation | BIP32_HARD);
    }
    
    CKDpriv(&secret, &chain, internal ? 1 : 0); // internal or external chain
    
    for (NSNumber *i in n) {
        NSMutableData *privKey = [NSMutableData secureDataWithCapacity:34];
        UInt256 s = secret, c = chain;
        
        CKDpriv(&s, &c, i.unsignedIntValue); // nth key in chain
        
        [privKey appendBytes:&version length:1];
        [privKey appendBytes:&s length:sizeof(s)];
        [privKey appendBytes:"\x01" length:1]; // specifies compressed pubkey format
        [a addObject:[NSString base58checkWithData:privKey]];
    }
    
    return a;
}

// MARK: - authentication key

+ (NSString *)authPrivateKeyFromSeed:(NSData *)seed forChain:(DSChain*)chain
{
    if (! seed) return nil;
    
    UInt512 I;
    
    HMAC(&I, SHA512, sizeof(UInt512), BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length);
    
    UInt256 secret = *(UInt256 *)&I, chainHash = *(UInt256 *)&I.u8[sizeof(UInt256)];
    
    uint8_t version;
    if ([chain isMainnet]) {
        version = DASH_PRIVKEY;
    } else {
        version = DASH_PRIVKEY_TEST;
    }
    
    // path m/1H/0 (same as copay uses for bitauth)
    CKDpriv(&secret, &chainHash, 1 | BIP32_HARD);
    CKDpriv(&secret, &chainHash, 0);
    
    NSMutableData *privKey = [NSMutableData secureDataWithCapacity:34];
    
    [privKey appendBytes:&version length:1];
    [privKey appendBytes:&secret length:sizeof(secret)];
    [privKey appendBytes:"\x01" length:1]; // specifies compressed pubkey format
    return [NSString base58checkWithData:privKey];
}

// key used for BitID: https://github.com/bitid/bitid/blob/master/BIP_draft.md
+ (NSString *)bitIdPrivateKey:(uint32_t)n forURI:(NSString *)uri fromSeed:(NSData *)seed forChain:(DSChain*)chain
{
    NSUInteger len = [uri lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *data = [NSMutableData dataWithCapacity:sizeof(n) + len];
    
    [data appendUInt32:n];
    [data appendBytes:uri.UTF8String length:len];
    
    UInt256 hash = data.SHA256;
    UInt512 I;
    
    HMAC(&I, SHA512, sizeof(UInt512), BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length);
    
    UInt256 secret = *(UInt256 *)&I, chainHash = *(UInt256 *)&I.u8[sizeof(UInt256)];
    uint8_t version;
    if ([chain isMainnet]) {
        version = DASH_PRIVKEY;
    } else {
        version = DASH_PRIVKEY_TEST;
    }
    
    CKDpriv(&secret, &chainHash, 13 | BIP32_HARD); // m/13H
    CKDpriv(&secret, &chainHash, CFSwapInt32LittleToHost(hash.u32[0]) | BIP32_HARD); // m/13H/aH
    CKDpriv(&secret, &chainHash, CFSwapInt32LittleToHost(hash.u32[1]) | BIP32_HARD); // m/13H/aH/bH
    CKDpriv(&secret, &chainHash, CFSwapInt32LittleToHost(hash.u32[2]) | BIP32_HARD); // m/13H/aH/bH/cH
    CKDpriv(&secret, &chainHash, CFSwapInt32LittleToHost(hash.u32[3]) | BIP32_HARD); // m/13H/aH/bH/cH/dH
    
    NSMutableData *privKey = [NSMutableData secureDataWithCapacity:34];
    
    [privKey appendBytes:&version length:1];
    [privKey appendBytes:&secret length:sizeof(secret)];
    [privKey appendBytes:"\x01" length:1]; // specifies compressed pubkey format
    return [NSString base58checkWithData:privKey];
}

// MARK: - serializations

- (NSString *)serializedExtendedPrivateKeyFromSeed:(NSData *)seed
{
    @autoreleasepool {
    if (! seed) return nil;
    
    UInt512 I;
    
    HMAC(&I, SHA512, sizeof(UInt512), BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length);
    
    UInt256 secret = *(UInt256 *)&I, chain = *(UInt256 *)&I.u8[sizeof(UInt256)];
    uint8_t version;
    if ([self.chain isMainnet]) {
        version = DASH_PRIVKEY;
    } else {
        version = DASH_PRIVKEY_TEST;
    }
    
    for (NSInteger i = 0;i<[self length] - 1;i++) {
        uint32_t derivation = (uint32_t)[self indexAtPosition:i];
        CKDpriv(&secret, &chain, derivation | BIP32_HARD);
    }
    uint32_t fingerprint = [DSKey keyWithSecret:secret compressed:YES].hash160.u32[0];
    CKDpriv(&secret, &chain, (uint32_t)[self indexAtPosition:[self length] - 1] | BIP32_HARD); // account 0H
    
    return serialize([self length], fingerprint, self.account.accountNumber | BIP32_HARD, chain, [NSData dataWithBytes:&secret length:sizeof(secret)],[self.chain isMainnet]);
    }
}

+ (NSData *)deserializedExtendedPrivateKey:(NSString *)extendedPrivateKeyString onChain:(DSChain*)chain
{
    @autoreleasepool {
    uint8_t depth;
    uint32_t fingerprint;
    uint32_t child;
    UInt256 chainHash;
    NSData * privkey = nil;
    NSMutableData * masterPrivateKey = [NSMutableData secureData];
    BOOL valid = deserialize(extendedPrivateKeyString, &depth, &fingerprint, &child, &chainHash, &privkey,[chain isMainnet]);
    if (!valid) return nil;
    [masterPrivateKey appendUInt32:CFSwapInt32HostToBig(fingerprint)];
    [masterPrivateKey appendBytes:&chainHash length:32];
    [masterPrivateKey appendData:privkey];
    return [masterPrivateKey copy];
    }
}

- (NSString *)serializedExtendedPublicKey
{
    if (self.extendedPublicKey.length < 36) return nil;
    
    uint32_t fingerprint = CFSwapInt32BigToHost(*(const uint32_t *)self.extendedPublicKey.bytes);
    UInt256 chain = *(UInt256 *)((const uint8_t *)self.extendedPublicKey.bytes + 4);
    DSECPoint pubKey = *(DSECPoint *)((const uint8_t *)self.extendedPublicKey.bytes + 36);
    uint32_t child = self.child?[self.child unsignedIntValue]:self.account.accountNumber | BIP32_HARD;
    return serialize([self.depth unsignedCharValue], fingerprint, child, chain, [NSData dataWithBytes:&pubKey length:sizeof(pubKey)],[self.chain isMainnet]);
}

+ (NSData *)deserializedExtendedPublicKey:(NSString *)extendedPublicKeyString onChain:(DSChain*)chain rDepth:(uint8_t*)depth rChild:(uint32_t*)child
{
    uint32_t fingerprint;
    UInt256 chainHash;
    NSData * pubkey = nil;
    NSMutableData * masterPublicKey = [NSMutableData secureData];
    BOOL valid = deserialize(extendedPublicKeyString, depth, &fingerprint, child, &chainHash, &pubkey,[chain isMainnet]);
    if (!valid) return nil;
    [masterPublicKey appendUInt32:CFSwapInt32HostToBig(fingerprint)];
    [masterPublicKey appendBytes:&chainHash length:32];
    [masterPublicKey appendData:pubkey];
    return [masterPublicKey copy];
}

- (NSData *)deserializedExtendedPublicKey:(NSString *)extendedPublicKeyString
{
    return [DSDerivationPath deserializedExtendedPublicKey:extendedPublicKeyString onChain:self.chain];
}

@end

