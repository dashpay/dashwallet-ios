//
//  DSWalletManager.m
//  DashSync
//
//  Created by Aaron Voisine on 3/2/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
//  Updated by Quantum Explorer on 05/11/18.
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

#import "DSWalletManager.h"
#import "DSChainManager.h"
#import "DSAccount.h"
#import "DSKey.h"
#import "DSChain.h"
#import "DSKey+BIP38.h"
#import "DSBIP39Mnemonic.h"
#import "DSTransaction.h"
#import "DSTransactionEntity+CoreDataClass.h"
#import "DSAddressEntity+CoreDataClass.h"
#import "DSEventManager.h"
#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Dash.h"
#import "NSManagedObject+Sugar.h"
#import "NSAttributedString+Attachments.h"
#import "NSString+Dash.h"
#import "Reachability.h"
#import "DSChainPeerManager.h"
#import "DSDerivationPath.h"
#import "DSAuthenticationManager.h"
#import "NSData+Bitcoin.h"

#define UNSPENT_URL          @"http://insight.dash.org/insight-api-dash/addrs/utxo"
#define UNSPENT_FAILOVER_URL @"https://insight.dash.siampm.com/api/addrs/utxo"
#define BITCOIN_TICKER_URL  @"https://bitpay.com/rates"
#define POLONIEX_TICKER_URL  @"https://poloniex.com/public?command=returnOrderBook&currencyPair=BTC_DASH&depth=1"
#define DASHCENTRAL_TICKER_URL  @"https://www.dashcentral.org/api/v1/public"
#define TICKER_REFRESH_TIME 60.0

#define DEFAULT_CURRENCY_CODE @"USD"
#define DEFAULT_SPENT_LIMIT   DUFFS

#define LOCAL_CURRENCY_CODE_KEY @"LOCAL_CURRENCY_CODE"
#define CURRENCY_CODES_KEY      @"CURRENCY_CODES"
#define CURRENCY_NAMES_KEY      @"CURRENCY_NAMES"
#define CURRENCY_PRICES_KEY     @"CURRENCY_PRICES"
#define POLONIEX_DASH_BTC_PRICE_KEY  @"POLONIEX_DASH_BTC_PRICE"
#define POLONIEX_DASH_BTC_UPDATE_TIME_KEY  @"POLONIEX_DASH_BTC_UPDATE_TIME"
#define DASHCENTRAL_DASH_BTC_PRICE_KEY @"DASHCENTRAL_DASH_BTC_PRICE"
#define DASHCENTRAL_DASH_BTC_UPDATE_TIME_KEY @"DASHCENTRAL_DASH_BTC_UPDATE_TIME"
#define SPEND_LIMIT_AMOUNT_KEY  @"SPEND_LIMIT_AMOUNT"

#define USER_ACCOUNT_KEY    @"https://api.dashwallet.com"


@interface DSWalletManager()

@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) NSArray *currencyPrices;
@property (nonatomic, assign) BOOL sweepFee;
@property (nonatomic, strong) NSString *sweepKey;
@property (nonatomic, strong) void (^sweepCompletion)(DSTransaction *tx, uint64_t fee, NSError *error);
@property (nonatomic, strong) id protectedObserver;

@property (nonatomic, strong) NSNumber * _Nullable bitcoinDashPrice; // exchange rate in bitcoin per dash
@property (nonatomic, strong) NSNumber * _Nullable localCurrencyBitcoinPrice; // exchange rate in local currency units per bitcoin
@property (nonatomic, strong) NSNumber * _Nullable localCurrencyDashPrice;

@end

@implementation DSWalletManager

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
    _dashFormat = [NSNumberFormatter new];
    self.dashFormat.lenient = YES;
    self.dashFormat.numberStyle = NSNumberFormatterCurrencyStyle;
    self.dashFormat.generatesDecimalNumbers = YES;
    self.dashFormat.negativeFormat = [self.dashFormat.positiveFormat
                                      stringByReplacingCharactersInRange:[self.dashFormat.positiveFormat rangeOfString:@"#"]
                                      withString:@"-#"];
    self.dashFormat.currencyCode = @"DASH";
    self.dashFormat.currencySymbol = DASH NARROW_NBSP;
    self.dashFormat.maximumFractionDigits = 8;
    self.dashFormat.minimumFractionDigits = 0; // iOS 8 bug, minimumFractionDigits now has to be set after currencySymbol
    self.dashFormat.maximum = @(MAX_MONEY/(int64_t)pow(10.0, self.dashFormat.maximumFractionDigits));
    
    _dashSignificantFormat = [NSNumberFormatter new];
    self.dashSignificantFormat.lenient = YES;
    self.dashSignificantFormat.numberStyle = NSNumberFormatterCurrencyStyle;
    self.dashSignificantFormat.generatesDecimalNumbers = YES;
    self.dashSignificantFormat.negativeFormat = [self.dashFormat.positiveFormat
                                                 stringByReplacingCharactersInRange:[self.dashFormat.positiveFormat rangeOfString:@"#"]
                                                 withString:@"-#"];
    self.dashSignificantFormat.currencyCode = @"DASH";
    self.dashSignificantFormat.currencySymbol = DASH NARROW_NBSP;
    self.dashSignificantFormat.usesSignificantDigits = TRUE;
    self.dashSignificantFormat.minimumSignificantDigits = 1;
    self.dashSignificantFormat.maximumSignificantDigits = 6;
    self.dashSignificantFormat.maximumFractionDigits = 8;
    self.dashSignificantFormat.minimumFractionDigits = 0; // iOS 8 bug, minimumFractionDigits now has to be set after currencySymbol
    self.dashSignificantFormat.maximum = @(MAX_MONEY/(int64_t)pow(10.0, self.dashFormat.maximumFractionDigits));
    
    _bitcoinFormat = [NSNumberFormatter new];
    self.bitcoinFormat.lenient = YES;
    self.bitcoinFormat.numberStyle = NSNumberFormatterCurrencyStyle;
    self.bitcoinFormat.generatesDecimalNumbers = YES;
    self.bitcoinFormat.negativeFormat = [self.bitcoinFormat.positiveFormat
                                         stringByReplacingCharactersInRange:[self.bitcoinFormat.positiveFormat rangeOfString:@"#"]
                                         withString:@"-#"];
    self.bitcoinFormat.currencyCode = @"BTC";
    self.bitcoinFormat.currencySymbol = BTC NARROW_NBSP;
    self.bitcoinFormat.maximumFractionDigits = 8;
    self.bitcoinFormat.minimumFractionDigits = 0; // iOS 8 bug, minimumFractionDigits now has to be set after currencySymbol
    self.bitcoinFormat.maximum = @(MAX_MONEY/(int64_t)pow(10.0, self.bitcoinFormat.maximumFractionDigits));
    
    _unknownFormat = [NSNumberFormatter new];
    self.unknownFormat.lenient = YES;
    self.unknownFormat.numberStyle = NSNumberFormatterDecimalStyle;
    self.unknownFormat.generatesDecimalNumbers = YES;
    self.unknownFormat.negativeFormat = [self.unknownFormat.positiveFormat
                                         stringByReplacingCharactersInRange:[self.unknownFormat.positiveFormat rangeOfString:@"#"]
                                         withString:@"-#"];
    self.unknownFormat.maximumFractionDigits = 8;
    self.unknownFormat.minimumFractionDigits = 0; // iOS 8 bug, minimumFractionDigits now has to be set after currencySymbol
    
    _localFormat = [NSNumberFormatter new];
    self.localFormat.lenient = YES;
    self.localFormat.numberStyle = NSNumberFormatterCurrencyStyle;
    self.localFormat.generatesDecimalNumbers = YES;
    self.localFormat.negativeFormat = self.dashFormat.negativeFormat;
    
    self.protectedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           [self protectedInit];
                                                       }];
    if ([UIApplication sharedApplication].protectedDataAvailable) [self protectedInit];
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
    
}

- (void)dealloc
{
    if (self.protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

-(void)startExchangeRateFetching {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateBitcoinExchangeRate];
        [self updateDashExchangeRate];
        [self updateDashCentralExchangeRateFallback];
    });
}



//- (void)registerWallet:(DSWallet*)wallet
//{
//    if ([chain.wallets indexOfObject:wallet] == NSNotFound) {
//        [chain addWallet:wallet];
//    }
//    NSError * error = nil;
//    NSMutableArray * keyChainArray = [getKeychainArray(chain.chainWalletsKey, &error) mutableCopy];
//    [keyChainArray addObject:wallet.uniqueID];
//    setKeychainArray(keyChainArray, chain.chainWalletsKey, NO);

        //TODO: reimplement this safeguard
        //        // verify that keychain matches core data, with different access and backup policies it's possible to diverge
        //        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //            DSKey *k = [DSKey keyWithPublicKey:[self.sequence publicKey:0 internal:NO masterPublicKey:mpk]];
        //
        //            if (chain.wallet.allReceiveAddresses.count > 0 && k && ! [chain.wallet containsAddress:k.address]) {
        //                NSLog(@"wallet doesn't contain address: %@", k.address);
        //#if 0
        //                abort(); // don't wipe core data for debug builds
        //#else
        //                [[NSManagedObject context] performBlockAndWait:^{
        //                    [DSAddressEntity deleteAllObjects];
        //                    [DSTransactionEntity deleteAllObjects];
        //                    [NSManagedObject saveContext];
        //                }];
        //
        //                [chain unregisterWallet];
        //
        //                dispatch_async(dispatch_get_main_queue(), ^{
        //                    [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletManagerSeedChangedNotification
        //                                                                        object:nil];
        //                    [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletBalanceChangedNotification
        //                                                                        object:nil];
        //                });
        //#endif
        //            }
        //        });

//

- (void)clearKeychainWalletData {
    BOOL failed = NO;
    for (DSWallet * wallet in [self allWallets]) {
        for (DSAccount * account in wallet.accounts) {
            for (DSDerivationPath * derivationPath in account.derivationPaths) {
                failed = failed | !setKeychainData(nil, [derivationPath walletBasedExtendedPublicKeyLocationString], NO);
            }
        }
    }
    failed = failed | !setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP44_V1, NO); //new keys
    failed = failed | !setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP32_V1, NO); //new keys
    failed = failed | !setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP44_V0, NO); //old keys
    failed = failed | !setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP32_V0, NO); //old keys
}

-(NSArray<DSWallet*>*)allWallets {
    NSMutableArray * wallets = [NSMutableArray array];
    for (DSChain * chain in [[DSChainManager sharedInstance] chains]) {
        if ([chain hasAWallet]) {
            [wallets addObjectsFromArray:chain.wallets];
        }
    }
    return [wallets copy];
}

//there was an issue with extended public keys on version 0.7.6 and before, this fixes that
-(void)upgradeExtendedKeysForWallet:(DSWallet*)wallet withCompletion:(UpgradeCompletionBlock)completion
{
    DSAccount * account = [wallet accountWithNumber:0];
    NSString * keyString = [[account bip44DerivationPath] walletBasedExtendedPublicKeyLocationString];
    NSError * error = nil;
    BOOL hasV2BIP44Data = hasKeychainData(keyString, &error);
    if (error) {
        completion(NO,NO,NO,NO);
        return;
    }
    error = nil;
    BOOL hasV1BIP44Data = (hasV2BIP44Data)?NO:hasKeychainData(EXTENDED_0_PUBKEY_KEY_BIP44_V1, &error);
    if (error) {
        completion(NO,NO,NO,NO);
        return;
    }
    BOOL hasV0BIP44Data = (hasV2BIP44Data)?NO:hasKeychainData(EXTENDED_0_PUBKEY_KEY_BIP44_V0, nil);
    if (!hasV2BIP44Data && (hasV1BIP44Data || hasV0BIP44Data)) {
        NSLog(@"fixing public key");
        //upgrade scenario
        [[DSAuthenticationManager sharedInstance] authenticateWithPrompt:(NSLocalizedString(@"please enter pin to upgrade wallet", nil)) andTouchId:NO alertIfLockout:NO completion:^(BOOL authenticated,BOOL cancelled) {
            if (!authenticated) {
                completion(NO,YES,NO,cancelled);
                return;
            }
            @autoreleasepool {
                NSString * seedPhrase = authenticated?getKeychainString(wallet.mnemonicUniqueID, nil):nil;
                if (!seedPhrase) {
                    completion(NO,YES,YES,NO);
                    return;
                }
                NSData * derivedKeyData = (seedPhrase) ?[[DSBIP39Mnemonic sharedInstance]
                                                         deriveKeyFromPhrase:seedPhrase withPassphrase:nil]:nil;
                BOOL failed = NO;
                for (DSAccount * account in wallet.accounts) {
                    for (DSDerivationPath * derivationPath in account.derivationPaths) {
                        NSData * data = [derivationPath generateExtendedPublicKeyFromSeed:derivedKeyData storeUnderWalletUniqueId:wallet.uniqueID];
                        failed = failed | !setKeychainData(data, [derivationPath walletBasedExtendedPublicKeyLocationString], NO);
                    }
                }
                if (hasV0BIP44Data) {
                    failed = failed | !setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP44_V1, NO); //old keys
                    failed = failed | !setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP32_V1, NO); //old keys
                }
                if (hasV1BIP44Data) {
                    failed = failed | !setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP44_V0, NO); //old keys
                    failed = failed | !setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP32_V0, NO); //old keys
                }
                
                completion(!failed,YES,YES,NO);
                
            }
        }];
        
    } else {
        completion(YES,NO,NO,NO);
    }
}

// true if this is a "watch only" wallet with no signing ability
- (BOOL)watchOnly
{
    @autoreleasepool {
        for (DSWallet * wallet in [self allWallets]) {
            DSAccount * account = [wallet accountWithNumber:0];
            NSString * keyString = [[account bip44DerivationPath] walletBasedExtendedPublicKeyLocationString];
            NSError * error = nil;
            NSData * v2BIP44Data = getKeychainData(keyString, &error);
            
            return (v2BIP44Data && v2BIP44Data.length == 0) ? YES : NO;
        }
    }
    return NO;
}

- (NSDictionary *)userAccount
{
    return getKeychainDict(USER_ACCOUNT_KEY, nil);
}

- (void)setUserAccount:(NSDictionary *)userAccount
{
    setKeychainDict(userAccount, USER_ACCOUNT_KEY, NO);
}

- (BOOL)hasAOldWallet
{
    NSError *error = nil;
    if (getKeychainData(EXTENDED_0_PUBKEY_KEY_BIP44_V1, &error) || error) return NO;
    if (getKeychainData(EXTENDED_0_PUBKEY_KEY_BIP32_V1, &error) || error) return NO;
    if (getKeychainData(EXTENDED_0_PUBKEY_KEY_BIP44_V0, &error) || error) return NO;
    if (getKeychainData(EXTENDED_0_PUBKEY_KEY_BIP32_V0, &error) || error) return NO;
    return YES;
}

// MARK: - Spending Limit

//makes sense to be here, since we have the limits per chain
-(void)resetSpendingLimit {

    uint64_t limit = self.spendingLimit;
    uint64_t totalSent = 0;
    for (DSWallet * wallet in self.allWallets) {
        totalSent += wallet.totalSent;
    }
    if (limit > 0) setKeychainInt(totalSent + limit, SPEND_LIMIT_KEY, NO);

}

// amount that can be spent using touch id without pin entry
- (uint64_t)spendingLimit
{
    // it's ok to store this in userdefaults because increasing the value only takes effect after successful pin entry
    if (! [[NSUserDefaults standardUserDefaults] objectForKey:SPEND_LIMIT_AMOUNT_KEY]) return DUFFS;
    
    return [[NSUserDefaults standardUserDefaults] doubleForKey:SPEND_LIMIT_AMOUNT_KEY];
}

- (void)setSpendingLimit:(uint64_t)spendingLimit
{
    uint64_t totalSent = 0;
    for (DSWallet * wallet in self.allWallets) {
        totalSent += wallet.totalSent;
    }
    if (setKeychainInt((spendingLimit > 0) ? totalSent + spendingLimit : 0, SPEND_LIMIT_KEY, NO)) {
        // use setDouble since setInteger won't hold a uint64_t
        [[NSUserDefaults standardUserDefaults] setDouble:spendingLimit forKey:SPEND_LIMIT_AMOUNT_KEY];
    }
}

// MARK: - exchange rate

// local currency ISO code
- (void)setLocalCurrencyCode:(NSString *)code
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSUInteger i = [_currencyCodes indexOfObject:code];
    
    if (i == NSNotFound) code = DEFAULT_CURRENCY_CODE, i = [_currencyCodes indexOfObject:DEFAULT_CURRENCY_CODE];
    _localCurrencyCode = [code copy];
    
    if (i < _currencyPrices.count && [DSAuthenticationManager sharedInstance].secureTime + 3*24*60*60 > [NSDate timeIntervalSinceReferenceDate]) {
        self.localCurrencyBitcoinPrice = _currencyPrices[i]; // don't use exchange rate data more than 72hrs out of date
    }
    else self.localCurrencyBitcoinPrice = @(0);
    
    self.localFormat.currencyCode = _localCurrencyCode;
    self.localFormat.maximum =
    [[NSDecimalNumber decimalNumberWithDecimal:self.localCurrencyBitcoinPrice.decimalValue]
     decimalNumberByMultiplyingBy:(id)[NSDecimalNumber numberWithLongLong:MAX_MONEY/DUFFS]];
    
    if ([self.localCurrencyCode isEqual:[[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode]]) {
        [defs removeObjectForKey:LOCAL_CURRENCY_CODE_KEY];
    }
    else [defs setObject:self.localCurrencyCode forKey:LOCAL_CURRENCY_CODE_KEY];
    
    //    if (! _wallet) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletBalanceChangedNotification object:nil];
    });
}

-(NSNumber*)bitcoinDashPrice {
    if (_bitcoinDashPrice.doubleValue == 0) {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        
        double poloniexPrice = [[defs objectForKey:POLONIEX_DASH_BTC_PRICE_KEY] doubleValue];
        double dashcentralPrice = [[defs objectForKey:DASHCENTRAL_DASH_BTC_PRICE_KEY] doubleValue];
        if (poloniexPrice > 0) {
            if (dashcentralPrice > 0) {
                _bitcoinDashPrice = @((poloniexPrice + dashcentralPrice)/2.0);
            } else {
                _bitcoinDashPrice = @(poloniexPrice);
            }
        } else if (dashcentralPrice > 0) {
            _bitcoinDashPrice = @(dashcentralPrice);
        }
    }
    return _bitcoinDashPrice;
}

- (void)refreshBitcoinDashPrice{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    double poloniexPrice = [[defs objectForKey:POLONIEX_DASH_BTC_PRICE_KEY] doubleValue];
    double dashcentralPrice = [[defs objectForKey:DASHCENTRAL_DASH_BTC_PRICE_KEY] doubleValue];
    NSNumber * newPrice = 0;
    if (poloniexPrice > 0) {
        if (dashcentralPrice > 0) {
            newPrice = @((poloniexPrice + dashcentralPrice)/2.0);
        } else {
            newPrice = @(poloniexPrice);
        }
    } else if (dashcentralPrice > 0) {
        newPrice = @(dashcentralPrice);
    }
    
    //    if (! _wallet ) return;
    //if ([newPrice doubleValue] == [_bitcoinDashPrice doubleValue]) return;
    _bitcoinDashPrice = newPrice;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletBalanceChangedNotification object:nil];
    });
}


// until there is a public api for dash prices among multiple currencies it's better that we pull Bitcoin prices per currency and convert it to dash
- (void)updateDashExchangeRate
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateDashExchangeRate) object:nil];
    [self performSelector:@selector(updateDashExchangeRate) withObject:nil afterDelay:TICKER_REFRESH_TIME];
    if (self.reachability.currentReachabilityStatus == NotReachable) return;
    
    
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:POLONIEX_TICKER_URL]
                                         cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *connectionError) {
                                         if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError) {
                                             NSLog(@"connectionError %@ (status %ld)", connectionError,(long)((NSHTTPURLResponse*)response).statusCode);
                                             return;
                                         }
                                         if ([response isKindOfClass:[NSHTTPURLResponse class]]) { // store server timestamp
                                             NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
                                             NSString *date = [(NSHTTPURLResponse *)response allHeaderFields][@"Date"];
                                             NSTimeInterval now = [[[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:nil]
                                                                    matchesInString:date options:0 range:NSMakeRange(0, date.length)].lastObject
                                                                   date].timeIntervalSinceReferenceDate;
                                             
                                             if (now > [DSAuthenticationManager sharedInstance].secureTime) [defs setDouble:now forKey:SECURE_TIME_KEY];
                                         }
                                         NSError *error = nil;
                                         NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                                         NSArray * asks = [json objectForKey:@"asks"];
                                         NSArray * bids = [json objectForKey:@"bids"];
                                         if ([asks count] && [bids count] && [[asks objectAtIndex:0] count] && [[bids objectAtIndex:0] count]) {
                                             NSString * lastTradePriceStringAsks = [[asks objectAtIndex:0] objectAtIndex:0];
                                             NSString * lastTradePriceStringBids = [[bids objectAtIndex:0] objectAtIndex:0];
                                             if (lastTradePriceStringAsks && lastTradePriceStringBids) {
                                                 NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
                                                 NSLocale *usa = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
                                                 numberFormatter.locale = usa;
                                                 numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
                                                 NSNumber *lastTradePriceNumberAsks = [numberFormatter numberFromString:lastTradePriceStringAsks];
                                                 NSNumber *lastTradePriceNumberBids = [numberFormatter numberFromString:lastTradePriceStringBids];
                                                 NSNumber * lastTradePriceNumber = @((lastTradePriceNumberAsks.floatValue + lastTradePriceNumberBids.floatValue) / 2);
                                                 NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
                                                 [defs setObject:lastTradePriceNumber forKey:POLONIEX_DASH_BTC_PRICE_KEY];
                                                 [defs setObject:[NSDate date] forKey:POLONIEX_DASH_BTC_UPDATE_TIME_KEY];
                                                 [defs synchronize];
                                                 [self refreshBitcoinDashPrice];
                                             }
                                         }
#if EXCHANGE_RATES_LOGGING
                                         NSLog(@"poloniex exchange rate updated to %@/%@", [self localCurrencyStringForDashAmount:DUFFS],
                                               [self stringForDashAmount:DUFFS]);
#endif
                                     }
      ] resume];
    
}

// until there is a public api for dash prices among multiple currencies it's better that we pull Bitcoin prices per currency and convert it to dash
- (void)updateDashCentralExchangeRateFallback
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateDashCentralExchangeRateFallback) object:nil];
    [self performSelector:@selector(updateDashCentralExchangeRateFallback) withObject:nil afterDelay:TICKER_REFRESH_TIME];
    if (self.reachability.currentReachabilityStatus == NotReachable) return;
    
    
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:DASHCENTRAL_TICKER_URL]
                                         cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *connectionError) {
                                         if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError) {
                                             NSLog(@"connectionError %@ (status %ld)", connectionError,(long)((NSHTTPURLResponse*)response).statusCode);
                                             return;
                                         }
                                         
                                         if ([response isKindOfClass:[NSHTTPURLResponse class]]) { // store server timestamp
                                             NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
                                             NSString *date = [(NSHTTPURLResponse *)response allHeaderFields][@"Date"];
                                             NSTimeInterval now = [[[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:nil]
                                                                    matchesInString:date options:0 range:NSMakeRange(0, date.length)].lastObject
                                                                   date].timeIntervalSinceReferenceDate;
                                             
                                             if (now > [DSAuthenticationManager sharedInstance].secureTime) [defs setDouble:now forKey:SECURE_TIME_KEY];
                                         }
                                         
                                         NSError *error = nil;
                                         NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                                         if (!error) {
                                             NSNumber * dash_usd = @([[[json objectForKey:@"exchange_rates"] objectForKey:@"btc_dash"] doubleValue]);
                                             if (dash_usd && [dash_usd doubleValue] > 0) {
                                                 NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
                                                 
                                                 [defs setObject:dash_usd forKey:DASHCENTRAL_DASH_BTC_PRICE_KEY];
                                                 [defs setObject:[NSDate date] forKey:DASHCENTRAL_DASH_BTC_UPDATE_TIME_KEY];
                                                 [defs synchronize];
                                                 [self refreshBitcoinDashPrice];
#if EXCHANGE_RATES_LOGGING
                                                 NSLog(@"dash central exchange rate updated to %@/%@", [self localCurrencyStringForDashAmount:DUFFS],
                                                       [self stringForDashAmount:DUFFS]);
#endif
                                             }
                                         }
                                     }
      ] resume];
    
}

- (void)updateBitcoinExchangeRate
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateBitcoinExchangeRate) object:nil];
    [self performSelector:@selector(updateBitcoinExchangeRate) withObject:nil afterDelay:TICKER_REFRESH_TIME];
    if (self.reachability.currentReachabilityStatus == NotReachable) return;
    
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:BITCOIN_TICKER_URL]
                                         cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10.0];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *connectionError) {
        if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError) {
            NSLog(@"connectionError %@ (status %ld)", connectionError,(long)((NSHTTPURLResponse*)response).statusCode);
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
            
            if (now > [DSAuthenticationManager sharedInstance].secureTime) [defs setDouble:now forKey:SECURE_TIME_KEY];
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
        
        self->_currencyCodes = codes;
        self->_currencyNames = names;
        self->_currencyPrices = rates;
        self.localCurrencyCode = self->_localCurrencyCode; // update localCurrencyPrice and localFormat.maximum
        [defs setObject:self.currencyCodes forKey:CURRENCY_CODES_KEY];
        [defs setObject:self.currencyNames forKey:CURRENCY_NAMES_KEY];
        [defs setObject:self.currencyPrices forKey:CURRENCY_PRICES_KEY];
        [defs synchronize];
#if EXCHANGE_RATES_LOGGING
        NSLog(@"bitcoin exchange rate updated to %@/%@", [self localCurrencyStringForDashAmount:DUFFS],
              [self stringForDashAmount:DUFFS]);
#endif
    }
      
      
      ] resume];
    
}


// MARK: - query unspent outputs

// queries api.breadwallet.com and calls the completion block with unspent outputs for the given addresses
- (void)utxosForAddresses:(NSArray *)addresses
               completion:(void (^)(NSArray *utxos, NSArray *amounts, NSArray *scripts, NSError *error))completion
{
    [self utxos:UNSPENT_URL forAddresses:addresses
     completion:^(NSArray *utxos, NSArray *amounts, NSArray *scripts, NSError *error) {
         if (error) {
             [self utxos:UNSPENT_FAILOVER_URL forAddresses:addresses
              completion:^(NSArray *utxos, NSArray *amounts, NSArray *scripts, NSError *err) {
                  if (err) err = error;
                  completion(utxos, amounts, scripts, err);
              }];
         }
         else completion(utxos, amounts, scripts, error);
     }];
}

- (void)utxos:(NSString *)unspentURL forAddresses:(NSArray *)addresses
   completion:(void (^)(NSArray *utxos, NSArray *amounts, NSArray *scripts, NSError *error))completion
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:unspentURL]
                                                       cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:20.0];
    NSMutableArray *args = [NSMutableArray array];
    NSMutableCharacterSet *charset = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    
    [charset removeCharactersInString:@"&="];
    [args addObject:[@"addrs=" stringByAppendingString:[[addresses componentsJoinedByString:@","]
                                                        stringByAddingPercentEncodingWithAllowedCharacters:charset]]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [[args componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    NSLog(@"%@ POST: %@", req.URL.absoluteString,
          [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding]);
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                         if (error) {
                                             completion(nil, nil, nil, error);
                                             return;
                                         }
                                         
                                         NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                                         NSMutableArray *utxos = [NSMutableArray array], *amounts = [NSMutableArray array],
                                         *scripts = [NSMutableArray array];
                                         DSUTXO o;
                                         
                                         if (error || ! [json isKindOfClass:[NSArray class]]) {
                                             NSLog(@"Error decoding response %@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                                             completion(nil, nil, nil,
                                                        [NSError errorWithDomain:@"DashWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                                                                                                                       [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil),
                                                                                                                        req.URL.host]}]);
                                             return;
                                         }
                                         
                                         for (NSDictionary *utxo in json) {
                                             
                                             NSDecimalNumber * amount = nil;
                                             if (utxo[@"amount"]) {
                                                 if ([utxo[@"amount"] isKindOfClass:[NSString class]]) {
                                                     amount = [NSDecimalNumber decimalNumberWithString:utxo[@"amount"]];
                                                 } else if ([utxo[@"amount"] isKindOfClass:[NSDecimalNumber class]]) {
                                                     amount = utxo[@"amount"];
                                                 } else if ([utxo[@"amount"] isKindOfClass:[NSNumber class]]) {
                                                     amount = [NSDecimalNumber decimalNumberWithDecimal:[utxo[@"amount"] decimalValue]];
                                                 }
                                             }
                                             if (! [utxo isKindOfClass:[NSDictionary class]] ||
                                                 ! [utxo[@"txid"] isKindOfClass:[NSString class]] ||
                                                 [utxo[@"txid"] hexToData].length != sizeof(UInt256) ||
                                                 ! [utxo[@"vout"] isKindOfClass:[NSNumber class]] ||
                                                 ! [utxo[@"scriptPubKey"] isKindOfClass:[NSString class]] ||
                                                 ! [utxo[@"scriptPubKey"] hexToData] ||
                                                 (! [utxo[@"duffs"] isKindOfClass:[NSNumber class]] && ! [utxo[@"satoshis"] isKindOfClass:[NSNumber class]] && !amount)) {
                                                 completion(nil, nil, nil,
                                                            [NSError errorWithDomain:@"DashWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                                                                                                                           [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil),
                                                                                                                            req.URL.host]}]);
                                                 return;
                                             }
                                             
                                             o.hash = *(const UInt256 *)[utxo[@"txid"] hexToData].reverse.bytes;
                                             o.n = [utxo[@"vout"] unsignedIntValue];
                                             [utxos addObject:dsutxo_obj(o)];
                                             if (amount) {
                                                 [amounts addObject:[amount decimalNumberByMultiplyingByPowerOf10:8]];
                                             } else if (utxo[@"duffs"]) {
                                                 [amounts addObject:utxo[@"duffs"]];
                                             }  else if (utxo[@"satoshis"]) {
                                                 [amounts addObject:utxo[@"satoshis"]];
                                             }
                                             [scripts addObject:[utxo[@"scriptPubKey"] hexToData]];
                                         }
                                         
                                         completion(utxos, amounts, scripts, nil);
                                     }] resume];
}

// given a private key, queries dash insight for unspent outputs and calls the completion block with a signed transaction
// that will sweep the balance into the account (doesn't publish the tx)
// this can only be done on main chain for now
- (void)sweepPrivateKey:(NSString *)privKey onChain:(DSChain*)chain toAccount:(DSAccount*)account withFee:(BOOL)fee
             completion:(void (^)(DSTransaction *tx, uint64_t fee, NSError *error))completion
{
    if (! completion) return;
    
    if ([privKey isValidDashBIP38Key]) {
        [[DSAuthenticationManager sharedInstance] requestKeyPasswordForSweepCompletion:^(NSString *password) {
            dispatch_async(dispatch_get_main_queue(), ^{
                DSKey *key = [DSKey keyWithBIP38Key:self.sweepKey andPassphrase:password onChain:chain];
                
                if (! key) {
                    [[DSAuthenticationManager sharedInstance] badKeyPasswordForSweepCompletion:^{
                        [self sweepPrivateKey:privKey onChain:chain toAccount:account withFee:fee completion:completion];
                    } cancel:^{
                        if (self.sweepCompletion) self.sweepCompletion(nil, 0, nil);
                        self.sweepKey = nil;
                        self.sweepCompletion = nil;
                    }];
                     }
                     else {
                         [self sweepPrivateKey:[key privateKeyStringForChain:chain] onChain:chain withFee:self.sweepFee completion:self.sweepCompletion];
                         self.sweepKey = nil;
                         self.sweepCompletion = nil;
                     }
            });
        } cancel:^{
            
        }];
        self.sweepKey = privKey;
        self.sweepFee = fee;
        self.sweepCompletion = completion;
        return;
    }
    
    DSKey *key = [DSKey keyWithPrivateKey:privKey onChain:chain];
    NSString * address = [key addressForChain:chain];
    if (! address) {
        completion(nil, 0, [NSError errorWithDomain:@"DashWallet" code:187 userInfo:@{NSLocalizedDescriptionKey:
                                                                                          NSLocalizedString(@"not a valid private key", nil)}]);
        return;
    }
        if ([account.wallet containsAddress:address]) {
            completion(nil, 0, [NSError errorWithDomain:@"DashWallet" code:187 userInfo:@{NSLocalizedDescriptionKey:
                                                                                              NSLocalizedString(@"this private key is already in your wallet", nil)}]);
            return;
        }
    
    [self utxosForAddresses:@[address]
                 completion:^(NSArray *utxos, NSArray *amounts, NSArray *scripts, NSError *error) {
                     DSTransaction *tx = [DSTransaction new];
                     uint64_t balance = 0, feeAmount = 0;
                     NSUInteger i = 0;
                     
                     if (error) {
                         completion(nil, 0, error);
                         return;
                     }
                     
                     //TODO: make sure not to create a transaction larger than TX_MAX_SIZE
                     for (NSValue *output in utxos) {
                         DSUTXO o;
                         
                         [output getValue:&o];
                         [tx addInputHash:o.hash index:o.n script:scripts[i]];
                         balance += [amounts[i++] unsignedLongLongValue];
                     }
                     
                     if (balance == 0) {
                         completion(nil, 0, [NSError errorWithDomain:@"DashWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                                                                                                           NSLocalizedString(@"this private key is empty", nil)}]);
                         return;
                     }
                     
                     // we will be adding a wallet output (34 bytes), also non-compact pubkey sigs are larger by 32bytes each
                     if (fee) feeAmount = [chain feeForTxSize:tx.size + 34 + (key.publicKey.length - 33)*tx.inputHashes.count isInstant:false inputCount:0]; //input count doesn't matter for non instant transactions
                     
                     if (feeAmount + chain.minOutputAmount > balance) {
                         completion(nil, 0, [NSError errorWithDomain:@"DashWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                                                                                                           NSLocalizedString(@"transaction fees would cost more than the funds available on this "
                                                                                                                             "private key (due to tiny \"dust\" deposits)",nil)}]);
                         return;
                     }
                     
                     [tx addOutputAddress:account.receiveAddress amount:balance - feeAmount];
                     
                     if (! [tx signWithPrivateKeys:@[privKey]]) {
                         completion(nil, 0, [NSError errorWithDomain:@"DashWallet" code:401 userInfo:@{NSLocalizedDescriptionKey:
                                                                                                           NSLocalizedString(@"error signing transaction", nil)}]);
                         return;
                     }
                     
                     completion(tx, feeAmount, nil);
                 }];
}

// MARK: - string helpers

- (int64_t)amountForUnknownCurrencyString:(NSString *)string
{
    if (! string.length) return 0;
    return [[[NSDecimalNumber decimalNumberWithString:string]
             decimalNumberByMultiplyingByPowerOf10:self.unknownFormat.maximumFractionDigits] longLongValue];
}

- (int64_t)amountForDashString:(NSString *)string
{
    if (! string.length) return 0;
    NSInteger dashCharPos = [string indexOfCharacter:NSAttachmentCharacter];
    if (dashCharPos != NSNotFound) {
        string = [string stringByReplacingCharactersInRange:NSMakeRange(dashCharPos, 1) withString:DASH];
    }
    return [[[NSDecimalNumber decimalNumberWithDecimal:[[self.dashFormat numberFromString:string] decimalValue]]
             decimalNumberByMultiplyingByPowerOf10:self.dashFormat.maximumFractionDigits] longLongValue];
}

- (int64_t)amountForBitcoinString:(NSString *)string
{
    if (! string.length) return 0;
    return [[[NSDecimalNumber decimalNumberWithDecimal:[[self.bitcoinFormat numberFromString:string] decimalValue]]
             decimalNumberByMultiplyingByPowerOf10:self.bitcoinFormat.maximumFractionDigits] longLongValue];
}

- (NSAttributedString *)attributedStringForDashAmount:(int64_t)amount
{
    NSString * string = [self.dashFormat stringFromNumber:[(id)[NSDecimalNumber numberWithLongLong:amount]
                                                           decimalNumberByMultiplyingByPowerOf10:-self.dashFormat.maximumFractionDigits]];
    return [string attributedStringForDashSymbol];
}

- (NSAttributedString *)attributedStringForDashAmount:(int64_t)amount withTintColor:(UIColor*)color {
    NSString * string = [self.dashFormat stringFromNumber:[(id)[NSDecimalNumber numberWithLongLong:amount]
                                                           decimalNumberByMultiplyingByPowerOf10:-self.dashFormat.maximumFractionDigits]];
    return [string attributedStringForDashSymbolWithTintColor:color];
}

- (NSAttributedString *)attributedStringForDashAmount:(int64_t)amount withTintColor:(UIColor*)color useSignificantDigits:(BOOL)useSignificantDigits {
    NSString * string = [(useSignificantDigits?self.dashSignificantFormat:self.dashFormat) stringFromNumber:[(id)[NSDecimalNumber numberWithLongLong:amount]
                                                                                                             decimalNumberByMultiplyingByPowerOf10:-self.dashFormat.maximumFractionDigits]];
    return [string attributedStringForDashSymbolWithTintColor:color];
}

- (NSAttributedString *)attributedStringForDashAmount:(int64_t)amount withTintColor:(UIColor*)color dashSymbolSize:(CGSize)dashSymbolSize
{
    NSString * string = [self.dashFormat stringFromNumber:[(id)[NSDecimalNumber numberWithLongLong:amount]
                                                           decimalNumberByMultiplyingByPowerOf10:-self.dashFormat.maximumFractionDigits]];
    return [string attributedStringForDashSymbolWithTintColor:color dashSymbolSize:dashSymbolSize];
}

- (NSNumber *)numberForAmount:(int64_t)amount
{
    return (id)[(id)[NSDecimalNumber numberWithLongLong:amount]
                decimalNumberByMultiplyingByPowerOf10:-self.dashFormat.maximumFractionDigits];
}

- (NSString *)stringForBitcoinAmount:(int64_t)amount
{
    return [self.bitcoinFormat stringFromNumber:[(id)[NSDecimalNumber numberWithLongLong:amount]
                                                 decimalNumberByMultiplyingByPowerOf10:-self.bitcoinFormat.maximumFractionDigits]];
}

- (NSString *)stringForDashAmount:(int64_t)amount
{
    return [self.dashFormat stringFromNumber:[(id)[NSDecimalNumber numberWithLongLong:amount]
                                              decimalNumberByMultiplyingByPowerOf10:-self.dashFormat.maximumFractionDigits]];
}

-(NSNumber* _Nonnull)localCurrencyDashPrice {
    if (!_bitcoinDashPrice || !_localCurrencyBitcoinPrice) {
        return _localCurrencyDashPrice;
    } else {
        return @(_bitcoinDashPrice.doubleValue * _localCurrencyBitcoinPrice.doubleValue);
    }
}

// NOTE: For now these local currency methods assume that a satoshi has a smaller value than the smallest unit of any
// local currency. They will need to be revisited when that is no longer a safe assumption.
- (int64_t)amountForLocalCurrencyString:(NSString *)string
{
    if ([string hasPrefix:@"<"]) string = [string substringFromIndex:1];
    
    NSNumber *n = [self.localFormat numberFromString:string];
    int64_t price = [[NSDecimalNumber decimalNumberWithDecimal:self.localCurrencyDashPrice.decimalValue]
                     decimalNumberByMultiplyingByPowerOf10:self.localFormat.maximumFractionDigits].longLongValue,
    local = [[NSDecimalNumber decimalNumberWithDecimal:n.decimalValue]
             decimalNumberByMultiplyingByPowerOf10:self.localFormat.maximumFractionDigits].longLongValue,
    overflowbits = 0, p = 10, min, max, amount;
    
    if (local == 0 || price < 1) return 0;
    while (llabs(local) + 1 > INT64_MAX/DUFFS) local /= 2, overflowbits++; // make sure we won't overflow an int64_t
    min = llabs(local)*DUFFS/price + 1; // minimum amount that safely matches local currency string
    max = (llabs(local) + 1)*DUFFS/price - 1; // maximum amount that safely matches local currency string
    amount = (min + max)/2; // average min and max
    while (overflowbits > 0) local *= 2, min *= 2, max *= 2, amount *= 2, overflowbits--;
    
    if (amount >= MAX_MONEY) return (local < 0) ? -MAX_MONEY : MAX_MONEY;
    while ((amount/p)*p >= min && p <= INT64_MAX/10) p *= 10; // lowest decimal precision matching local currency string
    p /= 10;
    return (local < 0) ? -(amount/p)*p : (amount/p)*p;
}


- (int64_t)amountForBitcoinCurrencyString:(NSString *)string
{
    if (self.bitcoinDashPrice.doubleValue <= DBL_EPSILON) return 0;
    if ([string hasPrefix:@"<"]) string = [string substringFromIndex:1];
    
    double price = self.bitcoinDashPrice.doubleValue*pow(10.0, self.bitcoinFormat.maximumFractionDigits),
    amt = [[self.bitcoinFormat numberFromString:string] doubleValue]*
    pow(10.0, self.bitcoinFormat.maximumFractionDigits);
    int64_t local = amt + DBL_EPSILON*amt, overflowbits = 0;
    
    if (local == 0) return 0;
    while (llabs(local) + 1 > INT64_MAX/DUFFS) local /= 2, overflowbits++; // make sure we won't overflow an int64_t
    int64_t min = llabs(local)*DUFFS/(int64_t)(price + DBL_EPSILON*price) + 1,
    max = (llabs(local) + 1)*DUFFS/(int64_t)(price + DBL_EPSILON*price) - 1,
    amount = (min + max)/2, p = 10;
    
    while (overflowbits > 0) local *= 2, min *= 2, max *= 2, amount *= 2, overflowbits--;
    
    if (amount >= MAX_MONEY) return (local < 0) ? -MAX_MONEY : MAX_MONEY;
    while ((amount/p)*p >= min && p <= INT64_MAX/10) p *= 10; // lowest decimal precision matching local currency string
    p /= 10;
    return (local < 0) ? -(amount/p)*p : (amount/p)*p;
}

-(NSString *)bitcoinCurrencyStringForAmount:(int64_t)amount
{
    if (amount == 0) return [self.bitcoinFormat stringFromNumber:@(0)];
    
    
    NSDecimalNumber *n = [[[NSDecimalNumber decimalNumberWithDecimal:self.bitcoinDashPrice.decimalValue]
                           decimalNumberByMultiplyingBy:(id)[NSDecimalNumber numberWithLongLong:llabs(amount)]]
                          decimalNumberByDividingBy:(id)[NSDecimalNumber numberWithLongLong:DUFFS]],
    *min = [[NSDecimalNumber one]
            decimalNumberByMultiplyingByPowerOf10:-self.bitcoinFormat.maximumFractionDigits];
    
    // if the amount is too small to be represented in local currency (but is != 0) then return a string like "$0.01"
    if ([n compare:min] == NSOrderedAscending) n = min;
    if (amount < 0) n = [n decimalNumberByMultiplyingBy:(id)[NSDecimalNumber numberWithInt:-1]];
    return [self.bitcoinFormat stringFromNumber:n];
}

- (NSString *)localCurrencyStringForDashAmount:(int64_t)amount
{
    NSNumber *n = [self localCurrencyNumberForDashAmount:amount];
    if (!n) {
        return NSLocalizedString(@"Updating Price",@"Updating Price");
    }
    return [self.localFormat stringFromNumber:n];
}

- (NSString *)localCurrencyStringForBitcoinAmount:(int64_t)amount
{
    if (amount == 0) return [self.localFormat stringFromNumber:@(0)];
    if (self.localCurrencyBitcoinPrice.doubleValue <= DBL_EPSILON) return @""; // no exchange rate data
    
    NSDecimalNumber *n = [[[NSDecimalNumber decimalNumberWithDecimal:self.localCurrencyBitcoinPrice.decimalValue]
                           decimalNumberByMultiplyingBy:(id)[NSDecimalNumber numberWithLongLong:llabs(amount)]]
                          decimalNumberByDividingBy:(id)[NSDecimalNumber numberWithLongLong:DUFFS]],
    *min = [[NSDecimalNumber one]
            decimalNumberByMultiplyingByPowerOf10:-self.localFormat.maximumFractionDigits];
    
    // if the amount is too small to be represented in local currency (but is != 0) then return a string like "$0.01"
    if ([n compare:min] == NSOrderedAscending) n = min;
    if (amount < 0) n = [n decimalNumberByMultiplyingBy:(id)[NSDecimalNumber numberWithInt:-1]];
    return [self.localFormat stringFromNumber:n];
}

- (NSNumber * _Nullable)localCurrencyNumberForDashAmount:(int64_t)amount {
    if (amount == 0) {
        return @0;
    }
    
    if (!self.localCurrencyBitcoinPrice || !self.bitcoinDashPrice) {
        return nil;
    }
    
    NSNumber *local = [NSNumber numberWithDouble:self.localCurrencyBitcoinPrice.doubleValue*self.bitcoinDashPrice.doubleValue];
    
    NSDecimalNumber *n = [[[NSDecimalNumber decimalNumberWithDecimal:local.decimalValue]
                           decimalNumberByMultiplyingBy:(id)[NSDecimalNumber numberWithLongLong:llabs(amount)]]
                          decimalNumberByDividingBy:(id)[NSDecimalNumber numberWithLongLong:DUFFS]],
    *min = [[NSDecimalNumber one]
            decimalNumberByMultiplyingByPowerOf10:-self.localFormat.maximumFractionDigits];
    
    // if the amount is too small to be represented in local currency (but is != 0) then return a string like "$0.01"
    if ([n compare:min] == NSOrderedAscending) n = min;
    if (amount < 0) n = [n decimalNumberByMultiplyingBy:(id)[NSDecimalNumber numberWithInt:-1]];
    return n;
}

// MARK: - Quick Shortcuts

-(UIViewController*)presentingViewController {
    UIViewController *topController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    while (topController.presentedViewController && ![topController.presentedViewController isKindOfClass:[UIAlertController class]]) {
        topController = topController.presentedViewController;
    }
    if ([topController isKindOfClass:[UINavigationController class]]) {
        topController = ((UINavigationController*)topController).topViewController;
    }
    return topController;
}

@end
