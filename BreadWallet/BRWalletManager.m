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

#define LOCAL_CURRENCY_SYMBOL_KEY @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY   @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY  @"LOCAL_CURRENCY_PRICE"
#define CURRENCY_CODES_KEY        @"CURRENCY_CODES"
#define PIN_KEY                   @"pin"
#define PIN_FAIL_COUNT_KEY        @"pinfailcount"
#define PIN_FAIL_HEIGHT_KEY       @"pinfailheight"
#define MNEMONIC_KEY              @"mnemonic"
#define SEED_KEY                  @"seed"
#define CREATION_TIME_KEY         @"creationtime"

#define SEED_ENTROPY_LENGTH     (128/8)
#define SEC_ATTR_SERVICE        @"org.voisine.breadwallet"
#define DEFAULT_CURRENCY_PRICE  500.0
#define DEFAULT_CURRENCY_CODE   @"USD"
#define DEFAULT_CURRENCY_SYMBOL @"$"

#define BASE_URL    @"https://blockchain.info"
#define UNSPENT_URL BASE_URL "/unspent?active="
#define TICKER_URL  BASE_URL "/ticker"

static BOOL setKeychainData(NSData *data, NSString *key)
{
    if (! key) return NO;

    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:(id)kCFBooleanTrue};

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
                            (__bridge id)kSecReturnData:(id)kCFBooleanTrue};
    CFDataRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);

    if (status != noErr) {
        NSLog(@"SecItemCopyMatching error status %d", (int)status);
        return nil;
    }

    return CFBridgingRelease(result);
}

@interface BRWalletManager()

@property (nonatomic, strong) BRWallet *wallet;
@property (nonatomic, strong) id<BRKeySequence> sequence;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, assign) BOOL sweepFee;
@property (nonatomic, strong) NSString *sweepKey;
@property (nonatomic, strong) void (^sweepCompletion)(BRTransaction *tx, NSError *error);

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
    self.format.minimumFractionDigits = 0;
    self.format.negativeFormat = [self.format.positiveFormat
                                  stringByReplacingCharactersInRange:[self.format.positiveFormat rangeOfString:@"#"]
                                  withString:@"-#"];
    self.format.currencyCode = @"XBT";
    self.format.currencySymbol = BITS NARROW_NBSP;
    self.format.maximumFractionDigits = 2;
//    self.format.currencySymbol = BTC NARROW_NBSP;
//    self.format.maximumFractionDigits = 8;

    self.format.maximum = @(MAX_MONEY/(int64_t)pow(10.0, self.format.maximumFractionDigits));

    _localFormat = [NSNumberFormatter new];
    self.localFormat.lenient = YES;
    self.localFormat.numberStyle = NSNumberFormatterCurrencyStyle;
    self.localFormat.negativeFormat = self.format.negativeFormat;

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

    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (BRWallet *)wallet
{
    if (_wallet == nil && self.seed) {
        @synchronized(self) {
            if (_wallet == nil) {
                _wallet = [[BRWallet alloc] initWithContext:[NSManagedObject context] sequence:self.sequence
                           seed:^NSData *{ return self.seed; }];

                // we need to verify that the keychain matches core data, since they have different access and backup
                // policies it's possible for them to diverge
                if (_wallet.addresses.count > 0) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        BRKey *k = [BRKey keyWithPrivateKey:[self.sequence privateKey:0 internal:NO
                                                             fromSeed:self.seed]];
                    
                        if (! [_wallet containsAddress:k.address]) {
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
                                [[NSNotificationCenter defaultCenter]
                                 postNotificationName:BRWalletManagerSeedChangedNotification object:nil];
                                [[NSNotificationCenter defaultCenter]
                                 postNotificationName:BRWalletBalanceChangedNotification object:nil];
                            });
                        }
                    });
                }
            }
        }
    }

    return _wallet;
}

- (id<BRKeySequence>)sequence
{
    if (! _sequence) _sequence = [BRBIP32Sequence new];
    return _sequence;
}

- (NSData *)seed
{
    return getKeychainData(SEED_KEY);
}

- (void)setSeed:(NSData *)seed
{
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        if ([seed isEqual:self.seed]) return;

        [[NSManagedObject context] performBlockAndWait:^{
            [BRAddressEntity deleteObjects:[BRAddressEntity allObjects]];
            [BRTransactionEntity deleteObjects:[BRTransactionEntity allObjects]];
            [NSManagedObject saveContext];
        }];

        setKeychainData(nil, PIN_KEY);
        setKeychainData(nil, PIN_FAIL_COUNT_KEY);
        setKeychainData(nil, PIN_FAIL_HEIGHT_KEY);
        setKeychainData(nil, MNEMONIC_KEY);
        setKeychainData(nil, CREATION_TIME_KEY);
        
        if (! setKeychainData(seed, SEED_KEY)) {
            NSLog(@"error setting wallet seed");
            [[[UIAlertView alloc] initWithTitle:@"couldn't create wallet"
              message:@"error adding master private key to iOS keychain, make sure app has keychain entitlements"
              delegate:self cancelButtonTitle:@"abort" otherButtonTitles:nil] show];
            return;
        }

        _wallet = nil;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletManagerSeedChangedNotification object:nil];
    });
}

- (NSString *)seedPhrase
{
    @autoreleasepool {
        NSData *phrase = getKeychainData(MNEMONIC_KEY);

        if (! phrase) return nil;

        return CFBridgingRelease(CFStringCreateFromExternalRepresentation(SecureAllocator(), (CFDataRef)phrase,
                                                                          kCFStringEncodingUTF8));
    }
}

- (void)setSeedPhrase:(NSString *)seedPhrase
{
    @autoreleasepool {
        BRBIP39Mnemonic *m = [BRBIP39Mnemonic sharedInstance];
        
        seedPhrase = [m encodePhrase:[m decodePhrase:seedPhrase]];
        self.seed = [m deriveKeyFromPhrase:seedPhrase withPassphrase:nil];

        NSData *d = CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(), (CFStringRef)seedPhrase,
                                                                           kCFStringEncodingUTF8, 0));
        
        setKeychainData(d, MNEMONIC_KEY);
    }
}

- (NSString *)pin
{
    @autoreleasepool {
        NSData *pin = getKeychainData(PIN_KEY);

        if (! pin) return nil;

        return CFBridgingRelease(CFStringCreateFromExternalRepresentation(SecureAllocator(), (CFDataRef)pin,
                                                                          kCFStringEncodingUTF8));
    }
}

- (void)setPin:(NSString *)pin
{
    @autoreleasepool {
        if (pin.length > 0) {
            NSData *d = CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(), (CFStringRef)pin,
                                                                               kCFStringEncodingUTF8, 0));

            setKeychainData(d, PIN_KEY);
        }
        else setKeychainData(nil, PIN_KEY);
    }
}

- (NSUInteger)pinFailCount
{
        NSData *count = getKeychainData(PIN_FAIL_COUNT_KEY);

        return (count.length < sizeof(NSUInteger)) ? 0 : *(const NSUInteger *)count.bytes;
}

- (void)setPinFailCount:(NSUInteger)count
{
    NSMutableData *d = [NSMutableData secureDataWithLength:sizeof(NSUInteger)];

    *(NSUInteger *)d.mutableBytes = count;
    setKeychainData(d, PIN_FAIL_COUNT_KEY);
}

- (uint32_t)pinFailHeight
{
    NSData *height = getKeychainData(PIN_FAIL_HEIGHT_KEY);

    return (height.length < sizeof(uint32_t)) ? 0 : *(const uint32_t *)height.bytes;
}

- (void)setPinFailHeight:(uint32_t)height
{
    NSMutableData *d = [NSMutableData secureDataWithLength:sizeof(uint32_t)];

    *(uint32_t *)d.mutableBytes = height;
    setKeychainData(d, PIN_FAIL_HEIGHT_KEY);
}

- (void)generateRandomSeed
{
    @autoreleasepool {
        NSMutableData *entropy = [NSMutableData secureDataWithLength:SEED_ENTROPY_LENGTH];
        NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];

        SecRandomCopyBytes(kSecRandomDefault, entropy.length, entropy.mutableBytes);

        self.seedPhrase = [[BRBIP39Mnemonic sharedInstance] encodePhrase:entropy];

        // we store the wallet creation time on the keychain because keychain data persists even when an app is deleted
        setKeychainData([NSData dataWithBytes:&time length:sizeof(time)], CREATION_TIME_KEY);
    }
}

- (NSTimeInterval)seedCreationTime
{
    NSData *d = getKeychainData(CREATION_TIME_KEY);

    return (d.length < sizeof(NSTimeInterval)) ? BITCOIN_REFERENCE_BLOCK_TIME : *(const NSTimeInterval *)d.bytes;
}

- (void)setLocalCurrencyCode:(NSString *)localCurrencyCode
{
    _localCurrencyCode = [localCurrencyCode copy];
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
            self.localFormat.currencySymbol = DEFAULT_CURRENCY_SYMBOL;
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
