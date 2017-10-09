//
//  BRWalletManager.h
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

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "BRWallet.h"
#import "BRMnemonic.h"

#define DASH         @"DASH"     // capital D with stroke (utf-8)
#define BTC          @"\xC9\x83"     // capital B with stroke (utf-8)
#define BITS         @"\xC6\x80"     // lowercase b with stroke (utf-8)
#define DITS         @"mDASH"     // lowercase d with stroke (utf-8)
#define NARROW_NBSP  @"\xE2\x80\xAF" // narrow no-break space (utf-8)
#define LDQUOTE      @"\xE2\x80\x9C" // left double quote (utf-8)
#define RDQUOTE      @"\xE2\x80\x9D" // right double quote (utf-8)
#define DISPLAY_NAME [NSString stringWithFormat:LDQUOTE @"%@" RDQUOTE,\
                      NSBundle.mainBundle.infoDictionary[@"CFBundleDisplayName"]]

#define WALLET_NEEDS_BACKUP_KEY @"WALLET_NEEDS_BACKUP"
#define PIN_UNLOCK_TIME_KEY     @"PIN_UNLOCK_TIME"

FOUNDATION_EXPORT NSString* _Nonnull const BRWalletManagerSeedChangedNotification;

@protocol BRMnemonic;

typedef void (^UpgradeCompletionBlock)(BOOL success, BOOL neededUpgrade,BOOL authenticated,BOOL cancelled); //success is true is neededUpgrade is true and we upgraded, or we didn't need upgrade
typedef void (^PinCompletionBlock)(BOOL authenticatedOrSuccess, BOOL cancelled);
typedef void (^SeedPhraseCompletionBlock)(NSString * _Nullable seedPhrase);
typedef void (^SeedCompletionBlock)(NSData * _Nullable seed);

@interface BRWalletManager : NSObject<UIAlertViewDelegate, UITextFieldDelegate, UITextViewDelegate>

@property (nonatomic, readonly) BRWallet * _Nullable wallet;
@property (nonatomic, readonly) BOOL noWallet; // true if keychain is available and we know that no wallet exists on it
@property (nonatomic, readonly) BOOL watchOnly; // true if this is a "watch only" wallet with no signing ability
@property (nonatomic, strong) id<BRKeySequence> _Nullable sequence;
@property (nonatomic, strong) id<BRMnemonic> _Nullable mnemonic;
@property (nonatomic, readonly) NSData * _Nullable extendedBIP44PublicKey;//master public key used to generate wallet addresses
@property (nonatomic, readonly) NSData * _Nullable extendedBIP32PublicKey;//master public key used to generate wallet addresses
@property (nonatomic, readonly) NSTimeInterval seedCreationTime; // interval since refrence date, 00:00:00 01/01/01 GMT
@property (nonatomic, readonly) NSTimeInterval secureTime; // last known time from an ssl server connection
@property (nonatomic, assign) uint64_t spendingLimit; // amount that can be spent using touch id without pin entry
@property (nonatomic, readonly) NSString * _Nullable authPrivateKey; // private key for signing authenticated api calls
@property (nonatomic, copy) NSDictionary * _Nullable userAccount; // client api user id and auth token
@property (nonatomic, readonly, getter=isTouchIdEnabled) BOOL touchIdEnabled; // true if touch id is enabled
@property (nonatomic, readonly, getter=isPasscodeEnabled) BOOL passcodeEnabled; // true if device passcode is enabled
@property (nonatomic, assign) BOOL didAuthenticate; // true if the user authenticated after this was last set to false
@property (nonatomic, readonly) NSNumberFormatter * _Nullable dashFormat; // dash currency formatter
@property (nonatomic, readonly) NSNumberFormatter * _Nullable dashSignificantFormat; // dash currency formatter that shows significant digits
@property (nonatomic, readonly) NSNumberFormatter * _Nullable bitcoinFormat; // bitcoin currency formatter
@property (nonatomic, readonly) NSNumberFormatter * _Nullable unknownFormat; // unknown currency formatter
@property (nonatomic, readonly) NSNumberFormatter * _Nullable localFormat; // local currency formatter
@property (nonatomic, copy) NSString * _Nullable localCurrencyCode; // local currency ISO code
@property (nonatomic, readonly) NSNumber * _Nullable bitcoinDashPrice; // exchange rate in bitcoin per dash
@property (nonatomic, readonly) NSNumber * _Nullable localCurrencyBitcoinPrice; // exchange rate in local currency units per bitcoin
@property (nonatomic, readonly) NSNumber * _Nullable localCurrencyDashPrice;
@property (nonatomic, readonly) NSArray * _Nullable currencyCodes; // list of supported local currency codes
@property (nonatomic, readonly) NSArray * _Nullable currencyNames; // names for local currency codes
@property (nonatomic, readonly) BOOL isTestnet;

+ (instancetype _Nullable)sharedInstance;

- (NSString * _Nullable)generateRandomSeed; // generates a random seed, saves to keychain and returns the seedPhrase
- (void)seedWithPrompt:(NSString * _Nullable)authprompt forAmount:(uint64_t)amount completion:(_Nullable SeedCompletionBlock)completion;//auth user,return seed
- (void)seedPhraseWithPrompt:(NSString * _Nullable)authprompt completion:(_Nullable SeedPhraseCompletionBlock)completion;; // authenticates user, returns seedPhrase
- (void)authenticateWithPrompt:(NSString * _Nullable)authprompt andTouchId:(BOOL)touchId alertIfLockout:(BOOL)alertIfLockout completion:(_Nullable PinCompletionBlock)completion; // prompt user to authenticate
- (void)setPinWithCompletion:(void (^ _Nullable)(BOOL success))completion; // prompts the user to set or change wallet pin and returns true if the pin was successfully set

// queries api.dashwallet.com and calls the completion block with unspent outputs for the given address
- (void)utxosForAddresses:(NSArray * _Nonnull)address
completion:(void (^ _Nonnull)(NSArray * _Nonnull utxos, NSArray * _Nonnull amounts, NSArray * _Nonnull scripts,
                              NSError * _Null_unspecified error))completion;

// given a private key, queries api.dashwallet.com for unspent outputs and calls the completion block with a signed
// transaction that will sweep the balance into wallet (doesn't publish the tx)
- (void)sweepPrivateKey:(NSString * _Nonnull)privKey withFee:(BOOL)fee
completion:(void (^ _Nonnull)(BRTransaction * _Nonnull tx, uint64_t fee, NSError * _Null_unspecified error))completion;

- (int64_t)amountForUnknownCurrencyString:(NSString * _Nullable)string;
- (int64_t)amountForDashString:(NSString * _Nullable)string;
- (int64_t)amountForBitcoinString:(NSString * _Nullable)string;
- (NSAttributedString * _Nonnull)attributedStringForDashAmount:(int64_t)amount;
- (NSAttributedString * _Nonnull)attributedStringForDashAmount:(int64_t)amount withTintColor:(UIColor* _Nonnull)color;
- (NSAttributedString * _Nonnull)attributedStringForDashAmount:(int64_t)amount withTintColor:(UIColor* _Nonnull)color useSignificantDigits:(BOOL)useSignificantDigits;
- (NSAttributedString * _Nonnull)attributedStringForDashAmount:(int64_t)amount withTintColor:(UIColor* _Nonnull)color dashSymbolSize:(CGSize)dashSymbolSize;
- (NSNumber * _Nonnull)numberForAmount:(int64_t)amount;
- (NSString * _Nonnull)stringForBitcoinAmount:(int64_t)amount;
- (NSString * _Nonnull)stringForDashAmount:(int64_t)amount;
- (int64_t)amountForBitcoinCurrencyString:(NSString * _Nonnull)string;
- (int64_t)amountForLocalCurrencyString:(NSString * _Nonnull)string;
- (NSString * _Nonnull)bitcoinCurrencyStringForAmount:(int64_t)amount;
- (NSString * _Nonnull)localCurrencyStringForDashAmount:(int64_t)amount;
- (NSString * _Nonnull)localCurrencyStringForBitcoinAmount:(int64_t)amount;

-(NSNumber* _Nonnull)localCurrencyDashPrice;

-(void)seedPhraseAfterAuthentication:(void (^ _Nullable)(NSString * _Nullable seedPhrase))completion;
-(void)setSeedPhrase:(NSString* _Nullable)seedPhrase;

-(void)upgradeExtendedKeysWithCompletion:(_Nullable UpgradeCompletionBlock)completion;

@end
