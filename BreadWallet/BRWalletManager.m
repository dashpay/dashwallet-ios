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
#import "BRKey.h"
#import "BRKey+BIP38.h"
#import "BRBIP39Mnemonic.h"
#import "BRBIP32Sequence.h"
#import "BRTransaction.h"
#import "BRTransactionEntity.h"
#import "BRAddressEntity.h"
#import "NSString+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "NSManagedObject+Sugar.h"
#import "Reachability.h"
#import <LocalAuthentication/LocalAuthentication.h>

#define CIRCLE @"\xE2\x97\x8C" // dotted circle (utf-8)
#define DOT    @"\xE2\x97\x8F" // black circle (utf-8)

#define UNSPENT_URL @"https://blockchain.info/unspent?active="
#define TICKER_URL  @"https://bitpay.com/rates"

#define SEED_ENTROPY_LENGTH    (128/8)
#define SEC_ATTR_SERVICE       @"org.voisine.breadwallet"
#define DEFAULT_CURRENCY_PRICE 500.0
#define DEFAULT_CURRENCY_CODE  @"USD"
#define DEFAULT_SPENT_LIMIT    SATOSHIS

#if TX_FEE_0_8_RULES
#define DEFAULT_FEE_PER_KB     0 // use standard minimum fee instead
#else
#define DEFAULT_FEE_PER_KB     (TX_FEE_PER_KB*1100/247) // slightly higher than a typical 247byte tx with a 10bit fee
#endif

#define LOCAL_CURRENCY_CODE_KEY @"LOCAL_CURRENCY_CODE"
#define CURRENCY_CODES_KEY      @"CURRENCY_CODES"
#define CURRENCY_NAMES_KEY      @"CURRENCY_NAMES"
#define CURRENCY_PRICES_KEY     @"CURRENCY_PRICES"
#define SPEND_LIMIT_AMOUNT_KEY  @"SPEND_LIMIT_AMOUNT"
#define SECURE_TIME_KEY         @"SECURE_TIME"

#define MNEMONIC_KEY        @"mnemonic"
#define CREATION_TIME_KEY   @"creationtime"
#define MASTER_PUBKEY_KEY   @"masterpubkey"
#define SPEND_LIMIT_KEY     @"spendlimit"
#define PIN_KEY             @"pin"
#define PIN_FAIL_COUNT_KEY  @"pinfailcount"
#define PIN_FAIL_HEIGHT_KEY @"pinfailheight"
#define SEED_KEY            @"seed" // depreceated

static BOOL setKeychainData(NSData *data, NSString *key, BOOL authenticated)
{
    if (! key) return NO;

    id accessible = (authenticated) ? (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly :
                    (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key};
    
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL) == errSecItemNotFound) {
        if (! data) return YES;

        NSDictionary *item = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                               (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                               (__bridge id)kSecAttrAccount:key,
                               (__bridge id)kSecAttrAccessible:accessible,
                               (__bridge id)kSecValueData:data};
        OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        
        if (status == noErr) return YES;
        NSLog(@"SecItemAdd error status %d", (int)status);
        return NO;
    }
    
    if (! data) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

        if (status == noErr) return YES;
        NSLog(@"SecItemDelete error status %d", (int)status);
        return NO;
    }

    NSDictionary *update = @{(__bridge id)kSecAttrAccessible:accessible,
                             (__bridge id)kSecValueData:data};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
    
    if (status == noErr) return YES;
    NSLog(@"SecItemUpdate error status %d", (int)status);
    return NO;
}

static NSData *getKeychainData(NSString *key, NSError **error)
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:@YES};
    CFDataRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);

    if (status == errSecItemNotFound) return nil;
    if (status == noErr) return CFBridgingRelease(result);
    if (error) *error = [NSError errorWithDomain:@"BreadWallet" code:status
                         userInfo:@{NSLocalizedDescriptionKey:@"SecItemCopyMatching error"}];
    return nil;
}

static BOOL setKeychainInt(int64_t i, NSString *key, BOOL authenticated)
{
    @autoreleasepool {
        NSMutableData *d = [NSMutableData secureDataWithLength:sizeof(int64_t)];

        *(int64_t *)d.mutableBytes = i;
        return setKeychainData(d, key, authenticated);
    }
}

static int64_t getKeychainInt(NSString *key, NSError **error)
{
    @autoreleasepool {
        NSData *d = getKeychainData(key, error);

        return (d.length == sizeof(int64_t)) ? *(int64_t *)d.bytes : 0;
    }
}

static BOOL setKeychainString(NSString *s, NSString *key, BOOL authenticated)
{
    @autoreleasepool {
        NSData *d = (s) ? CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(), (CFStringRef)s,
                                                                                 kCFStringEncodingUTF8, 0)) : nil;
        
        return setKeychainData(d, key, authenticated);
    }
}

static NSString *getKeychainString(NSString *key, NSError **error)
{
    @autoreleasepool {
        NSData *d = getKeychainData(key, error);
        
        return (d) ? CFBridgingRelease(CFStringCreateFromExternalRepresentation(SecureAllocator(), (CFDataRef)d,
                                                                                kCFStringEncodingUTF8)) : nil;
    }
}

@interface BRWalletManager()

@property (nonatomic, strong) BRWallet *wallet;
@property (nonatomic, strong) id<BRKeySequence> sequence;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) NSArray *currencyPrices;
@property (nonatomic, assign) BOOL sweepFee;
@property (nonatomic, strong) NSString *sweepKey;
@property (nonatomic, strong) void (^sweepCompletion)(BRTransaction *tx, NSError *error);
@property (nonatomic, strong) UIAlertView *alertView;
@property (nonatomic, strong) UITextField *pinField;
@property (nonatomic, strong) NSMutableSet *failedPins;
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

    self.sequence = [BRBIP32Sequence new];
    self.reachability = [Reachability reachabilityForInternetConnection];
    self.failedPins = [NSMutableSet set];

    _format = [NSNumberFormatter new];
    self.format.lenient = YES;
    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
    self.format.negativeFormat = [self.format.positiveFormat
                                  stringByReplacingCharactersInRange:[self.format.positiveFormat rangeOfString:@"#"]
                                  withString:@"-#"];
    self.format.currencyCode = @"XBT";
    self.format.currencySymbol = BITS NARROW_NBSP;
    self.format.maximumFractionDigits = 2;
    self.format.minimumFractionDigits = 0; // iOS 8 bug, minimumFractionDigits now has to be set after currencySymbol
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
    
    if (self.protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    self.protectedObserver = nil;
    
    _currencyCodes = [defs arrayForKey:CURRENCY_CODES_KEY];
    _currencyNames = [defs arrayForKey:CURRENCY_NAMES_KEY];
    _currencyPrices = [defs arrayForKey:CURRENCY_PRICES_KEY];
    self.localCurrencyCode = ([defs stringForKey:LOCAL_CURRENCY_CODE_KEY]) ?
        [defs stringForKey:LOCAL_CURRENCY_CODE_KEY] : [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode];

    [self updateExchangeRate];
}

- (void)dealloc
{
    if (self.protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (BRWallet *)wallet
{
    if (_wallet) return _wallet;

    if (getKeychainData(SEED_KEY, nil)) { // upgrade from old keychain scheme
        NSLog(@"upgrading to authenticated keychain scheme");
        if (! setKeychainData([self.sequence masterPublicKeyFromSeed:self.seed], MASTER_PUBKEY_KEY, NO)) return _wallet;
        if (setKeychainData(getKeychainData(MNEMONIC_KEY, nil), MNEMONIC_KEY, YES)) setKeychainData(nil, SEED_KEY, NO);

        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"where's my passcode?", nil)
          message:NSLocalizedString(@"passcode or touch id is required to send or view balance", nil)
          delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    }
    
    if (! self.masterPublicKey) return _wallet;
    
    @synchronized(self) {
        if (_wallet) return _wallet;
            
        _wallet =
            [[BRWallet alloc] initWithContext:[NSManagedObject context] sequence:self.sequence
            masterPublicKey:self.masterPublicKey seed:^NSData *(NSString *authprompt, uint64_t amount) {
                return [self seedWithPrompt:authprompt forAmount:amount];
            }];

        _wallet.feePerKb = DEFAULT_FEE_PER_KB;
        
        // verify that keychain matches core data, with different access and backup policies it's possible to diverge
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BRKey *k = [BRKey keyWithPublicKey:[self.sequence publicKey:0 internal:NO
                                                masterPublicKey:self.masterPublicKey]];
                    
            if (_wallet.addresses.count > 0 && ! [_wallet containsAddress:k.address]) {
                NSLog(@"wallet doesn't contain address: %@", k.address);
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

// true if keychain is available and we know that no wallet exists on it
- (BOOL)noWallet
{
    NSError *error = nil;
    
    if (_wallet) return NO;
    if (getKeychainData(MASTER_PUBKEY_KEY, &error) || error) return NO;
    if (getKeychainData(SEED_KEY, &error) || error) return NO; // check for old keychain scheme
    return YES;
}

// master public key used to generate wallet addresses
- (NSData *)masterPublicKey
{
    return getKeychainData(MASTER_PUBKEY_KEY, nil);
}

- (NSData *)seed
{
    @autoreleasepool {
        NSString *phrase = getKeychainString(MNEMONIC_KEY, nil);
        
        if (phrase.length == 0) return nil;
        return [[BRBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:phrase withPassphrase:nil];
    }
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
        setKeychainData(nil, SPEND_LIMIT_KEY, NO);
        setKeychainData(nil, PIN_KEY, NO);
        setKeychainData(nil, PIN_FAIL_COUNT_KEY, NO);
        setKeychainData(nil, PIN_FAIL_HEIGHT_KEY, NO);
        
        if (! setKeychainString(seedPhrase, MNEMONIC_KEY, YES)) {
            NSLog(@"error setting wallet seed");

            if (seedPhrase) {
                [[[UIAlertView alloc] initWithTitle:@"couldn't create wallet"
                  message:@"error adding master private key to iOS keychain, make sure app has keychain entitlements"
                  delegate:self cancelButtonTitle:@"abort" otherButtonTitles:nil] show];
            }

            return;
        }
        
        NSData *masterPubKey = (seedPhrase) ? [self.sequence masterPublicKeyFromSeed:[m deriveKeyFromPhrase:seedPhrase
                                                                                      withPassphrase:nil]] : nil;
        
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

    return (d.length < sizeof(NSTimeInterval)) ? BIP39_CREATION_TIME : *(const NSTimeInterval *)d.bytes;
}

// true if touch id is enabled
- (BOOL)isTouchIdEnabled
{
    return ([LAContext class] &&
            [[LAContext new] canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:nil]) ? YES : NO;
}

// true if device passcode is enabled
- (BOOL)isPasscodeEnabled
{
    NSError *error = nil;
    
    if (! [LAContext class]) return YES; // we can only check for passcode on iOS 8 and above
    if ([[LAContext new] canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) return YES;
    return (error && error.code == LAErrorPasscodeNotSet) ? NO : YES;
}

// set this to enable basic floating fee calculation
- (void)setAverageBlockSize:(size_t)size
{
    _averageBlockSize = size;
#if TX_FEE_0_8_RULES
    return;
#endif

    // if average block size increases past 650kb, start increasing tx fee up to a max of 10x when block size hits 850kb
    // we want to increase the fee/kb to where we just beat a typical 247byte tx with a 100bit fee
    self.wallet.feePerKb = DEFAULT_FEE_PER_KB;
    if (size > 650*1000) self.wallet.feePerKb *= (size < 850*1000) ? 10*(size - 650*1000)/(200*1000) : 10;
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
- (NSData *)seedWithPrompt:(NSString *)authprompt forAmount:(uint64_t)amount
{
    BOOL touchid = (self.wallet.totalSent + amount < getKeychainInt(SPEND_LIMIT_KEY, nil)) ? YES : NO;

    if (! [self authenticateWithPrompt:authprompt andTouchId:touchid]) return nil;
    
    // BUG: if user manually chooses to enter pin, spending limit is reset without including the tx being authorized
    if (! touchid) setKeychainInt(self.wallet.totalSent + amount + self.spendingLimit, SPEND_LIMIT_KEY, NO);
    return self.seed;
}

// authenticates user and returns seedPhrase
- (NSString *)seedPhraseWithPrompt:(NSString *)authprompt
{
    return ([self authenticateWithPrompt:authprompt andTouchId:NO]) ? getKeychainString(MNEMONIC_KEY, nil) : nil;
}

#pragma mark - authentication

// prompts user to authenticate with touch id or passcode
- (BOOL)authenticateWithPrompt:(NSString *)authprompt andTouchId:(BOOL)touchId
{
    if (touchId && [LAContext class]) { // check if touch id framework is available
        LAContext *context = [LAContext new];
        NSError *error = nil;
        __block NSInteger authcode = 0;
        
        if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error] &&
            getKeychainInt(PIN_FAIL_COUNT_KEY, nil) == 0 && getKeychainInt(SPEND_LIMIT_KEY, nil) > 0) {
            context.localizedFallbackTitle = NSLocalizedString(@"passcode", nil);
            
            [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
            localizedReason:(authprompt ? authprompt : @" ") reply:^(BOOL success, NSError *error) {
                authcode = (success) ? 1 : error.code;
            }];
            
            while (authcode == 0) {
                [[NSRunLoop mainRunLoop] limitDateForMode:NSDefaultRunLoopMode];
            }
            
            if (authcode == LAErrorAuthenticationFailed) {
                setKeychainInt(0, SPEND_LIMIT_KEY, NO); // require pin entry for next spend
            }
            else if (authcode == 1) {
                self.didAuthenticate = YES;
                return YES;
            }
            else if (authcode == LAErrorUserCancel || authcode == LAErrorSystemCancel) return NO;
        }
        else if (error) NSLog(@"[LAContext canEvaluatePolicy:] %@", error.localizedDescription);
    }
    
    if ([self authenticatePinWithTitle:[NSString stringWithFormat:NSLocalizedString(@"passcode for %@", nil),
                                        DISPLAY_NAME] message:authprompt]) {
        [self.alertView dismissWithClickedButtonIndex:self.alertView.cancelButtonIndex animated:YES];
        [self hideKeyboard];
        return YES;
    }
    else return NO;
}

- (UITextField *)pinField
{
    if (_pinField) return _pinField;
    _pinField = [UITextField new];
    _pinField.alpha = 0.0;
    _pinField.font = [UIFont systemFontOfSize:0.1];
    _pinField.keyboardType = UIKeyboardTypeNumberPad;
    _pinField.secureTextEntry = YES;
    _pinField.delegate = self;
    return _pinField;
}

- (BOOL)authenticatePinWithTitle:(NSString *)title message:(NSString *)message
{
    NSError *error = nil;
    NSString *pin = getKeychainString(PIN_KEY, &error);

    if (error) return NO; // error reading pin from keychain
    if (pin.length != 4) return [self setPin]; // no pin set

    uint64_t failCount = getKeychainInt(PIN_FAIL_COUNT_KEY, nil);
    
    if (failCount >= 3) {
        uint64_t failHeight = getKeychainInt(PIN_FAIL_HEIGHT_KEY, nil);
        
        if (self.secureTime + NSTimeIntervalSince1970 < failHeight + pow(6, failCount - 3)*60.0) { // locked out
            NSTimeInterval wait = (failHeight + pow(6, failCount - 3)*60.0 -
                                   (self.secureTime + NSTimeIntervalSince1970))/60.0;
            NSString *unit = NSLocalizedString(@"minutes", nil);
            
            if (wait < 2.0) wait = 1.0, unit = NSLocalizedString(@"minute", nil);

            if (wait >= 60.0) {
                wait /= 60.0;
                unit = (wait < 2.0) ? NSLocalizedString(@"hour", nil) : NSLocalizedString(@"hours", nil);
            }
        
            if (! self.alertView.isVisible) {
                self.alertView = [UIAlertView new];
                [self.alertView addButtonWithTitle:NSLocalizedString(@"reset", nil)];
                [self.alertView addButtonWithTitle:NSLocalizedString(@"ok", nil)];
                self.alertView.cancelButtonIndex = 1;
            }
            
            [self.pinField resignFirstResponder];
            [self.alertView setValue:nil forKey:@"accessoryView"];
            self.alertView.title = NSLocalizedString(@"wallet disabled", nil);
            self.alertView.message = [NSString stringWithFormat:NSLocalizedString(@"\ntry again in %d %@", nil),
                                      (int)wait, unit];
            self.alertView.delegate = self;
            if (! self.alertView.isVisible) [self.alertView show];
            return NO;
        }
        
        message = [(failCount >= 7 ? NSLocalizedString(@"\n1 attempt remaining\n", nil) :
                    [NSString stringWithFormat:NSLocalizedString(@"\n%d attempts remaining\n", nil), 8 - failCount])
                   stringByAppendingString:(message) ? message : @""];
    }

    //TODO: replace all alert views with darkened initial warning screen type dialog
    self.alertView = [[UIAlertView alloc]
                      initWithTitle:[NSString stringWithFormat:CIRCLE @"\t" CIRCLE @"\t" CIRCLE @"\t" CIRCLE @"\n%@",
                                     (title) ? title : @""] message:message delegate:self
                      cancelButtonTitle:NSLocalizedString(@"cancel", nil) otherButtonTitles:nil];
    self.pinField = nil; // reset pinField so a new one is created
    [self.alertView setValue:self.pinField forKey:@"accessoryView"];
    [self.alertView show];
    [self.pinField becomeFirstResponder];
    
    for (;;) {
        while (self.alertView.visible && self.pinField.text.length < 4) {
            [[NSRunLoop mainRunLoop] limitDateForMode:NSDefaultRunLoopMode];
        }
        
        if (! self.alertView.visible) break;
        
        if ([self.pinField.text isEqual:pin]) { // successful pin attempt
            self.pinField.text = nil;
            [self.failedPins removeAllObjects];
            self.didAuthenticate = YES;
            setKeychainInt(0, PIN_FAIL_COUNT_KEY, NO);
            setKeychainInt(0, PIN_FAIL_HEIGHT_KEY, NO);
            if (self.spendingLimit > 0) setKeychainInt(self.wallet.totalSent + self.spendingLimit, SPEND_LIMIT_KEY, NO);
            return YES;
        }

        if (! [self.failedPins containsObject:self.pinField.text]) { // only count unique failed attempts
            if (++failCount >= 8) { // wipe wallet after 8 failed pin attempts and 24+ hours of lockout
                self.seedPhrase = nil;
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/10), dispatch_get_main_queue(), ^{
                    abort();
                });
                
                return NO;
            }

            setKeychainInt(failCount, PIN_FAIL_COUNT_KEY, NO);

            if (self.secureTime + NSTimeIntervalSince1970 > getKeychainInt(PIN_FAIL_HEIGHT_KEY, nil)) {
                setKeychainInt(self.secureTime + NSTimeIntervalSince1970, PIN_FAIL_HEIGHT_KEY, NO);
            }

            [self.failedPins addObject:self.pinField.text];
            if (failCount >= 3) return [self authenticatePinWithTitle:title message:message]; // wallet disabled
        }
        
        self.pinField.text = nil;
        
        // walking the view hierarchy is prone to breaking, but it's still functional even if the animation doesn't work
        UIView *v = self.pinField.superview.superview.superview;
        CGPoint p = v.center;
                
        [UIView animateWithDuration:0.05 delay:0.1 options:UIViewAnimationOptionCurveEaseInOut animations:^{ // shake
            v.center = CGPointMake(p.x + 30.0, p.y);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.2 initialSpringVelocity:0.0 options:0
            animations:^{ v.center = p; } completion:^(BOOL finished) {
                [self textField:self.pinField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
            }];
        }];
    }

    return NO;
}

// prompts the user to set or change their wallet pin and returns true if the pin was successfully set
- (BOOL)setPin
{
    NSError *error = nil;
    NSString *pin = getKeychainString(PIN_KEY, &error);
    NSString *title = [NSString stringWithFormat:CIRCLE @"\t" CIRCLE @"\t" CIRCLE @"\t" CIRCLE @"\n%@",
                       [NSString stringWithFormat:NSLocalizedString(@"choose passcode for %@", nil), DISPLAY_NAME]];

    if (error) return NO; // error reading existing pin from keychain

    if (pin.length == 4) {
        if (! [self authenticatePinWithTitle:NSLocalizedString(@"enter old passcode", nil) message:nil]) return NO;

        UIView *v = self.pinField.superview.superview.superview;
        CGPoint p = v.center;

        [UIView animateWithDuration:0.1 delay:0.1 options:UIViewAnimationOptionCurveEaseIn animations:^{
            v.center = CGPointMake(p.x - v.bounds.size.width, p.y);
        } completion:^(BOOL finished) {
            self.alertView.title = title;
            self.alertView.message = nil;
            v.center = CGPointMake(p.x + v.bounds.size.width*2, p.y);
            [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
             animations:^{ v.center = p; } completion:nil];
        }];
    }
    else {
        self.alertView = [[UIAlertView alloc] initWithTitle:title message:@" " delegate:self cancelButtonTitle:nil
                          otherButtonTitles:nil];
        self.pinField = nil; // reset pinField so a new one is created
        [self.alertView setValue:self.pinField forKey:@"accessoryView"];
        [self.alertView show];
        [self.pinField becomeFirstResponder];
    }
    
    for (;;) {
        while (self.alertView.visible && self.pinField.text.length < 4) {
            [[NSRunLoop mainRunLoop] limitDateForMode:NSDefaultRunLoopMode];
        }
    
        if (! self.alertView.visible) break;
        pin = self.pinField.text;
        self.pinField.text = nil;
        
        UIView *v = self.pinField.superview.superview.superview;
        CGPoint p = v.center;
        
        [UIView animateWithDuration:0.1 delay:0.1 options:UIViewAnimationOptionCurveEaseIn animations:^{ // verify pin
            v.center = CGPointMake(p.x - v.bounds.size.width, p.y);
        } completion:^(BOOL finished) {
            self.alertView.title = [NSString stringWithFormat:CIRCLE @"\t" CIRCLE @"\t" CIRCLE @"\t" CIRCLE @"\n%@",
                                    NSLocalizedString(@"verify passcode", nil)];
            v.center = CGPointMake(p.x + v.bounds.size.width*2, p.y);
            [self textField:self.pinField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
            [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
             animations:^{ v.center = p; } completion:nil];
        }];

        while (self.alertView.visible && self.pinField.text.length < 4) {
            [[NSRunLoop mainRunLoop] limitDateForMode:NSDefaultRunLoopMode];
        }

        if (! self.alertView.visible) break;
    
        if ([self.pinField.text isEqual:pin]) {
            self.pinField.text = nil;
            setKeychainString(pin, PIN_KEY, NO);
            [self.alertView dismissWithClickedButtonIndex:self.alertView.cancelButtonIndex animated:YES];
            [self hideKeyboard];
            return YES;
        }
        
        self.pinField.text = nil;
        
        [UIView animateWithDuration:0.05 delay:0.1 options:UIViewAnimationOptionCurveEaseInOut animations:^{ // shake
            v.center = CGPointMake(p.x + 30.0, p.y);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.2 initialSpringVelocity:0.0 options:0
            animations:^{ v.center = p; } completion:^(BOOL finished) {
                self.alertView.title = title;
                [self textField:self.pinField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
            }];
        }];
    }
    
    return NO;
}

// amount that can be spent using touch id without pin entry
- (uint64_t)spendingLimit
{
    // it's ok to store this in userdefaults because increasing the value only takes effect after successful pin entry
    if (! [[NSUserDefaults standardUserDefaults] objectForKey:SPEND_LIMIT_AMOUNT_KEY]) return SATOSHIS;
    return [[NSUserDefaults standardUserDefaults] doubleForKey:SPEND_LIMIT_AMOUNT_KEY] + DBL_EPSILON;
}

- (void)setSpendingLimit:(uint64_t)spendingLimit
{
    if (setKeychainInt((spendingLimit > 0) ? self.wallet.totalSent + spendingLimit : 0, SPEND_LIMIT_KEY, NO)) {
        [[NSUserDefaults standardUserDefaults] setDouble:spendingLimit forKey:SPEND_LIMIT_AMOUNT_KEY];
    }
}

// last known time from an ssl server connection
- (NSTimeInterval)secureTime
{
    return [[NSUserDefaults standardUserDefaults] doubleForKey:SECURE_TIME_KEY];
}

// the keyboard can take a second or more to dismiss, this hides it quickly to improve perceived response time
- (void)hideKeyboard
{
    for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
        if (w.windowLevel == UIWindowLevelNormal || w.windowLevel == UIWindowLevelAlert ||
            w.windowLevel == UIWindowLevelStatusBar) continue;
        [UIView animateWithDuration:0.2 animations:^{ w.alpha = 0; }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ w.alpha = 1; });
        break;
    }
}

#pragma mark - exchange rate

// local currency ISO code
- (void)setLocalCurrencyCode:(NSString *)code
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSUInteger i = [_currencyCodes indexOfObject:code];
    
    if (i == NSNotFound) code = DEFAULT_CURRENCY_CODE, i = [_currencyCodes indexOfObject:DEFAULT_CURRENCY_CODE];
    _localCurrencyCode = [code copy];
    _localCurrencyPrice = (i < _currencyPrices.count) ? [_currencyPrices[i] doubleValue] : DEFAULT_CURRENCY_PRICE;
    self.localFormat.currencyCode = _localCurrencyCode;
    self.localFormat.maximum = @((MAX_MONEY/SATOSHIS)*_localCurrencyPrice);
    
    if ([self.localCurrencyCode isEqual:[[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode]]) {
        [defs removeObjectForKey:LOCAL_CURRENCY_CODE_KEY];
    }
    else [defs setObject:self.localCurrencyCode forKey:LOCAL_CURRENCY_CODE_KEY];
    
    if (! _wallet) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletBalanceChangedNotification object:nil];
    });
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
        NSMutableArray *codes = [NSMutableArray array], *names = [NSMutableArray array], *rates =[NSMutableArray array];
        
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) { // store server timestamp
            NSString *date = [(NSHTTPURLResponse *)response allHeaderFields][@"Date"];
            NSTimeInterval now = [[[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:nil]
                                   matchesInString:date options:0 range:NSMakeRange(0, date.length)].lastObject
                                  date].timeIntervalSinceReferenceDate;
            
            if (now > self.secureTime) [defs setDouble:now forKey:SECURE_TIME_KEY];
        }

        if (error || ! [json isKindOfClass:[NSDictionary class]] || ! [json[@"data"] isKindOfClass:[NSArray class]]) {
            NSLog(@"unexpected response from %@:\n%@", req.URL.host,
                  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            return;
        }
        
        for (NSDictionary *d in json[@"data"]) {
            if (! [d isKindOfClass:[NSDictionary class]] || ! [d[@"code"] isKindOfClass:[NSString class]] ||
                ! [d[@"name"] isKindOfClass:[NSString class]] || ! [d[@"rate"] isKindOfClass:[NSNumber class]]) {
                NSLog(@"unexpected response from %@:\n%@", req.URL.host,
                      [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                return;
            }
           
            if ([d[@"code"] isEqual:@"BTC"]) continue;
            [codes addObject:d[@"code"]];
            [names addObject:d[@"name"]];
            [rates addObject:d[@"rate"]];
        }

        _currencyCodes = codes;
        _currencyNames = names;
        _currencyPrices = rates;
        self.localCurrencyCode = _localCurrencyCode;

        [defs setObject:self.currencyCodes forKey:CURRENCY_CODES_KEY];
        [defs setObject:self.currencyNames forKey:CURRENCY_NAMES_KEY];
        [defs setObject:self.currencyPrices forKey:CURRENCY_PRICES_KEY];
        [defs synchronize];
        
        NSLog(@"exchange rate updated to %@/%@", [self localCurrencyStringForAmount:SATOSHIS],
              [self stringForAmount:SATOSHIS]);
    }];
}

#pragma mark - sweep private key

// given a private key, queries blockchain for unspent outputs and calls the completion block with a signed transaction
// that will sweep the balance into the wallet (doesn't publish the tx)
- (void)sweepPrivateKey:(NSString *)privKey withFee:(BOOL)fee
completion:(void (^)(BRTransaction *tx, NSError *error))completion
{
    if (! completion) return;

    if ([privKey isValidBitcoinBIP38Key]) {
        UIAlertView *v = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"password protected key", nil)
                          message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                          otherButtonTitles:NSLocalizedString(@"ok", nil), nil];

        v.alertViewStyle = UIAlertViewStyleSecureTextInput;
        [v textFieldAtIndex:0].returnKeyType = UIReturnKeyDone;
        [v textFieldAtIndex:0].placeholder = NSLocalizedString(@"password", nil);
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
        uint64_t balance = 0, feeAmount = 0;
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
        if (fee) feeAmount = [self.wallet feeForTxSize:tx.size + 34];

        if (feeAmount + TX_MIN_OUTPUT_AMOUNT > balance) {
            completion(nil, [NSError errorWithDomain:@"BreadWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             NSLocalizedString(@"transaction fees would cost more than the funds available on this "
                                               "private key (due to tiny \"dust\" deposits)",nil)}]);
            return;
        }

        [tx addOutputAddress:[self.wallet changeAddress] amount:balance - feeAmount];

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
            (self.format.maximumFractionDigits > 4) ? 4 : self.format.maximumFractionDigits;
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
                     pow(10.0, self.localFormat.maximumFractionDigits),
            overflowbits = 0;

    if (local == 0) return 0;
    while (llabs(local) + 1 > INT64_MAX/SATOSHIS) local /= 2, overflowbits++; // make sure we won't overflow an int64_t

    int64_t min = llabs(local)*SATOSHIS/
                  (int64_t)(self.localCurrencyPrice*pow(10.0, self.localFormat.maximumFractionDigits)) + 1,
            max = (llabs(local) + 1)*SATOSHIS/
                  (int64_t)(self.localCurrencyPrice*pow(10.0, self.localFormat.maximumFractionDigits)) - 1,
            amount = (min + max)/2, p = 10;

    while (overflowbits > 0) local *= 2, min *= 2, max *= 2, amount *= 2, overflowbits--;
    if (amount >= MAX_MONEY) return (local < 0) ? -MAX_MONEY : MAX_MONEY;

    while ((amount/p)*p >= min && p <= INT64_MAX/10) { // find lowest decimal precision matching local currency string
        p *= 10;
    }

    p /= 10;
    return (local < 0) ? -(amount/p)*p : (amount/p)*p;
}

- (NSString *)localCurrencyStringForAmount:(int64_t)amount
{
    if (amount == 0) return [self.localFormat stringFromNumber:@(0)];

    NSString *ret = [self.localFormat stringFromNumber:@(self.localCurrencyPrice*amount/SATOSHIS)];

    // if the amount is too small to be represented in local currency (but is != 0) then return a string like "$0.01"
    if (amount > 0 && self.localCurrencyPrice*amount/SATOSHIS + DBL_EPSILON <
        0.9/pow(10.0, self.localFormat.maximumFractionDigits)) {
        ret = [self.localFormat stringFromNumber:@(1.0/pow(10.0, self.localFormat.maximumFractionDigits))];
    }
    else if (amount < 0 && self.localCurrencyPrice*amount/SATOSHIS - DBL_EPSILON >
             -0.9/pow(10.0, self.localFormat.maximumFractionDigits)) {
        ret = [self.localFormat stringFromNumber:@(-1.0/pow(10.0, self.localFormat.maximumFractionDigits))];
    }

    return ret;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    NSUInteger l = textField.text.length + string.length - range.length;

    self.alertView.title = [NSString stringWithFormat:@"%@\t%@\t%@\t%@%@", (l > 0 ? DOT : CIRCLE),
                            (l > 1 ? DOT : CIRCLE), (l > 2 ? DOT : CIRCLE), (l > 3 ? DOT : CIRCLE),
                            [self.alertView.title substringFromIndex:7]];
    return YES;
}

// iOS 7 doesn't adjust the alertView position to account for the keyboard when using an accessoryView
- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    if ([LAContext class]) return; // fix is needed for iOS 7 only
    
    textField.superview.superview.superview.superview.superview.center =
        CGPointMake([UIScreen mainScreen].bounds.size.width/2.0, [UIScreen mainScreen].bounds.size.height/2.0 - 108.0);
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    BRBIP39Mnemonic *m = [BRBIP39Mnemonic sharedInstance];
    
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        if ([textView.text rangeOfString:@"\n"].location != NSNotFound) {
            textView.text = [m normalizePhrase:textView.text];
            
            if (! [m phraseIsValid:[m normalizePhrase:textView.text]]) {
                self.alertView.title = NSLocalizedString(@"bad recovery phrase", nil);
                [self.alertView performSelector:@selector(setTitle:)
                 withObject:NSLocalizedString(@"recovery phrase", nil) afterDelay:3.0];
            }
            else if (! [[m normalizePhrase:textView.text] isEqual:getKeychainString(MNEMONIC_KEY, nil)]) {
                self.alertView.title = NSLocalizedString(@"recovery phrase doesn't match", nil);
                [self.alertView performSelector:@selector(setTitle:)
                 withObject:NSLocalizedString(@"recovery phrase", nil) afterDelay:3.0];
            }
            else {
                setKeychainData(nil, SPEND_LIMIT_KEY, NO);
                setKeychainData(nil, PIN_KEY, NO);
                setKeychainData(nil, PIN_FAIL_COUNT_KEY, NO);
                setKeychainData(nil, PIN_FAIL_HEIGHT_KEY, NO);
                [self.alertView dismissWithClickedButtonIndex:0 animated:YES];
                [self performSelector:@selector(setPin) withObject:nil afterDelay:0.0];
            }
        }
    }
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    if ([LAContext class]) return; // fix is needed for iOS 7 only
    
    textView.superview.superview.superview.superview.superview.center =
        CGPointMake([UIScreen mainScreen].bounds.size.width/2.0, [UIScreen mainScreen].bounds.size.height/2.0 - 108.0);
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [NSObject cancelPreviousPerformRequestsWithTarget:alertView];
    if (alertView == self.alertView) self.alertView = nil;
    if (self.pinField.isFirstResponder) [self hideKeyboard];
    
    if (buttonIndex == alertView.cancelButtonIndex) {
        if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:@"abort"]) abort();

        if (self.sweepCompletion) self.sweepCompletion(nil, nil);
        self.sweepKey = nil;
        self.sweepCompletion = nil;
    }
    else if (self.sweepKey && self.sweepCompletion) {
        NSString *passphrase = [[alertView textFieldAtIndex:0] text];

        dispatch_async(dispatch_get_main_queue(), ^{
            BRKey *key = [BRKey keyWithBIP38Key:self.sweepKey andPassphrase:passphrase];

            if (! key) {
                UIAlertView *v = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"password protected key", nil)
                                  message:NSLocalizedString(@"bad password, try again", nil) delegate:self
                                  cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                                  otherButtonTitles:NSLocalizedString(@"ok", nil), nil];

                v.alertViewStyle = UIAlertViewStyleSecureTextInput;
                [v textFieldAtIndex:0].returnKeyType = UIReturnKeyDone;
                [v textFieldAtIndex:0].placeholder = NSLocalizedString(@"password", nil);
                [v show];
            }
            else {
                [self sweepPrivateKey:key.privateKey withFee:self.sweepFee completion:self.sweepCompletion];
                self.sweepKey = nil;
                self.sweepCompletion = nil;
            }
        });
    }
    else if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:NSLocalizedString(@"reset", nil)]) {
        UITextView *t = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 260, 180)];
            
        t.keyboardType = UIKeyboardTypeASCIICapable;
        t.returnKeyType = UIReturnKeyDone;
        t.delegate = self;
        t.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
        self.alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"recovery phrase", nil) message:nil
                          delegate:nil cancelButtonTitle:NSLocalizedString(@"cancel", nil) otherButtonTitles:nil];
        [self.alertView setValue:t forKey:@"accessoryView"];
        [self.alertView show];
        [t becomeFirstResponder];
    }
}

@end
