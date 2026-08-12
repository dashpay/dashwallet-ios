//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DWPaymentProcessor.h"

#import "DWGlobalOptions.h"
#import "DWPaymentInput+Private.h"
#import "DWPaymentInput.h"
#import "DWPaymentOutput+Private.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

/// Display-order txid hex from a wire-order txid (bytes reversed). Replaces the DashSync
/// `[NSString hexWithData:data.reverse]` categories for the callback-scheme URL.
static NSString *DWReversedHexString(NSData *data) {
    const uint8_t *bytes = data.bytes;
    const NSUInteger length = data.length;
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
    for (NSInteger i = (NSInteger)length - 1; i >= 0; i--) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [hex copy];
}

@interface DWPaymentProcessor ()

@property (nullable, nonatomic, strong) DWPaymentInput *paymentInput;

/// Retains the BIP70 coordinator for the duration of an async fetch/confirm-and-send.
@property (nullable, nonatomic, strong) id bip70Coordinator;

@property (nonatomic, assign) uint64_t amount;
/// The app-side send carrier for a plain-dash: send, set on the URI path. C8 step 4.
@property (nullable, nonatomic, strong) DWPaymentIntent *paymentIntent;

@property (nonatomic, assign) BOOL didSendRequestDelegateNotified;

@end

@implementation DWPaymentProcessor

- (void)processPaymentInput:(DWPaymentInput *)paymentInput {
    NSParameterAssert(self.delegate);

#if DASHPAY
    // Row #18: the DashSync "re-build input for a DashPay username"
    // path is retired — it resolved the sender through the frozen
    // Core Data contact graph (matchingDashpayUserInContext +
    // DSFriendRequestEntity) that no longer syncs. Pay-to-contact
    // now flows through the SwiftUI contacts screen →
    // WalletSendService.sendToContact, never through this processor.
#endif

    self.paymentInput = paymentInput;

    if (paymentInput.bip70Confirmation) {
        [self confirmBIP70Output:paymentInput.bip70Confirmation];
        return;
    }

    // App-side URI send path (scan / deeplink / pasteboard / plain-address). The scan/deeplink
    // case shows the amount screen (prefilled); everything else routes through the parsed URI
    // (BIP70 rURL / plain send → confirmPaymentIntent:). C8 step 4.
    if (paymentInput.paymentIntent) {
        if ((paymentInput.source == DWPaymentInputSource_ScanQR || paymentInput.source == DWPaymentInputSource_DeepLink) && paymentInput.parsedURI.isValidDashPaymentIntent) {
            [self requestAmountForPaymentIntent:paymentInput.paymentIntent];
        }
        else {
            [self confirmParsedPaymentInput];
        }
    }
}

- (void)provideAmount:(uint64_t)amount {
    self.amount = amount;

    NSParameterAssert(self.paymentIntent);
    [self confirmPaymentIntent:self.paymentIntent];
}

- (void)confirmPaymentOutput:(DWPaymentOutput *)paymentOutput {
    self.didSendRequestDelegateNotified = NO;

    // App-side BIP70 path: build + broadcast + POST the Payment via the Swift orchestrator.
    if (paymentOutput.bip70Confirmation) {
        [self broadcastBIP70PaymentOutput:paymentOutput];
        return;
    }

    // SwiftDashSDK path: tx is already prepared, just broadcast.
    // (`performSwiftDashSDKBroadcast:` fails with an explicit error if the prepared tx is missing.)
    [self broadcastSwiftDashSDKPaymentOutput:paymentOutput];
}

/// Authenticate user, then broadcast the pre-signed SwiftDashSDK transaction.
- (void)broadcastSwiftDashSDKPaymentOutput:(DWPaymentOutput *)paymentOutput {
    // Authenticate before broadcasting (PIN / biometric).
    BOOL skipAuth = [[DWGlobalOptions sharedInstance] spendingConfirmationDisabled] ||
                    paymentOutput.broadcastAuthorizationState == DWPaymentOutputBroadcastAuthorizationStateAlreadyAuthorized;

    if (skipAuth) {
        [self performSwiftDashSDKBroadcast:paymentOutput];
        return;
    }

    [DWWalletSendService authenticateSpendWithCompletion:^(BOOL authenticated, BOOL cancelled) {
        if (cancelled) {
            [self.delegate paymentProcessorDidCancelTransactionSigning:self];
            return;
        }
        if (!authenticated) {
            [self failedWithError:nil
                            title:NSLocalizedString(@"Couldn't make payment", nil)
                          message:NSLocalizedString(@"Authentication failed", nil)];
            return;
        }
        [self performSwiftDashSDKBroadcast:paymentOutput];
    }];
}

- (void)performSwiftDashSDKBroadcast:(DWPaymentOutput *)paymentOutput {
    NSString *address = paymentOutput.address;
    DWPreparedStandardSend *preparedSend = paymentOutput.preparedStandardSend;

    if (!preparedSend) {
        NSError *error = [NSError errorWithDomain:@"DashWallet.PaymentProcessor"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"Missing prepared transaction", nil)}];
        [self failedWithError:error
                        title:NSLocalizedString(@"Couldn't make payment", nil)
                      message:error.localizedDescription];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        [preparedSend broadcastAndReturnError:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSString *title = NSLocalizedString(@"Couldn't make payment", nil);
                if ([DWWalletSendService isBroadcastUnknownError:error]) {
                    title = NSLocalizedString(@"Transaction status unknown", nil);
                }
                else if ([DWWalletSendService isBroadcastRejectedError:error]) {
                    title = NSLocalizedString(@"Transaction not sent", nil);
                }
                [self failedWithError:error
                                title:title
                              message:error.localizedDescription];
            }
            else {
                [self sendCompletedToAddress:address
                                    txidWire:preparedSend.txidWire];
            }
        });
    });
}

#pragma mark - Private

/// Route a parsed payment URI: BIP70 request URL → fetch/verify; otherwise plain app-side send.
- (void)confirmParsedPaymentInput {
    DWParsedPaymentURI *parsed = self.paymentInput.parsedURI;

    if (parsed == nil) {
        // Defensive: every live input carries a parsed URI (`attachParsedURI:` is the only
        // `paymentIntent` producer). Fail visibly rather than guess a route.
        [self failedWithError:nil title:NSLocalizedString(@"Not a valid Dash address", nil) message:nil];
        return;
    }

    if (!parsed.isValidDashPaymentIntent) {
        // Not a payable dash: intent and no BIP70 request URL → reject. (Paper-wallet sweep — the old
        // WIF/BIP38 arm here — was dropped in C8 step 5; it needs an arbitrary-address UTXO FFI to return.)
        [self failedWithError:nil title:NSLocalizedString(@"Not a valid Dash address", nil) message:nil];
    }
    else if (parsed.rURL != nil) { // payment protocol over HTTP (app-side BIP70)
        __weak typeof(self) weakSelf = self;
        DWBIP70InteractiveCoordinator *coordinator = [[DWBIP70InteractiveCoordinator alloc] init];
        self.bip70Coordinator = coordinator;
        [coordinator fetchAndVerifyWithRequestURL:parsed.rURL
                                           scheme:parsed.scheme
                                   callbackScheme:parsed.callbackScheme
                                       completion:^(DWBIP70ConfirmationBox *_Nullable box, NSError *_Nullable error) {
                                           __strong typeof(weakSelf) strongSelf = weakSelf;
                                           if (!strongSelf) {
                                               return;
                                           }
                                           strongSelf.bip70Coordinator = nil;

                                           if (box) {
                                               [strongSelf confirmBIP70Output:box];
                                           }
                                           else if (parsed.isAddressValidForCurrentNetwork) {
                                               // fetch failed but there's a valid fallback address → plain send (app-side, C8 step 4)
                                               [strongSelf confirmPaymentIntent:strongSelf.paymentInput.paymentIntent];
                                           }
                                           else {
                                               [strongSelf failedWithError:error
                                                                     title:NSLocalizedString(@"Couldn't make payment", nil)
                                                                   message:error.localizedDescription];
                                           }
                                       }];
    }
    else { // plain send (valid dash intent, no BIP70 request URL) → app-side (C8 step 4)
        [self confirmPaymentIntent:self.paymentInput.paymentIntent];
    }
}

#pragma mark - App-side BIP70 (Swift orchestrator)

/// Build the confirm-screen output from a verified BIP70 `Confirmation` box (no build, no spend).
- (void)confirmBIP70Output:(id)bip70Confirmation {
    DWPaymentOutput *paymentOutput = [DWBIP70PaymentOutputFactory paymentOutputFromBox:bip70Confirmation];
    [self.delegate paymentProcessor:self confirmPaymentOutput:paymentOutput];
}

/// Authenticate (PIN / biometric), then build + broadcast + POST via the Swift orchestrator.
- (void)broadcastBIP70PaymentOutput:(DWPaymentOutput *)paymentOutput {
    NSError *restoreSyncError = [DWCoreSpendAvailability coreSpendBlockedError];
    if (restoreSyncError != nil) {
        [self failedWithError:restoreSyncError
                        title:NSLocalizedString(@"Couldn't make payment", nil)
                      message:restoreSyncError.localizedDescription];
        return;
    }

    BOOL skipAuth = [[DWGlobalOptions sharedInstance] spendingConfirmationDisabled] ||
                    paymentOutput.broadcastAuthorizationState == DWPaymentOutputBroadcastAuthorizationStateAlreadyAuthorized;

    if (skipAuth) {
        [self performBIP70Send:paymentOutput];
        return;
    }

    [DWWalletSendService authenticateSpendWithCompletion:^(BOOL authenticated, BOOL cancelled) {
        if (cancelled) {
            [self.delegate paymentProcessorDidCancelTransactionSigning:self];
            return;
        }
        if (!authenticated) {
            [self failedWithError:nil
                            title:NSLocalizedString(@"Couldn't make payment", nil)
                          message:NSLocalizedString(@"Authentication failed", nil)];
            return;
        }
        [self performBIP70Send:paymentOutput];
    }];
}

- (void)performBIP70Send:(DWPaymentOutput *)paymentOutput {
    [self.delegate paymentProcessor:self showProgressHUDWithMessage:NSLocalizedString(@"Sending", nil)];

    DWBIP70InteractiveCoordinator *coordinator = [[DWBIP70InteractiveCoordinator alloc] init];
    self.bip70Coordinator = coordinator; // retain for the duration of the async send

    [coordinator confirmAndSend:paymentOutput.bip70Confirmation
                     completion:^(DWBIP70SendResultBox *_Nullable result, NSError *_Nullable error) {
                         [self.delegate paymentInputProcessorHideProgressHUD:self];
                         self.bip70Coordinator = nil;

                         if (error || result == nil) {
                             [self failedWithError:error
                                             title:NSLocalizedString(@"Couldn't make payment", nil)
                                           message:error.localizedDescription];
                             return;
                         }

                         if (!self.didSendRequestDelegateNotified) {
                             self.didSendRequestDelegateNotified = YES;
                             [self.delegate paymentProcessor:self
                                         didSendWithTxidWire:result.txidWire];
                         }

                         if (result.callbackURL) {
                             [[UIApplication sharedApplication] openURL:result.callbackURL
                                                                options:@{}
                                                      completionHandler:nil];
                         }
                     }];
}

#pragma mark - App-side plain send (SwiftDashSDK)

/// App-side plain-dash: send (C8 step 4): read address/amount/display straight off the intent and
/// hand to the shared SwiftDashSDK build+confirm.
- (void)confirmPaymentIntent:(DWPaymentIntent *)intent {
    self.paymentIntent = intent;

    // A fixed send amount (payToAddress:) rides on the intent; the amount screen sets self.amount.
    if (self.amount == 0) {
        self.amount = intent.amount;
    }

    // Still no amount (a bare pasted/entered address) → ask, mirroring DashSync's amount round-trip.
    if (self.amount == 0) {
        [self requestAmountForPaymentIntent:intent];
        return;
    }

    NSString *address = intent.address;
    if (address.length == 0) {
        [self failedWithError:nil title:NSLocalizedString(@"Not a valid Dash address", nil) message:nil];
        return;
    }

    self.didSendRequestDelegateNotified = NO;
    [self confirmSwiftDashSDKSendToAddress:address
                                    amount:self.amount
                                      name:intent.label
                                      memo:intent.message
                             localCurrency:intent.fiatCurrencyCode];
}

/// Push the amount screen for an intent-driven send (destination is the plain address — no PKI/lock).
- (void)requestAmountForPaymentIntent:(DWPaymentIntent *)intent {
    self.paymentIntent = intent;
    [self.delegate paymentProcessor:self
        requestAmountWithDestination:intent.address ?: @""
                              amount:intent.amount];
}

/// Shared SwiftDashSDK build+sign then show the confirmation UI with the real fee.
- (void)confirmSwiftDashSDKSendToAddress:(NSString *)address
                                  amount:(uint64_t)amount
                                    name:(nullable NSString *)name
                                    memo:(nullable NSString *)memo
                           localCurrency:(nullable NSString *)localCurrency {
    [[DWWalletSendService sharedService]
        prepareStandardSendForConfirmationWithAddress:address
                                               amount:amount
                                           completion:^(DWPreparedStandardSend *_Nullable preparedSend, NSError *_Nullable error) {
                                               if (error || !preparedSend) {
                                                   if (error && [DWWalletSendService isAuthenticationCancelledError:error]) {
                                                       [self.delegate paymentProcessorDidCancelTransactionSigning:self];
                                                       return;
                                                   }

                                                   [self failedWithError:error
                                                                   title:NSLocalizedString(@"Couldn't make payment", nil)
                                                                 message:error.localizedDescription];
                                                   return;
                                               }

                                               // Legacy parity: the confirm sheet's display math assumes `amount` is the
                                               // all-in wallet debit (DashSync passed amountSent − amountReceived), so the
                                               // headline (`amount − fee`) shows what the recipient gets and "Total" shows
                                               // the true debit. `preparedSend.amount` keeps the recipient amount.
                                               DWPaymentOutput *paymentOutput = [[DWPaymentOutput alloc]
                                                               initWithAddress:address
                                                                        amount:amount + preparedSend.fee
                                                                           fee:preparedSend.fee
                                                                          name:name
                                                                          memo:memo
                                                                      isSecure:NO
                                                                 localCurrency:localCurrency
                                                          preparedStandardSend:preparedSend
                                                   broadcastAuthorizationState:DWPaymentOutputBroadcastAuthorizationStateAlreadyAuthorized];

                                               [self.delegate paymentProcessor:self confirmPaymentOutput:paymentOutput];
                                           }];
}

#pragma mark - Handlers

/// Successful SwiftDashSDK broadcast: notify the delegate and fire the URI's callback scheme.
- (void)sendCompletedToAddress:(NSString *)address
                      txidWire:(NSData *)txidWire {
    [self.delegate paymentProcessor:self didSendWithTxidWire:txidWire];

    self.didSendRequestDelegateNotified = YES;

    [self handleCallbackSchemeIfNeeded:self.paymentIntent.callbackScheme
                               address:address
                              txidWire:txidWire];

    [self reset];
}

- (void)handleCallbackSchemeIfNeeded:(nullable NSString *)callbackScheme
                             address:(NSString *)address
                            txidWire:(NSData *)txidWire {
    if (callbackScheme) {
        // Same display-order hex as before the txid retype (wire bytes reversed).
        NSString *txid = DWReversedHexString(txidWire);
        NSString *encodedAddress = [address stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *callbackString = [callbackScheme
            stringByAppendingFormat:@"://callback=payack&address=%@&txid=%@",
                                    encodedAddress,
                                    txid];
        NSURL *callbackURL = [NSURL URLWithString:callbackString];
        if (callbackURL) {
            [[UIApplication sharedApplication] openURL:callbackURL
                                               options:@{}
                                     completionHandler:nil];
        }
    }
}

- (void)failedWithError:(nullable NSError *)error title:(nullable NSString *)title message:(nullable NSString *)message {
    [self.delegate paymentProcessor:self didFailWithError:error title:title message:message];
    [self cancel];
}

- (void)cancel {
    self.amount = 0;
}

- (void)reset {
    self.paymentInput = nil;
    self.paymentIntent = nil;
    [self cancel];
}

@end

NS_ASSUME_NONNULL_END
