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
#import <LocalAuthentication/LocalAuthentication.h>

#define BTC         @"\xC9\x83"     // capital B with stroke (utf-8)
#define BITS        @"\xC6\x80"     // lowercase b with stroke (utf-8)
#define NARROW_NBSP @"\xE2\x80\xAF" // narrow no-break space (utf-8)
#define LDQUOTE     @"\xE2\x80\x9C" // left double quote (utf-8)
#define RDQUOTE     @"\xE2\x80\x9D" // right double quote (utf-8)
#define CIRCLE      @"\xE2\x97\x8C" // dotted circle (utf-8)
#define DOT         @"\xE2\x97\x8F" // black circle (utf-8)

#define BASE_URL    @"https://blockchain.info"
#define UNSPENT_URL BASE_URL "/unspent?active="
#define TICKER_URL  BASE_URL "/ticker"

#define SEED_ENTROPY_LENGTH    (128/8)
#define SEC_ATTR_SERVICE       @"org.voisine.breadwallet"
#define DEFAULT_CURRENCY_PRICE 500.0
#define DEFAULT_CURRENCY_CODE  @"USD"
#define DEFAULT_SPENT_LIMIT    SATOSHIS
#define DISPLAY_NAME           [NSString stringWithFormat:LDQUOTE @"%@" RDQUOTE,\
                                NSBundle.mainBundle.infoDictionary[@"CFBundleDisplayName"]]

#define LOCAL_CURRENCY_SYMBOL_KEY @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY   @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY  @"LOCAL_CURRENCY_PRICE"
#define CURRENCY_CODES_KEY        @"CURRENCY_CODES"
#define SPEND_LIMIT_AMOUNT_KEY    @"SPEND_LIMIT_AMOUNT"
#define SECURE_TIME_KEY           @"SECURE_TIME"

#define MNEMONIC_KEY        @"mnemonic"
#define CREATION_TIME_KEY   @"creationtime"
#define MASTER_PUBKEY_KEY   @"masterpubkey"
#define SPEND_LIMIT_KEY     @"spendlimit"
#define PIN_KEY             @"pin"
#define PIN_FAIL_COUNT_KEY  @"pinfailcount"
#define PIN_FAIL_HEIGHT_KEY @"pinfailheight"

// depreceated
#define SEED_KEY            @"seed"


static BOOL isPasscodeEnabled()
{
    NSError *error = nil;

    if (! [LAContext class]) return YES; // we can only check for passcode on iOS 8 and above
    if ([[LAContext new] canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) return YES;
    return (error && error.code == LAErrorPasscodeNotSet) ? NO : YES;
}

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

static NSData *getKeychainData(NSString *key)
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:@YES};
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
    
    NSLog(@"SecItemCopyMatching error status %d", (int)status);
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

static int64_t getKeychainInt(NSString *key)
{
    @autoreleasepool {
        NSData *d = getKeychainData(key);

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

static NSString *getKeychainString(NSString *key)
{
    @autoreleasepool {
        NSData *d = getKeychainData(key);
        
        return (d) ? CFBridgingRelease(CFStringCreateFromExternalRepresentation(SecureAllocator(), (CFDataRef)d,
                                                                                kCFStringEncodingUTF8)) : nil;
    }
}

@interface BRWalletManager()

@property (nonatomic, strong) BRWallet *wallet;
@property (nonatomic, strong) id<BRKeySequence> sequence;
@property (nonatomic, strong) Reachability *reachability;
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

    self.failedPins = [NSMutableSet set];
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

    if (getKeychainData(SEED_KEY)) { // upgrade from old keychain scheme
        NSLog(@"upgrading to authenticated keychain scheme");
        setKeychainData([self.sequence masterPublicKeyFromSeed:self.seed], MASTER_PUBKEY_KEY, NO);
        self.didAuthenticate = NO;

        if (setKeychainData(getKeychainData(MNEMONIC_KEY), MNEMONIC_KEY, YES)) {
            setKeychainData(nil, SEED_KEY, NO);
        }
        else if (! self.passcodeEnabled) return nil;
    }
    
    if (! self.masterPublicKey) return _wallet;
    
    @synchronized(self) {
        if (_wallet) return _wallet;
            
        _wallet =
            [[BRWallet alloc] initWithContext:[NSManagedObject context] sequence:self.sequence
            masterPublicKey:self.masterPublicKey seed:^NSData *(NSString *authprompt, uint64_t amount) {
                return [self seedWithPrompt:authprompt forAmount:amount];
            }];

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

// master public key used to generate wallet addresses
- (NSData *)masterPublicKey
{
    return getKeychainData(MASTER_PUBKEY_KEY);
}

- (NSData *)seed
{
    @autoreleasepool {
        BRBIP39Mnemonic *m = [BRBIP39Mnemonic sharedInstance];
        NSString *phrase = getKeychainString(MNEMONIC_KEY);
        
        if (phrase.length == 0) return nil;
        return [m deriveKeyFromPhrase:phrase withPassphrase:nil];
    }
}

// requesting seedPhrase will trigger authentication
- (NSString *)seedPhrase
{
    return getKeychainString(MNEMONIC_KEY);
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
    NSData *d = getKeychainData(CREATION_TIME_KEY);

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
- (NSData *)seedWithPrompt:(NSString *)authprompt forAmount:(uint64_t)amount
{
    BOOL touchid = (self.wallet.totalSent + amount >= getKeychainInt(SPEND_LIMIT_KEY)) ? YES : NO;

    if (! [self authenticateWithPrompt:authprompt andTouchId:touchid]) return nil;
    
    // BUG: if user manually chooses to enter pin, spending limit is reset without including the tx being authorized
    if (! touchid) setKeychainInt(self.wallet.totalSent + amount + self.spendingLimit, SPEND_LIMIT_KEY, NO);
    return self.seed;
}

// prompts user to authenticate with touch id or passcode
- (BOOL)authenticateWithPrompt:(NSString *)authprompt andTouchId:(BOOL)touchId
{
    if (touchId && [LAContext class]) { // check if touch id framework is available
        LAContext *context = [LAContext new];
        NSError *error = nil;
        __block NSInteger authcode = 0;
        
        if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
            context.localizedFallbackTitle = NSLocalizedString(@"enter passcode", nil);
            
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
    
    if ([self authenticatePinWithTitle:[NSString stringWithFormat:NSLocalizedString(@"\npasscode for %@", nil),
                                        DISPLAY_NAME] message:authprompt]) {
        if (self.alertView.visible) {
            [self.alertView dismissWithClickedButtonIndex:self.alertView.cancelButtonIndex animated:YES];
            [self.pinField performSelector:@selector(resignFirstResponder) withObject:nil afterDelay:0.1];
        }
        
        self.didAuthenticate = YES;
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
    NSString *pin = getKeychainString(PIN_KEY);
    uint64_t failCount = getKeychainInt(PIN_FAIL_COUNT_KEY), failHeight = getKeychainInt(PIN_FAIL_HEIGHT_KEY);

    if (pin.length != 4) { // no pin set
        return [self setPin];
    }
    else if (failCount >= 3) {
        if (self.secureTime + NSTimeIntervalSince1970 < failHeight + pow(6, failCount - 3)*60.0) { // locked out
            NSTimeInterval wait = (failHeight + pow(6, failCount - 3)*60.0 -
                                   (self.secureTime + NSTimeIntervalSince1970))/60.0;
            NSString *unit = NSLocalizedString(@"minutes", nil);
            
            if (wait < 2.0) wait = 1.0, unit = NSLocalizedString(@"minute", nil);
            if (wait >= 60.0) wait /= 60.0, unit = NSLocalizedString((wait < 2.0) ? @"hour" : @"hours", nil);
        
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"wallet disabled", nil)
              message:[NSString stringWithFormat:NSLocalizedString(@"\ntry again in %d %@", nil), (int)wait, unit]
              delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            return NO;
        }
        else if (failCount < 7) {
            message = [NSString stringWithFormat:NSLocalizedString(@"\n%d attempts remaining\n%@", nil), 8 - failCount,
                       message ? message : @""];
        }
        else {
            message = [NSString stringWithFormat:NSLocalizedString(@"\n1 attempt remaining\n%@", nil),
                       message ? message : @""];
        }
    }

    self.alertView = [[UIAlertView alloc]
                      initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"%@\t%@\t%@\t%@%@", nil), CIRCLE,
                                     CIRCLE, CIRCLE, CIRCLE, (title) ? title : @""] message:message delegate:self
                      cancelButtonTitle:@"Cancel" otherButtonTitles:nil];
    self.pinField = nil;
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
            setKeychainInt(self.wallet.totalSent + self.spendingLimit, SPEND_LIMIT_KEY, NO);
            return YES;
        }

        if (! [self.failedPins containsObject:self.pinField.text]) { // only count unique failed attempts
            if (failCount == 7) { // wipe wallet after 8 failed pin attempts and 24+ hours of lockout
                self.seedPhrase = nil;
                abort();
            }

            [self.failedPins addObject:self.pinField.text];
            setKeychainInt(++failCount, PIN_FAIL_COUNT_KEY, NO);

            if (self.secureTime + NSTimeIntervalSince1970 > failHeight) {
                setKeychainInt(self.secureTime + NSTimeIntervalSince1970, PIN_FAIL_HEIGHT_KEY, NO);
            }
        }
        
        self.pinField.text = nil;
        
        // walking the view hierarchy is prone to breaking, but it's still functional even if the animation doesn't work
        UIView *v = self.pinField.superview.superview.superview;
            
        [UIView animateWithDuration:0.05 delay:0.1 options:UIViewAnimationOptionCurveEaseInOut animations:^{ // shake
            v.center = CGPointMake(v.center.x + 30.0, v.center.y);
        } completion:^(BOOL finished) {
            [self textField:self.pinField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.2 initialSpringVelocity:0.0 options:0
            animations:^{ v.center = CGPointMake(v.center.x - 30.0, v.center.y); } completion:nil];

            if (failCount >= 3) {
                [self.alertView dismissWithClickedButtonIndex:self.alertView.cancelButtonIndex animated:YES];
            }
        }];
    }

    [self.pinField performSelector:@selector(resignFirstResponder) withObject:nil afterDelay:0.1];
    return NO;
}

// prompts the user to set or change their wallet pin and returns true if the pin was successfully set
- (BOOL)setPin
{
    NSString *pin = getKeychainString(PIN_KEY);

    if (pin.length == 4) {
        if (! [self authenticatePinWithTitle:nil message:NSLocalizedString(@"\nenter old passcode", nil)]) {
            [self.alertView dismissWithClickedButtonIndex:self.alertView.cancelButtonIndex animated:YES];
            return NO;
        }

        UIView *v = self.pinField.superview.superview.superview;

        [UIView animateWithDuration:0.1 delay:0.1 options:UIViewAnimationOptionCurveEaseIn animations:^{
            v.center = CGPointMake(v.center.x - v.bounds.size.width, v.center.y);
        } completion:^(BOOL finished) {
            v.center = CGPointMake(v.center.x + v.bounds.size.width*2, v.center.y);
            self.alertView.message = NSLocalizedString(@"\nchoose passcode", nil);
            [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
             animations:^{ v.center = CGPointMake(v.center.x - v.bounds.size.width, v.center.y); } completion:nil];
        }];
    }
    else {
        self.alertView = [[UIAlertView alloc]
                          initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"%@\t%@\t%@\t%@", nil), CIRCLE,
                                         CIRCLE, CIRCLE, CIRCLE] message:NSLocalizedString(@"\nchoose passcode", nil)
                          delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:nil];
        self.pinField = nil;
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
        
        [UIView animateWithDuration:0.1 delay:0.1 options:UIViewAnimationOptionCurveEaseIn animations:^{ // verify pin
            v.center = CGPointMake(v.center.x - v.bounds.size.width, v.center.y);
        } completion:^(BOOL finished) {
            v.center = CGPointMake(v.center.x + v.bounds.size.width*2, v.center.y);
            self.alertView.message = NSLocalizedString(@"\nverify passcode", nil);
            [self textField:self.pinField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
            [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
             animations:^{ v.center = CGPointMake(v.center.x - v.bounds.size.width, v.center.y); } completion:nil];
        }];

        while (self.alertView.visible && self.pinField.text.length < 4) {
            [[NSRunLoop mainRunLoop] limitDateForMode:NSDefaultRunLoopMode];
        }

        if (! self.alertView.visible) break;
    
        if ([self.pinField.text isEqual:pin]) {
            self.pinField.text = nil;
            setKeychainString(pin, PIN_KEY, NO);
            [self.alertView dismissWithClickedButtonIndex:self.alertView.cancelButtonIndex animated:YES];
            [self.pinField performSelector:@selector(resignFirstResponder) withObject:nil afterDelay:0.1];
            return YES;
        }
        
        self.pinField.text = nil;
        
        [UIView animateWithDuration:0.05 delay:0.1 options:UIViewAnimationOptionCurveEaseInOut animations:^{ // shake
            v.center = CGPointMake(v.center.x + 30.0, v.center.y);
        } completion:^(BOOL finished) {
            self.alertView.message = NSLocalizedString(@"\nchoose passcode", nil);
            [self textField:self.pinField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.2 initialSpringVelocity:0.0 options:0
             animations:^{ v.center = CGPointMake(v.center.x - 30.0, v.center.y); } completion:nil];
        }];
    }
    
    [self.pinField performSelector:@selector(resignFirstResponder) withObject:nil afterDelay:0.1];
    return NO;
}

- (uint64_t)spendingLimit
{
    // it's ok to store this in userdefaults because increasing the value only takes effect after next pin entry
    uint64_t limit = [[NSUserDefaults standardUserDefaults] doubleForKey:SPEND_LIMIT_AMOUNT_KEY];

    return (limit) ? limit : SATOSHIS;
}

- (void)setSpendingLimit:(uint64_t)spendingLimit
{
    // check if the new spending limit is less than the current amount left before triggering pin
    if (self.wallet.totalSent + spendingLimit < getKeychainInt(SPEND_LIMIT_KEY)) {
        if (! setKeychainInt(self.wallet.totalSent + spendingLimit, SPEND_LIMIT_KEY, NO)) return;
    }
    
    [[NSUserDefaults standardUserDefaults] setDouble:spendingLimit forKey:SPEND_LIMIT_AMOUNT_KEY];
}

// last known time from an ssl server connection
- (NSTimeInterval)secureTime
{
    return [[NSUserDefaults standardUserDefaults] doubleForKey:SECURE_TIME_KEY];
}

// local currency ISO code
- (void)setLocalCurrencyCode:(NSString *)localCurrencyCode
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    
    _localCurrencyCode = [localCurrencyCode copy];
    
    if ([self.localCurrencyCode isEqual:[[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode]]) {
        [defs removeObjectForKey:LOCAL_CURRENCY_CODE_KEY];
    }
    else [defs setObject:self.localCurrencyCode forKey:LOCAL_CURRENCY_CODE_KEY];
    
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
        
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) { // store server timestamp
            NSString *date = [(NSHTTPURLResponse *)response allHeaderFields][@"Date"];
            NSTimeInterval now = [[[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:nil]
                                   matchesInString:date options:0 range:NSMakeRange(0, date.length)].lastObject
                                  date].timeIntervalSinceReferenceDate;
            
            if (now > self.secureTime) [defs setDouble:now forKey:SECURE_TIME_KEY];
        }

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

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    NSMutableString *passcode = CFBridgingRelease(CFStringCreateMutableCopy(SecureAllocator(), 4,
                                                                            (CFStringRef)textField.text));
    
    CFStringReplace((CFMutableStringRef)passcode, CFRangeMake(range.location, range.length), (CFStringRef)string);

    NSUInteger l = passcode.length;

    self.alertView.title = [NSString stringWithFormat:@"%@\t%@\t%@\t%@%@", (l > 0 ? DOT : CIRCLE),
                            (l > 1 ? DOT : CIRCLE), (l > 2 ? DOT : CIRCLE), (l > 3 ? DOT : CIRCLE),
                            [self.alertView.title substringFromIndex:7]];
    return YES;
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
