//
//  BRWalletManager.m
//  BreadWallet
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

#import "BRWalletManager.h"
#import "BRWallet.h"
#import "BRKey.h"
#import "BRKey+BIP38.h"
#import "BRBIP39Mnemonic.h"
#import "BRBIP32Sequence.h"
#import "BRPeer.h"
#import "BRTransaction.h"
#import "BRTransactionEntity.h"
#import "BRAddressEntity.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSManagedObject+Sugar.h"
#import "Reachability.h"

#define BTC         @"\xC9\x83"     // capital B with stroke (utf-8)
#define BITS        @"\xC6\x80"     // lowercase b with stroke (utf-8)
#define NARROW_NBSP @"\xE2\x80\xAF" // narrow no-break space (utf-8)

#define BASE_URL    @"https://blockchain.info"
#define UNSPENT_URL BASE_URL "/unspent?active="
#define TICKER_URL  BASE_URL "/ticker"

#define SEED_ENTROPY_LENGTH    (128/8)
#define SEC_ATTR_SERVICE       @"org.voisine.breadwallet"
#define DEFAULT_CURRENCY_PRICE 500.0
#define DEFAULT_CURRENCY_CODE  @"USD"

#define LOCAL_CURRENCY_SYMBOL_KEY @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY   @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY  @"LOCAL_CURRENCY_PRICE"
#define CURRENCY_CODES_KEY        @"CURRENCY_CODES"

#define MNEMONIC_KEY        @"mnemonic"
#define CREATION_TIME_KEY   @"creationtime"
#define MASTER_PUBKEY_KEY   @"masterpubkey"
#define PASSCODE_DETECT_KEY @"passcodedetect"

// deprecated
#define SEED_KEY            @"seed"
#define PIN_KEY             @"pin"
#define PIN_FAIL_COUNT_KEY  @"pinfailcount"
#define PIN_FAIL_HEIGHT_KEY @"pinfailheight"

static BOOL isPasscodeEnabled()
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:PASSCODE_DETECT_KEY};
    
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, nil) != errSecItemNotFound) return YES;

    NSDictionary *item = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                           (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                           (__bridge id)kSecAttrAccount:PASSCODE_DETECT_KEY,
                           (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                           (__bridge id)kSecValueData:[NSData data]};
        
    return (SecItemAdd((__bridge CFDictionaryRef)item, NULL) != errSecDecode) ? YES : NO;
}

static BOOL setKeychainData(NSData *data, NSString *key, BOOL authenticated)
{
    if (! key) return NO;

    CFErrorRef error = NULL;
    SecAccessControlRef access = (data) ?
        SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                        (authenticated) ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly :
                                        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                        (authenticated) ? kSecAccessControlUserPresence : 0, &error) : NULL;
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key};

    if (data && (access == NULL || error)) {
#if DEBUG
        [[[UIAlertView alloc] initWithTitle:nil message:[NSString stringWithFormat:@"SecAccessControlRef: %@", error]
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
#endif
        NSLog(@"SecAccessControlRef: %@", error);
        return NO;
    }
    
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL) == errSecItemNotFound) {
        if (! data) return YES;

        NSDictionary *item = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                               (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                               (__bridge id)kSecAttrAccount:key,
                               (__bridge id)kSecAttrAccessControl:(__bridge_transfer id)access,
                               (__bridge id)kSecValueData:data};
        OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        
        if (status == noErr) return YES;
        NSLog(@"SecItemAdd error status %d", (int)status);
#if DEBUG
        [[[UIAlertView alloc] initWithTitle:nil
          message:[NSString stringWithFormat:@"SecItemAdd error status %d", (int)status] delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
#endif
        return NO;
    }
    
    if (! data) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

        if (status == noErr) return YES;
        NSLog(@"SecItemDelete error status %d", (int)status);
#if DEBUG
        [[[UIAlertView alloc] initWithTitle:nil
          message:[NSString stringWithFormat:@"SecItemDelete error status %d", (int)status] delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
#endif
        return NO;
    }

    NSDictionary *update = @{(__bridge id)kSecAttrAccessControl:(__bridge_transfer id)access,
                             (__bridge id)kSecValueData:data};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
    
    if (status == noErr) return YES;
    NSLog(@"SecItemUpdate error status %d", (int)status);
#if DEBUG
    [[[UIAlertView alloc] initWithTitle:nil
      message:[NSString stringWithFormat:@"SecItemUpdate error status %d", (int)status] delegate:nil
      cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
#endif
    return NO;
}

static NSData *getKeychainData(NSString *key, NSString *authprompt)
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:@YES,
                            (__bridge id)kSecUseOperationPrompt:(authprompt) ? authprompt : @""};
    CFDataRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);

    if (status == errSecItemNotFound) return nil;
    if (status == noErr) return CFBridgingRelease(result);
    
    if (status == errSecAuthFailed && ! isPasscodeEnabled()) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"turn device passcode on", nil)
         message:NSLocalizedString(@"\ngo to settings and turn passcode on to access restricted areas of your wallet",
                                   nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
         otherButtonTitles:nil] show];
    }
#if DEBUG
    else {
        [[[UIAlertView alloc] initWithTitle:nil
          message:[NSString stringWithFormat:@"SecItemCopyMatching error status %d", (int)status] delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    }
#endif
    
    NSLog(@"SecItemCopyMatching error status %d", (int)status);
    return nil;
}

@interface BRWalletManager()

@property (nonatomic, strong) BRWallet *wallet;
@property (nonatomic, strong) id<BRKeySequence> sequence;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, assign) BOOL sweepFee;
@property (nonatomic, strong) NSString *sweepKey;
@property (nonatomic, strong) void (^sweepCompletion)(BRTransaction *tx, NSError *error);
@property (nonatomic, strong) id protectedObserver;

@end

@implementation BRWalletManager

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

    _format = [NSNumberFormatter new];
    self.format.lenient = YES;
    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
    self.format.negativeFormat = [self.format.positiveFormat
                                  stringByReplacingCharactersInRange:[self.format.positiveFormat rangeOfString:@"#"]
                                  withString:@"-#"];
    self.format.currencyCode = @"XBT";
    self.format.currencySymbol = BITS NARROW_NBSP;
    self.format.internationalCurrencySymbol = self.format.currencySymbol;
    self.format.minimumFractionDigits = 0; // iOS 8 bug, minimumFractionDigits now has to be set after currencySymbol
    self.format.maximumFractionDigits = 2;
//    self.format.currencySymbol = BTC NARROW_NBSP;
//    self.format.maximumFractionDigits = 8;

    self.format.maximum = @(MAX_MONEY/(int64_t)pow(10.0, self.format.maximumFractionDigits));

    _localFormat = [NSNumberFormatter new];
    self.localFormat.lenient = YES;
    self.localFormat.numberStyle = NSNumberFormatterCurrencyStyle;
    self.localFormat.negativeFormat = self.format.negativeFormat;

    self.protectedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [self protectedInit];
        }];

    if ([[UIApplication sharedApplication] isProtectedDataAvailable]) [self protectedInit];

    return self;
}

- (void)protectedInit
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    
    _localCurrencyCode = [defs stringForKey:LOCAL_CURRENCY_CODE_KEY],
    _localCurrencyPrice = [defs doubleForKey:LOCAL_CURRENCY_PRICE_KEY];
    self.localFormat.maximum = @((MAX_MONEY/SATOSHIS)*self.localCurrencyPrice);
    _currencyCodes = [defs arrayForKey:CURRENCY_CODES_KEY];
    
    if (self.localCurrencyCode) {
        self.localFormat.currencySymbol = [defs stringForKey:LOCAL_CURRENCY_SYMBOL_KEY];
        self.localFormat.currencyCode = self.localCurrencyCode;
    }
    else {
        self.localFormat.currencySymbol = [[NSLocale currentLocale] objectForKey:NSLocaleCurrencySymbol];
        self.localFormat.currencyCode = _localCurrencyCode =
        [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode];
        //BUG: if locale changed since last time, we'll start with an incorrect price
    }
    
    [self updateExchangeRate];
}

- (void)dealloc
{
    if (self.protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (BRWallet *)wallet
{
    if (_wallet || ! [[UIApplication sharedApplication] isProtectedDataAvailable]) return _wallet;

    if (getKeychainData(SEED_KEY, nil)) { // upgrade from old non-authenticated keychain
        NSLog(@"upgrading to authenticated keychain scheme");
        setKeychainData([self.sequence masterPublicKeyFromSeed:self.seed], MASTER_PUBKEY_KEY, NO);
        setKeychainData(getKeychainData(MNEMONIC_KEY, nil), MNEMONIC_KEY, YES);
        setKeychainData(nil, SEED_KEY, NO);
        setKeychainData(nil, PIN_KEY, NO);
        setKeychainData(nil, PIN_FAIL_COUNT_KEY, NO);
        setKeychainData(nil, PIN_FAIL_HEIGHT_KEY, NO);
    }
    
    if (! self.masterPublicKey) return _wallet;
    
    @synchronized(self) {
        if (_wallet) return _wallet;
            
        _wallet = [[BRWallet alloc] initWithContext:[NSManagedObject context] sequence:self.sequence
                   masterPublicKey:self.masterPublicKey seed:^NSData *{ return self.seed; }];

        // verify that keychain matches core data, with different access and backup policies it's possible to diverge
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BRKey *k = [BRKey keyWithPublicKey:[self.sequence publicKey:0 internal:NO
                                                masterPublicKey:self.masterPublicKey]];
                    
            if (_wallet.addresses.count > 0 && ! [_wallet containsAddress:k.address]) {
#if DEBUG
                abort(); // don't wipe core data for debug builds
#endif
                [[NSManagedObject context] performBlockAndWait:^{
                    [BRAddressEntity deleteObjects:[BRAddressEntity allObjects]];
                    [BRTransactionEntity deleteObjects:[BRTransactionEntity allObjects]];
                    [NSManagedObject saveContext];
                }];
                
                _wallet = nil;
                    
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletManagerSeedChangedNotification
                     object:nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletBalanceChangedNotification
                     object:nil];
                });
            }
        });
        
        return _wallet;
    }
}

- (id<BRKeySequence>)sequence
{
    if (! _sequence) _sequence = [BRBIP32Sequence new];
    return _sequence;
}

- (NSData *)masterPublicKey
{
    return getKeychainData(MASTER_PUBKEY_KEY, nil);
}

// requesting seed will trigger authentication
- (NSData *)seed
{
    return [self seedWithPrompt:nil];
}

// requesting seedPhrase will trigger authentication
- (NSString *)seedPhrase
{
    return [self seedPhraseWithPrompt:nil];
}

- (void)setSeedPhrase:(NSString *)seedPhrase
{
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        BRBIP39Mnemonic *m = [BRBIP39Mnemonic sharedInstance];
        
        if (seedPhrase) seedPhrase = [m encodePhrase:[m decodePhrase:seedPhrase]];

        [[NSManagedObject context] performBlockAndWait:^{
            [BRAddressEntity deleteObjects:[BRAddressEntity allObjects]];
            [BRTransactionEntity deleteObjects:[BRTransactionEntity allObjects]];
            [NSManagedObject saveContext];
        }];
        
        setKeychainData(nil, CREATION_TIME_KEY, NO);
        setKeychainData(nil, MASTER_PUBKEY_KEY, NO);
        
        NSData *mnemonic = (seedPhrase) ?
                           CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(),
                                                                                  (CFStringRef)seedPhrase,
                                                                                  kCFStringEncodingUTF8, 0)) : nil,
               *masterPubKey = (seedPhrase) ?
                               [self.sequence
                                masterPublicKeyFromSeed:[m deriveKeyFromPhrase:seedPhrase withPassphrase:nil]] : nil;

        if (! setKeychainData(mnemonic, MNEMONIC_KEY, YES)) {
            NSLog(@"error setting wallet seed");

            if (seedPhrase) {
                [[[UIAlertView alloc] initWithTitle:@"couldn't create wallet"
                  message:@"error adding master private key to iOS keychain, make sure app has keychain entitlements"
                  delegate:self cancelButtonTitle:@"abort" otherButtonTitles:nil] show];
            }

            return;
        }
        
        setKeychainData(masterPubKey, MASTER_PUBKEY_KEY, NO);
        _wallet = nil;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletManagerSeedChangedNotification object:nil];
    });
}

// interval since refrence date, 00:00:00 01/01/01 GMT
- (NSTimeInterval)seedCreationTime
{
    NSData *d = getKeychainData(CREATION_TIME_KEY, nil);

    return (d.length < sizeof(NSTimeInterval)) ? BITCOIN_REFERENCE_BLOCK_TIME : *(const NSTimeInterval *)d.bytes;
}

// true if device passcode is enabled
- (BOOL)isPasscodeEnabled
{
    return isPasscodeEnabled();
}

 // generates a random seed, saves to keychain and returns the associated seedPhrase
- (NSString *)generateRandomSeed
{
    @autoreleasepool {
        NSMutableData *entropy = [NSMutableData secureDataWithLength:SEED_ENTROPY_LENGTH];
        NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];
        
        SecRandomCopyBytes(kSecRandomDefault, entropy.length, entropy.mutableBytes);
        
        NSString *phrase = [[BRBIP39Mnemonic sharedInstance] encodePhrase:entropy];
        
        self.seedPhrase = phrase;
        
        // we store the wallet creation time on the keychain because keychain data persists even when an app is deleted
        setKeychainData([NSData dataWithBytes:&time length:sizeof(time)], CREATION_TIME_KEY, NO);
        
        return phrase;
    }
}

// authenticates user and returns seed
- (NSData *)seedWithPrompt:(NSString *)authprompt
{
    @autoreleasepool {
        BRBIP39Mnemonic *m = [BRBIP39Mnemonic sharedInstance];
        NSString *phrase = [self seedPhraseWithPrompt:authprompt];
        
        if (phrase.length == 0) return nil;
        return [m deriveKeyFromPhrase:phrase withPassphrase:nil];
    }
}

// authenticates user and returns seedPhrase
- (NSString *)seedPhraseWithPrompt:(NSString *)authprompt
{
    @autoreleasepool {
        NSData *phrase = getKeychainData(MNEMONIC_KEY, authprompt);
        
        if (! phrase) return nil;
        
        self.didAuthenticate = YES;
        return CFBridgingRelease(CFStringCreateFromExternalRepresentation(SecureAllocator(), (CFDataRef)phrase,
                                                                          kCFStringEncodingUTF8));
    }
}

// prompts user to authenticate with touch id or passcode
- (BOOL)authenticateWithPrompt:(NSString *)authprompt
{
    @autoreleasepool {
        if (! getKeychainData(MNEMONIC_KEY, authprompt)) return NO;
        self.didAuthenticate = YES;
        return YES;
    }
}

// local currency ISO code
- (void)setLocalCurrencyCode:(NSString *)localCurrencyCode
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    
    _localCurrencyCode = [localCurrencyCode copy];
    
    if ([self.localCurrencyCode isEqual:[[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode]]) {
        [defs removeObjectForKey:LOCAL_CURRENCY_CODE_KEY];
    }
    else {
        [defs setObject:self.localCurrencyCode forKey:LOCAL_CURRENCY_CODE_KEY];
    }
    
    [defs removeObjectForKey:LOCAL_CURRENCY_SYMBOL_KEY];
    [defs removeObjectForKey:LOCAL_CURRENCY_PRICE_KEY];
    
    [self updateExchangeRate];
}

- (void)updateExchangeRate
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateExchangeRate) object:nil];
    [self performSelector:@selector(updateExchangeRate) withObject:nil afterDelay:60.0];

    if (self.reachability.currentReachabilityStatus == NotReachable) return;

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:TICKER_URL]
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

        _localCurrencyCode = [defs stringForKey:LOCAL_CURRENCY_CODE_KEY];
        if (! self.localCurrencyCode) _localCurrencyCode = [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode];

        if (error || ! [json isKindOfClass:[NSDictionary class]] ||
            ! [json[DEFAULT_CURRENCY_CODE] isKindOfClass:[NSDictionary class]] ||
            ! [json[DEFAULT_CURRENCY_CODE][@"last"] isKindOfClass:[NSNumber class]] ||
            ([json[self.localCurrencyCode] isKindOfClass:[NSDictionary class]] &&
             (! [json[self.localCurrencyCode][@"last"] isKindOfClass:[NSNumber class]] ||
              ! [json[self.localCurrencyCode][@"symbol"] isKindOfClass:[NSString class]]))) {
            NSLog(@"unexpected response from %@:\n%@", req.URL.host,
                  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            return;
        }

        // if local currency is missing, use default
        if (! [json[self.localCurrencyCode] isKindOfClass:[NSDictionary class]]) {
            self.localFormat.currencyCode = _localCurrencyCode = DEFAULT_CURRENCY_CODE;
        }
        else {
            self.localFormat.currencySymbol = json[self.localCurrencyCode][@"symbol"];
            self.localFormat.currencyCode = self.localCurrencyCode;
        }

        _localCurrencyPrice = [json[self.localCurrencyCode][@"last"] doubleValue];
        self.localFormat.maximum = @((MAX_MONEY/SATOSHIS)*self.localCurrencyPrice);
        _currencyCodes = [NSArray arrayWithArray:json.allKeys];
        
        if ([self.localCurrencyCode isEqual:[[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode]]) {
            [defs removeObjectForKey:LOCAL_CURRENCY_SYMBOL_KEY];
            [defs removeObjectForKey:LOCAL_CURRENCY_CODE_KEY];
        }
        else {
            [defs setObject:self.localFormat.currencySymbol forKey:LOCAL_CURRENCY_SYMBOL_KEY];
            [defs setObject:self.localCurrencyCode forKey:LOCAL_CURRENCY_CODE_KEY];
        }

        [defs setObject:@(self.localCurrencyPrice) forKey:LOCAL_CURRENCY_PRICE_KEY];
        [defs setObject:self.currencyCodes forKey:CURRENCY_CODES_KEY];
        [defs synchronize];
        NSLog(@"exchange rate updated to %@/%@", [self localCurrencyStringForAmount:SATOSHIS],
              [self stringForAmount:SATOSHIS]);

        if (! self.wallet) return;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletBalanceChangedNotification object:nil];
        });
    }];
}

// given a private key, queries blockchain for unspent outputs and calls the completion block with a signed transaction
// that will sweep the balance into the wallet (doesn't publish the tx)
- (void)sweepPrivateKey:(NSString *)privKey withFee:(BOOL)fee
completion:(void (^)(BRTransaction *tx, NSError *error))completion
{
    if (! completion) return;

    if ([privKey isValidBitcoinBIP38Key]) {
        UIAlertView *v = [[UIAlertView alloc] initWithTitle:@"password protected key" message:nil delegate:self
                          cancelButtonTitle:@"cancel" otherButtonTitles:@"ok", nil];

        v.alertViewStyle = UIAlertViewStyleSecureTextInput;
        [v textFieldAtIndex:0].returnKeyType = UIReturnKeyDone;
        [v textFieldAtIndex:0].placeholder = @"password";
        [v show];

        self.sweepKey = privKey;
        self.sweepFee = fee;
        self.sweepCompletion = completion;
        return;
    }

    NSString *address = [[BRKey keyWithPrivateKey:privKey] address];

    if (! address) {
        completion(nil, [NSError errorWithDomain:@"BreadWallet" code:187 userInfo:@{NSLocalizedDescriptionKey:
                         NSLocalizedString(@"not a valid private key", nil)}]);
        return;
    }

    if ([self.wallet containsAddress:address]) {
        completion(nil, [NSError errorWithDomain:@"BreadWallet" code:187 userInfo:@{NSLocalizedDescriptionKey:
                         NSLocalizedString(@"this private key is already in your wallet", nil)}]);
        return;
    }

    NSURL *u = [NSURL URLWithString:[UNSPENT_URL stringByAppendingString:address]];
    NSURLRequest *req = [NSURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringCacheData
                         timeoutInterval:20.0];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue currentQueue]
    completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            completion(nil, connectionError);
            return;
        }

        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        uint64_t balance = 0, standardFee = 0;
        BRTransaction *tx = [BRTransaction new];

        if (error) {
            if ([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] hasPrefix:@"No free outputs"]) {
                error = [NSError errorWithDomain:@"BreadWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                         NSLocalizedString(@"this private key is empty", nil)}];
            }

            completion(nil, error);
            return;
        }

        if (! [json isKindOfClass:[NSDictionary class]] ||
            ! [json[@"unspent_outputs"] isKindOfClass:[NSArray class]]) {
            completion(nil, [NSError errorWithDomain:@"BreadWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil), u.host]
                            }]);
            return;
        }

        //TODO: make sure not to create a transaction larger than TX_MAX_SIZE
        for (NSDictionary *utxo in json[@"unspent_outputs"]) {
            if (! [utxo isKindOfClass:[NSDictionary class]] ||
                ! [utxo[@"tx_hash"] isKindOfClass:[NSString class]] || ! [utxo[@"tx_hash"] hexToData] ||
                ! [utxo[@"tx_output_n"] isKindOfClass:[NSNumber class]] ||
                ! [utxo[@"script"] isKindOfClass:[NSString class]] || ! [utxo[@"script"] hexToData] ||
                ! [utxo[@"value"] isKindOfClass:[NSNumber class]]) {
                completion(nil, [NSError errorWithDomain:@"BreadWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                                 [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil),
                                  u.host]}]);
                return;
            }

            [tx addInputHash:[utxo[@"tx_hash"] hexToData] index:[utxo[@"tx_output_n"] unsignedIntegerValue]
             script:[utxo[@"script"] hexToData]];
            balance += [utxo[@"value"] unsignedLongLongValue];
        }

        if (balance == 0) {
            completion(nil, [NSError errorWithDomain:@"BreadWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             NSLocalizedString(@"this private key is empty", nil)}]);
            return;
        }

        // we will be adding a wallet output (additional 34 bytes)
        //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
        if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;

        if (standardFee + TX_MIN_OUTPUT_AMOUNT > balance) {
            completion(nil, [NSError errorWithDomain:@"BreadWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             NSLocalizedString(@"transaction fees would cost more than the funds available on this "
                                               "private key (due to tiny \"dust\" deposits)",nil)}]);
            return;
        }

        [tx addOutputAddress:[self.wallet changeAddress] amount:balance - standardFee];

        if (! [tx signWithPrivateKeys:@[privKey]]) {
            completion(nil, [NSError errorWithDomain:@"BreadWallet" code:401 userInfo:@{NSLocalizedDescriptionKey:
                             NSLocalizedString(@"error signing transaction", nil)}]);
            return;
        }

        completion(tx, nil);
    }];
}

#pragma mark - string helpers

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

// NOTE: For now these local currency methods assume that a satoshi has a smaller value than the smallest unit of any
// local currency. They will need to be revisited when that is no longer a safe assumption.
- (int64_t)amountForLocalCurrencyString:(NSString *)string
{
    if (self.localCurrencyPrice <= DBL_EPSILON) return 0;
    if ([string hasPrefix:@"<"]) string = [string substringFromIndex:1];

    int64_t local = ([[self.localFormat numberFromString:string] doubleValue] + DBL_EPSILON)*
                     pow(10.0, self.localFormat.maximumFractionDigits);

    if (local == 0) return 0;

    int64_t min = llabs(local)*SATOSHIS/
                  (int64_t)(self.localCurrencyPrice*pow(10.0, self.localFormat.maximumFractionDigits)) + 1,
            max = (llabs(local) + 1)*SATOSHIS/
                  (int64_t)(self.localCurrencyPrice*pow(10.0, self.localFormat.maximumFractionDigits)) - 1,
            amount = (min + max)/2, p = 10;

    if (amount >= MAX_MONEY) return (local < 0) ? -MAX_MONEY : MAX_MONEY;

    while ((amount/p)*p >= min) { // find lowest decimal precision that still matches local currency string
        p *= 10;
    }

    p /= 10;
    return (local < 0) ? -(amount/p)*p : (amount/p)*p;
}

- (NSString *)localCurrencyStringForAmount:(int64_t)amount
{
    if (amount == 0) return [self.localFormat stringFromNumber:@(0)];

    NSString *ret = [self.localFormat stringFromNumber:@(self.localCurrencyPrice*amount/SATOSHIS)];

    // if the amount is too small to be represented in local currency (but is != 0) then return a string like "<$0.01"
    if (amount > 0 && self.localCurrencyPrice*amount/SATOSHIS + DBL_EPSILON <
        1.0/pow(10.0, self.localFormat.maximumFractionDigits)) {
        ret = [@"<" stringByAppendingString:[self.localFormat
               stringFromNumber:@(1.0/pow(10.0, self.localFormat.maximumFractionDigits))]];
    }
    else if (amount < 0 && self.localCurrencyPrice*amount/SATOSHIS - DBL_EPSILON >
             -1.0/pow(10.0, self.localFormat.maximumFractionDigits)) {
        // technically should be '>', but '<' is more intuitive
        ret = [@"<" stringByAppendingString:[self.localFormat
               stringFromNumber:@(-1.0/pow(10.0, self.localFormat.maximumFractionDigits))]];
    }

    return ret;
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:@"abort"]) abort();

        if (self.sweepCompletion) self.sweepCompletion(nil, nil);
        self.sweepKey = nil;
        self.sweepCompletion = nil;
        return;
    }

    if (! self.sweepKey || ! self.sweepCompletion) return;

    NSString *passphrase = [[alertView textFieldAtIndex:0] text];

    dispatch_async(dispatch_get_main_queue(), ^{
        BRKey *key = [BRKey keyWithBIP38Key:self.sweepKey andPassphrase:passphrase];

        if (! key) {
            UIAlertView *v = [[UIAlertView alloc] initWithTitle:@"password protected key"
                              message:@"bad password, try again" delegate:self cancelButtonTitle:@"cancel"
                              otherButtonTitles:@"ok", nil];

            v.alertViewStyle = UIAlertViewStyleSecureTextInput;
            [v textFieldAtIndex:0].returnKeyType = UIReturnKeyDone;
            [v textFieldAtIndex:0].placeholder = @"password";
            [v show];
        }
        else {
            [self sweepPrivateKey:key.privateKey withFee:self.sweepFee completion:self.sweepCompletion];
            self.sweepKey = nil;
            self.sweepCompletion = nil;
        }
    });
}

@end
