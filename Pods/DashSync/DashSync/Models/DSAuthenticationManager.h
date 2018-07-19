//
//  DSAuthenticationManager.h
//  DashSync
//
//  Created by Sam Westrich on 5/27/18.
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

#define PIN_UNLOCK_TIME_KEY     @"PIN_UNLOCK_TIME"
#define SECURE_TIME_KEY     @"SECURE_TIME"

typedef void (^PinCompletionBlock)(BOOL authenticatedOrSuccess, BOOL cancelled);
typedef void (^SeedPhraseCompletionBlock)(NSString * _Nullable seedPhrase);
typedef void (^SeedCompletionBlock)(NSData * _Nullable seed);

@class DSWallet,DSChain;

@interface DSAuthenticationManager : NSObject <UITextFieldDelegate>

@property (nonatomic, readonly, getter=isTouchIdEnabled) BOOL touchIdEnabled; // true if touch id is enabled
@property (nonatomic, readonly, getter=isPasscodeEnabled) BOOL passcodeEnabled; // true if device passcode is enabled
@property (nonatomic, assign) BOOL usesAuthentication;
@property (nonatomic, assign) BOOL didAuthenticate; // true if the user authenticated after this was last set to false
@property (nonatomic ,readonly) BOOL lockedOut;
@property (nonatomic, copy) NSDictionary * _Nullable userAccount; // client api user id and auth token
@property (nonatomic, readonly) NSTimeInterval secureTime; // last known time from an ssl server connection
@property (nonatomic, readonly) NSTimeInterval lockoutWaitTime;

+ (instancetype _Nullable)sharedInstance;
- (void)seedWithPrompt:(NSString * _Nullable)authprompt forWallet:(DSWallet* _Nonnull)wallet forAmount:(uint64_t)amount completion:(_Nullable SeedCompletionBlock)completion;//auth user,return seed
- (void)seedPhraseWithPrompt:(NSString * _Nullable)authprompt completion:(_Nullable SeedPhraseCompletionBlock)completion;; // authenticates user, returns seedPhrase
- (void)authenticateWithPrompt:(NSString * _Nullable)authprompt andTouchId:(BOOL)touchId alertIfLockout:(BOOL)alertIfLockout completion:(_Nullable PinCompletionBlock)completion; // prompt user to authenticate
- (void)setPinWithCompletion:(void (^ _Nullable)(BOOL success))completion; // prompts the user to set or change wallet pin and returns true if the pin was successfully set
-(void)requestKeyPasswordForSweepCompletion:(void (^_Nonnull)(NSString * password))completion cancel:(void (^_Nonnull)(void))cancel;

- (NSString *)promptForAmount:(uint64_t)amount fee:(uint64_t)fee address:(NSString *)address name:(NSString *)name memo:(NSString *)memo isSecure:(BOOL)isSecure errorMessage:(NSString*)errorMessage localCurrency:(NSString *)localCurrency localCurrencyAmount:(NSString *)localCurrencyAmount;

-(void)badKeyPasswordForSweepCompletion:(void (^_Nonnull)(void))completion cancel:(void (^_Nonnull)(void))cancel;

@end
