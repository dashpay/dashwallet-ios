//
//  ZNWalletManager.m
//  ZincWallet
//
//  Created by Aaron Voisine on 3/2/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
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

#import "ZNWalletManager.h"
#import "ZNWallet.h"
#import "ZNKey.h"
#import "ZNKeySequence.h"
#import "ZNZincMnemonic.h"
#import "ZNBIP39Mnemonic.h"
#import "ZNPeer.h"
#import "ZNTransaction.h"
#import "ZNTransactionEntity.h"
#import "ZNAddressEntity.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSManagedObject+Utils.h"
#import <netdb.h>
#import "Reachability.h"

#define BTC           @"\xC9\x83"     // capital B with stroke (utf-8)
#define CURRENCY_SIGN @"\xC2\xA4"     // generic currency sign (utf-8)
#define NBSP          @"\xC2\xA0"     // no-break space (utf-8)
#define NARROW_NBSP   @"\xE2\x80\xAF" // narrow no-break space (utf-8)

#define LOCAL_CURRENCY_SYMBOL_KEY @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY   @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY  @"LOCAL_CURRENCY_PRICE"
#define MNEMONIC_KEY              @"mnemonic"
#define SEED_KEY                  @"seed"
#define CREATION_TIME_KEY         @"creationtime"

#define SEED_ENTROPY_LENGTH    (128/8)
#define SEC_ATTR_SERVICE       @"cc.zinc.zincwallet"
#define DEFAULT_CURRENCY_PRICE 100000.0

#define BASE_URL    @"https://blockchain.info"
#define UNSPENT_URL BASE_URL "/unspent?active="
#define ADDRESS_URL BASE_URL "/multiaddr?active="

static BOOL setKeychainData(NSData *data, NSString *key)
{
    if (! key) return NO;

    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:(__bridge id)kCFBooleanTrue};

    SecItemDelete((__bridge CFDictionaryRef)query);

    if (! data) return YES;

    NSDictionary *item = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                           (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                           (__bridge id)kSecAttrAccount:key,
                           (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                           (__bridge id)kSecValueData:data};
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);

    if (status != noErr) {
        NSLog(@"SecItemAdd error status %d", (int)status);
        return NO;
    }

    return YES;
}

static NSData *getKeychainData(NSString *key)
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:(__bridge id)kCFBooleanTrue};
    CFDataRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);

    if (status != noErr) {
        NSLog(@"SecItemCopyMatching error status %d", (int)status);
        return nil;
    }

    return CFBridgingRelease(result);
}

@interface ZNWalletManager()

@property (nonatomic, strong) ZNWallet *wallet;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, assign) BOOL hasSeed;

@end

@implementation ZNWalletManager

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;

    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });

    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    [NSManagedObject setConcurrencyType:NSPrivateQueueConcurrencyType];

    self.reachability = [Reachability reachabilityForInternetConnection];

    self.format = [NSNumberFormatter new];
    self.format.lenient = YES;
    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
    self.format.minimumFractionDigits = 0;
    self.format.negativeFormat =
        [self.format.positiveFormat stringByReplacingOccurrencesOfString:CURRENCY_SIGN withString:CURRENCY_SIGN @"-"];
    //self.format.currencySymbol = @"m" BTC NARROW_NBSP;
    //self.format.maximumFractionDigits = 5;
    //self.format.maximum = @21000000000.0;
    self.format.currencySymbol = BTC NARROW_NBSP;
    self.format.maximumFractionDigits = 8;
    self.format.maximum = @21000000.0;

    self.hasSeed = (self.seed == nil) ? NO : YES;

    [self updateExchangeRate];

    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (ZNWallet *)wallet
{
    if (_wallet == nil && self.hasSeed) {
        _wallet =
            [[ZNWallet alloc] initWithContext:[NSManagedObject context] andSeed:^NSData *{
                return self.seed;
            }];
    }

    return _wallet;
}

- (NSData *)seed
{
    return getKeychainData(SEED_KEY);
}

- (void)setSeed:(NSData *)seed
{
    if (seed && self.hasSeed && [self.seed isEqual:seed]) return;

    [[NSManagedObject context] performBlockAndWait:^{
        [ZNAddressEntity deleteObjects:[ZNAddressEntity allObjects]];
        [ZNTransactionEntity deleteObjects:[ZNTransactionEntity allObjects]];
        [NSManagedObject saveContext];
    }];

    setKeychainData(nil, MNEMONIC_KEY);
    setKeychainData(nil, CREATION_TIME_KEY);
    if (! setKeychainData(seed, SEED_KEY)) {
        NSLog(@"error setting wallet seed");
        [[[UIAlertView alloc] initWithTitle:@"couldn't create wallet"
          message:@"error adding private keys to the iOS keychain, make sure the app has keychain entitlements"
          delegate:self cancelButtonTitle:@"abort" otherButtonTitles:nil] show];
        return;
    }

    self.hasSeed = (seed == nil) ? NO : YES;
    _wallet = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ZNWalletManagerSeedChangedNotification object:nil];
    });
}

- (NSString *)seedPhrase
{
    NSData *phrase = getKeychainData(MNEMONIC_KEY);

    if (! phrase) return [[ZNZincMnemonic sharedInstance] encodePhrase:self.seed]; // use old phrase format

    return CFBridgingRelease(CFStringCreateFromExternalRepresentation(SecureAllocator(), (__bridge CFDataRef)phrase,
                                                                      kCFStringEncodingUTF8));
}

- (void)setSeedPhrase:(NSString *)seedPhrase
{
    @autoreleasepool {
        if (! [[ZNBIP39Mnemonic sharedInstance] phraseIsValid:seedPhrase]) { // phrase is in old format
            self.seed = [[ZNZincMnemonic sharedInstance] decodePhrase:seedPhrase];
            return;
        }

        ZNBIP39Mnemonic *m = [ZNBIP39Mnemonic sharedInstance];
        
        seedPhrase = [m encodePhrase:[m decodePhrase:seedPhrase]];
        self.seed = [m deriveKeyFromPhrase:seedPhrase withPassphrase:nil];

        NSData *d = CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(),
                                                                           (__bridge CFStringRef)seedPhrase,
                                                                           kCFStringEncodingUTF8, 0));
        
        setKeychainData(d, MNEMONIC_KEY);
    }
}

- (void)generateRandomSeed
{
    @autoreleasepool {
        NSMutableData *entropy = [NSMutableData secureDataWithLength:SEED_ENTROPY_LENGTH];
        NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];

        SecRandomCopyBytes(kSecRandomDefault, entropy.length, entropy.mutableBytes);

        self.seedPhrase = [[ZNBIP39Mnemonic sharedInstance] encodePhrase:entropy];

        // we store the wallet creation time on the keychain because keychain data persists even when an app is deleted
        setKeychainData([NSData dataWithBytes:&time length:sizeof(time)], CREATION_TIME_KEY);
    }
}

- (NSTimeInterval)seedCreationTime
{
    NSData *d = getKeychainData(CREATION_TIME_KEY);

    return (d.length < sizeof(NSTimeInterval)) ? BITCOIN_REFERENCE_BLOCK_TIME : *(NSTimeInterval *)d.bytes;
}

- (void)updateExchangeRate
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateExchangeRate) object:nil];
    [self performSelector:@selector(updateExchangeRate) withObject:nil afterDelay:60.0];

    if (self.reachability.currentReachabilityStatus == NotReachable) return;

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:ADDRESS_URL]
                         cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10.0];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue currentQueue]
    completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            NSLog(@"%@", connectionError);
            return;
        }

        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

        if (error || ! [json isKindOfClass:[NSDictionary class]] ||
            ! [json[@"info"] isKindOfClass:[NSDictionary class]] ||
            ! [json[@"info"][@"symbol_local"] isKindOfClass:[NSDictionary class]] ||
            ! [json[@"info"][@"symbol_local"][@"symbol"] isKindOfClass:[NSString class]] ||
            ! [json[@"info"][@"symbol_local"][@"code"] isKindOfClass:[NSString class]] ||
            ! [json[@"info"][@"symbol_local"][@"conversion"] isKindOfClass:[NSNumber class]]) {
            NSLog(@"unexpected response from blockchain.info:\n%@",
                  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            return;
        }

        [defs setObject:json[@"info"][@"symbol_local"][@"symbol"] forKey:LOCAL_CURRENCY_SYMBOL_KEY];
        [defs setObject:json[@"info"][@"symbol_local"][@"code"] forKey:LOCAL_CURRENCY_CODE_KEY];
        [defs setObject:json[@"info"][@"symbol_local"][@"conversion"] forKey:LOCAL_CURRENCY_PRICE_KEY];
        [defs synchronize];
        NSLog(@"exchange rate updated to %@/%@", [self localCurrencyStringForAmount:SATOSHIS],
              [self stringForAmount:SATOSHIS]);

        if (! self.wallet) return;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNWalletBalanceChangedNotification object:nil];
        });
    }];
}

// given a private key, queries blockchain for unspent outputs and calls the completion block with a signed transaction
// that will sweep the balance into the wallet (doesn't publish the tx)
//TODO: XXXX test this
- (void)sweepPrivateKey:(NSString *)privKey withFee:(BOOL)fee
completion:(void (^)(ZNTransaction *tx, NSError *error))completion
{
    //TODO: add support for BIP38 password encrypted private keys
    NSString *address = [[ZNKey keyWithPrivateKey:privKey] address];

    if (! completion) return;

    if (! address) {
        completion(nil, [NSError errorWithDomain:@"ZincWallet" code:187
                         userInfo:@{NSLocalizedDescriptionKey:@"not a valid private key"}]);
        return;
    }

    if ([self.wallet containsAddress:address]) {
        completion(nil, [NSError errorWithDomain:@"ZincWallet" code:187
                         userInfo:@{NSLocalizedDescriptionKey:@"this private key is already in your wallet"}]);
        return;
    }

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:[UNSPENT_URL stringByAppendingString:address]]
                         cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10.0];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue currentQueue]
    completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            completion(nil, connectionError);
            return;
        }

        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        uint64_t balance = 0, standardFee = 0;
        ZNTransaction *tx = [ZNTransaction new];

        if (error) {
            if ([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] hasPrefix:@"No free outputs"]) {
                error = [NSError errorWithDomain:@"ZincWallet" code:417
                         userInfo:@{NSLocalizedDescriptionKey:@"this private key is empty"}];
            }

            completion(nil, error);
            return;
        }

        if (! [json isKindOfClass:[NSDictionary class]] ||
            ! [json[@"unspent_outputs"] isKindOfClass:[NSArray class]]) {
            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
                             userInfo:@{NSLocalizedDescriptionKey:@"unexpected response from blockchain.info"}]);
            return;
        }

        //TODO: make sure not to create a transaction larger than TX_MAX_SIZE
        for (NSDictionary *utxo in json[@"unspent_outputs"]) {
            if (! [utxo isKindOfClass:[NSDictionary class]] ||
                ! [utxo[@"tx_hash"] isKindOfClass:[NSString class]] || ! [utxo[@"tx_hash"] hexToData] ||
                ! [utxo[@"tx_output_n"] isKindOfClass:[NSNumber class]] ||
                ! [utxo[@"script"] isKindOfClass:[NSString class]] || ! [utxo[@"script"] hexToData] ||
                ! [utxo[@"value"] isKindOfClass:[NSNumber class]]) {
                completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
                                 userInfo:@{NSLocalizedDescriptionKey:@"unexpected response from blockchain.info"}]);
                return;
            }

            [tx addInputHash:[utxo[@"tx_hash"] hexToData] index:[utxo[@"tx_output_n"] unsignedIntegerValue]
             script:[utxo[@"script"] hexToData]];
            balance += [utxo[@"value"] unsignedLongLongValue];
        }

        if (balance == 0) {
            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
                             userInfo:@{NSLocalizedDescriptionKey:@"this private key is empty"}]);
            return;
        }

        // we will be adding a wallet output (additional 34 bytes)
        //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
        if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;

        if (standardFee + TX_MIN_OUTPUT_AMOUNT > balance) {
            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
                             userInfo:@{NSLocalizedDescriptionKey:@"transaction fees would cost more than the funds "
                                        "available on this private key (due to tiny \"dust\" deposits)"}]);
            return;
        }

        [tx addOutputAddress:[self.wallet changeAddress] amount:balance - standardFee];

        if (! [tx signWithPrivateKeys:@[privKey]]) {
            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:401
                             userInfo:@{NSLocalizedDescriptionKey:@"error signing transaction"}]);
            return;
        }

        completion(tx, nil);
    }];
}

#pragma mark - string helpers

// TODO: make this work with local currency amounts
- (int64_t)amountForString:(NSString *)string
{
    return ([[self.format numberFromString:string] doubleValue] + DBL_EPSILON)*
           pow(10.0, self.format.maximumFractionDigits);
}

- (NSString *)stringForAmount:(int64_t)amount
{
    NSUInteger min = self.format.minimumFractionDigits;

    if (amount == 0) {
        self.format.minimumFractionDigits =
            self.format.maximumFractionDigits > 4 ? 4 : self.format.maximumFractionDigits;
    }

    NSString *r = [self.format stringFromNumber:@(amount/pow(10.0, self.format.maximumFractionDigits))];

    self.format.minimumFractionDigits = min;

    return r;
}

- (NSString *)localCurrencyStringForAmount:(int64_t)amount
{
    static NSNumberFormatter *format = nil;

    if (! format) {
        format = [NSNumberFormatter new];
        format.lenient = YES;
        format.numberStyle = NSNumberFormatterCurrencyStyle;
        format.negativeFormat =
            [format.positiveFormat stringByReplacingOccurrencesOfString:CURRENCY_SIGN withString:CURRENCY_SIGN @"-"];
    }

    if (! amount) return [format stringFromNumber:@(0)];

    NSString *symbol = [[NSUserDefaults standardUserDefaults] stringForKey:LOCAL_CURRENCY_SYMBOL_KEY];
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:LOCAL_CURRENCY_CODE_KEY];
    double price = [[NSUserDefaults standardUserDefaults] doubleForKey:LOCAL_CURRENCY_PRICE_KEY];

    if (! symbol.length || price <= DBL_EPSILON) return [format stringFromNumber:@(amount/DEFAULT_CURRENCY_PRICE)];

    format.currencySymbol = symbol;
    format.currencyCode = code;

    NSString *ret = [format stringFromNumber:@(amount/price)];

    // if the amount is too small to be represented in local currency (but is != 0) then return a string like "<$0.01"
    if (amount != 0 && [[format numberFromString:ret] isEqual:@(0.0)]) {
        ret = [@"<" stringByAppendingString:[format stringFromNumber:@(1.0/pow(10.0, format.maximumFractionDigits))]];
    }

    return ret;
}

#pragma mark UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    abort();
}

@end
