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

#import "CurrencyExchanger_Objc.h"
#import "DSTransaction+DashWallet.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWPaymentInput+Private.h"
#import "DWPaymentInput.h"
#import "DWPaymentInputBuilder.h"
#import "DWPaymentOutput+Private.h"
#import "dashwallet-Swift.h"

#if DASHPAY
#import "DWDPUserObject.h"
// if MOCK_DASHPAY
#import "DWDashPayConstants.h"
#endif

NS_ASSUME_NONNULL_BEGIN

#define LOCK @"\xF0\x9F\x94\x92" // unicode lock symbol U+1F512 (utf-8)
#define REDX @"\xE2\x9D\x8C"     // unicode cross mark U+274C, red x emoji (utf-8)
#define NBSP @"\xC2\xA0"         // no-break space (utf-8)

static NSString *sanitizeString(NSString *s) {
    NSMutableString *sane = [NSMutableString stringWithString:(s) ? s : @""];
    CFStringTransform((CFMutableStringRef)sane, NULL, kCFStringTransformToUnicodeName, NO);
    return sane;
}


@interface DWPaymentProcessor ()


@property (nullable, nonatomic, strong) DWPaymentInput *paymentInput;

/// Retains the BIP70 coordinator for the duration of an async fetch/confirm-and-send.
@property (nullable, nonatomic, strong) id bip70Coordinator;

@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, assign) BOOL canChangeAmount;
@property (nonatomic, assign) BOOL shouldClearPasteboard;
@property (nullable, nonatomic, strong) DSPaymentProtocolRequest *request;
/// The app-side send carrier for a plain-dash: send. Set on the URI path (mutually exclusive with
/// `request`, which survives for the C10 DashPay / real-BIP70 / file paths). C8 step 4.
@property (nullable, nonatomic, strong) DWPaymentIntent *paymentIntent;

// Tx Manager blocks
@property (nonatomic, assign) BOOL didSendRequestDelegateNotified;
@property (nonatomic, copy) DSTransactionChallengeBlock challengeBlock;
@property (nonatomic, copy) DSTransactionSigningCompletionBlock signedCompletionBlock;
@property (nonatomic, copy) DSTransactionErrorNotificationBlock errorNotificationBlock;

@end

@implementation DWPaymentProcessor

- (instancetype)initWithDelegate:(id<DWPaymentProcessorDelegate>)delegate {
    self = [self init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

- (id)init {
    self = [super init];
    if (self) {
        __weak typeof(self) weakSelf = self;

        _challengeBlock = ^(NSString *_Nonnull challengeTitle, NSString *_Nonnull challengeMessage, NSString *_Nonnull actionTitle, void (^_Nonnull actionBlock)(void), void (^_Nonnull cancelBlock)(void)) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf requestUserActionTitle:challengeTitle
                                       message:challengeMessage
                                   actionTitle:actionTitle
                                   cancelBlock:cancelBlock
                                   actionBlock:actionBlock];
        };

        _signedCompletionBlock = ^BOOL(DSTransaction *_Nonnull tx, NSError *_Nullable error, BOOL cancelled) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return NO;
            }

            NSCAssert([NSThread isMainThread], @"Main thread is assumed here");

            return [strongSelf txManagerSignedCompletion:cancelled error:error];
        };

        _errorNotificationBlock = ^(NSError *_Nonnull error, NSString *_Nonnull errorTitle, NSString *_Nonnull errorMessage, BOOL shouldCancel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            if (errorTitle || errorMessage) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf failedWithError:error title:errorTitle message:errorMessage];
                });
            }
        };
    }

    return self;
}

- (void)processPaymentInput:(DWPaymentInput *)paymentInput {
    NSParameterAssert(self.delegate);

#if DASHPAY
    // re-build input if it's DashPay-compatible
    NSString *requestUsername = paymentInput.request.dashpayUsername;
    if (requestUsername) {
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;

        if (MOCK_DASHPAY && myBlockchainIdentity == NULL) {
            NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

            if (username != nil) {
                myBlockchainIdentity = [[DWEnvironment sharedInstance].currentWallet createBlockchainIdentityForUsername:username];
            }
        }

        if (myBlockchainIdentity) {
            NSManagedObjectContext *context = NSManagedObjectContext.viewContext;
            DSDashpayUserEntity *dashpayUserEntity = [myBlockchainIdentity matchingDashpayUserInContext:context];
            DSBlockchainIdentity *requestIdentity = nil;
            for (DSFriendRequestEntity *friendRequest in dashpayUserEntity.incomingRequests) {
                if ([[friendRequest.sourceContact.associatedBlockchainIdentity.dashpayUsername stringValue] isEqualToString:requestUsername]) {
                    requestIdentity = [friendRequest.sourceContact.associatedBlockchainIdentity blockchainIdentity];
                    break;
                }
            }


            if (requestIdentity) {
                paymentInput.userItem = [[DWDPUserObject alloc] initWithBlockchainIdentity:requestIdentity];
            }
        }
    }
#endif

    self.paymentInput = paymentInput;

    if (paymentInput.bip70Confirmation) {
        [self confirmBIP70Output:paymentInput.bip70Confirmation];
        return;
    }

    if (paymentInput.paymentIntent) {
        // App-side URI send path (scan / deeplink / pasteboard / plain-address). The scan/deeplink
        // case shows the amount screen (prefilled); everything else routes through confirmRequest:
        // (sweep D2 / BIP70 rURL / plain send → confirmPaymentIntent:). C8 step 4 — no synthetic
        // DSPaymentProtocolRequest here.
        if ((paymentInput.source == DWPaymentInputSource_ScanQR || paymentInput.source == DWPaymentInputSource_DeepLink) && paymentInput.parsedURI.isValidDashPaymentIntent) {
            [self requestAmountForPaymentIntent:paymentInput.paymentIntent];
        }
        else {
            self.canChangeAmount = paymentInput.canChangeAmount;
            [self confirmRequest:paymentInput.request];
        }
    }
    else if (paymentInput.request) {
        // C10 DashPay BlockchainUser (no parsedURI / no intent): the synthetic conversion survives.
        self.canChangeAmount = paymentInput.canChangeAmount;
        [self confirmRequest:paymentInput.request];
    }
    else if (paymentInput.source == DWPaymentInputSource_BlockchainUser) {
        self.canChangeAmount = paymentInput.canChangeAmount;
        [self confirmRequest:paymentInput.request];
    }
}

- (void)provideAmount:(uint64_t)amount {
    self.amount = amount;

    if (self.paymentIntent) {
        [self confirmPaymentIntent:self.paymentIntent];
        return;
    }

    NSParameterAssert(self.request);

    [self confirmProtocolRequest:self.request];
}

- (void)confirmPaymentOutput:(DWPaymentOutput *)paymentOutput {
    NSString *address = paymentOutput.address;
    DSPaymentProtocolRequest *protocolRequest = paymentOutput.protocolRequest;

    self.request = protocolRequest;
    self.didSendRequestDelegateNotified = NO;

    // App-side BIP70 path: build + broadcast + POST the Payment via the Swift orchestrator.
    if (paymentOutput.bip70Confirmation) {
        [self broadcastBIP70PaymentOutput:paymentOutput];
        return;
    }

    // SwiftDashSDK path: tx is already prepared, just broadcast.
    if (paymentOutput.preparedStandardSend) {
        [self broadcastSwiftDashSDKPaymentOutput:paymentOutput];
        return;
    }

    // Existing DashSync path: sign and publish via DSTransactionManager.
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    const BOOL requiresSpendingAuthenticationPrompt = ![[DWGlobalOptions sharedInstance] spendingConfirmationDisabled];
    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;

    [chainManager.transactionManager
        signAndPublishTransaction:paymentOutput.tx
        createdFromProtocolRequest:protocolRequest
        fromAccount:account
        toAddress:address
        requiresSpendingAuthenticationPrompt:requiresSpendingAuthenticationPrompt
        promptMessage:nil
        forAmount:paymentOutput.amount
        keepAuthenticatedIfErrorAfterAuthentication:NO
        mixedOnly:NO
        requestingAdditionalInfo:^(DSRequestingAdditionalInfo additionalInfoRequestType) {
            [self txManagerRequestingAdditionalInfo:additionalInfoRequestType
                                    protocolRequest:protocolRequest];
        }
        presentChallenge:self.challengeBlock
        transactionCreationCompletion:^BOOL(DSTransaction *_Nonnull tx, NSString *_Nonnull prompt, uint64_t amount, uint64_t proposedFee, NSArray<NSString *> *addresses, BOOL isSecure) {
            [self txManagerConfirmTx:tx
                     protocolRequest:protocolRequest
                              amount:amount
                                 fee:proposedFee
                             address:addresses.firstObject
                                name:protocolRequest.commonName
                                memo:protocolRequest.details.memo
                            isSecure:isSecure
                       localCurrency:protocolRequest.requestedFiatAmountCurrencyCode];
            // don't sign tx automatically
            return NO;
        }
        signedCompletion:self.signedCompletionBlock
        publishedCompletion:^(DSTransaction *_Nonnull tx, NSError *_Nullable error, BOOL sent) {
            if (error) {
                if (error.code == -1009) {
                    [self failedWithError:error
                                    title:NSLocalizedString(@"Could not connect to the Dash network, please check that you are connected to the internet.", nil)
                                  message:nil];
                }
                else {
                    [self failedWithError:error
                                    title:NSLocalizedString(@"Couldn't make payment", nil)
                                  message:nil];
                }
            }
            else {
                [self txManagerPublishedCompletion:address
                                              sent:sent
                                          txidWire:tx.txHashData];
            }
        }
        requestRelayCompletion:^(DSTransaction *_Nonnull tx, DSPaymentProtocolACK *_Nonnull ack, BOOL relayedToServer) {
            [self txManagerRequestRelayCompletion:address
                                  protocolRequest:protocolRequest
                                  relayedToServer:relayedToServer
                                               tx:tx];
        }
        errorNotificationBlock:self.errorNotificationBlock];
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
                [self failedWithError:error
                                title:NSLocalizedString(@"Couldn't make payment", nil)
                              message:error.localizedDescription];
            }
            else {
                [self txManagerPublishedCompletion:address
                                              sent:YES
                                          txidWire:preparedSend.txidWire];
            }
        });
    });
}

#pragma mark - Private

- (void)confirmRequest:(DSPaymentRequest *)request {
    DWParsedPaymentURI *parsed = self.paymentInput.parsedURI;

    if (parsed == nil) {
        // BlockchainUser inputs (friendship-derived address) carry no parsed URI — their courier is a
        // bare valid address that goes straight to conversion. TODO(C10): fold DashPay sends into the box.
        if (request.isValidAsNonDashpayPaymentRequest) {
            [self confirmProtocolRequest:[self protocolRequestFromPaymentRequest:request]];
        }
        else {
            [self failedWithError:nil title:NSLocalizedString(@"Not a valid Dash address", nil) message:nil];
        }
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

- (DSPaymentProtocolRequest *)protocolRequestFromPaymentRequest:(DSPaymentRequest *)request {
    // `request.protocolRequest` is a legacy method and shouldn't be used directly.
    // `myBlockchainIdentity` can be nil.
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    NSManagedObjectContext *context = [NSManagedObjectContext viewContext];

    return [request protocolRequestForBlockchainIdentity:myBlockchainIdentity
                                               onAccount:account
                                               inContext:context];
}

#pragma mark - App-side BIP70 (Swift orchestrator)

/// Build the confirm-screen output from a verified BIP70 `Confirmation` box (no build, no spend).
- (void)confirmBIP70Output:(id)bip70Confirmation {
    DWPaymentOutput *paymentOutput = [DWBIP70PaymentOutputFactory paymentOutputFromBox:bip70Confirmation
                                                                              userItem:self.paymentInput.userItem];
    [self.delegate paymentProcessor:self confirmPaymentOutput:paymentOutput];
}

/// Authenticate (PIN / biometric), then build + broadcast + POST via the Swift orchestrator.
- (void)broadcastBIP70PaymentOutput:(DWPaymentOutput *)paymentOutput {
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
                                              didSendRequest:nil
                                                    txidWire:result.txidWire
                                                 contactItem:paymentOutput.userItem];
                         }

                         if (result.callbackURL) {
                             [[UIApplication sharedApplication] openURL:result.callbackURL
                                                                options:@{}
                                                      completionHandler:nil];
                         }
                     }];
}

- (void)confirmProtocolRequest:(DSPaymentProtocolRequest *)protocolRequest {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;

    NSString *address = [NSString addressWithScriptPubKey:protocolRequest.details.outputScripts.firstObject
                                                  onChain:chain];

    self.didSendRequestDelegateNotified = NO;
    BOOL hasBIP70 = protocolRequest.details.paymentURL.length > 0;

    // Route non-BIP70 sends through SwiftDashSDK.
    if (!hasBIP70 && self.amount > 0 && address.length > 0) {
        [self confirmProtocolRequestViaSwiftDashSDK:protocolRequest
                                            address:address];
        return;
    }

    // Existing DashSync path (CoinJoin, BIP70, or edge cases).
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
    const BOOL addressIsFromPasteboard = self.paymentInput.source == DWPaymentInputSource_Pasteboard;

    [chainManager.transactionManager
        confirmProtocolRequest:protocolRequest
        forAmount:self.amount
        fromAccount:account
        acceptInternalAddress:NO
        acceptReusingAddress:NO
        addressIsFromPasteboard:addressIsFromPasteboard
        acceptUncertifiedPayee:NO
        mixedOnly:NO
        requiresSpendingAuthenticationPrompt:YES
        keepAuthenticatedIfErrorAfterAuthentication:NO
        requestingAdditionalInfo:^(DSRequestingAdditionalInfo additionalInfoRequestType) {
            [self txManagerRequestingAdditionalInfo:additionalInfoRequestType
                                    protocolRequest:protocolRequest];
        }
        presentChallenge:self.challengeBlock
        transactionCreationCompletion:^BOOL(DSTransaction *_Nonnull tx, NSString *_Nonnull prompt, uint64_t amount, uint64_t proposedFee, NSArray<NSString *> *addresses, BOOL isSecure) {
            [self txManagerConfirmTx:tx
                     protocolRequest:protocolRequest
                              amount:amount
                                 fee:proposedFee
                             address:addresses.firstObject
                                name:protocolRequest.commonName
                                memo:protocolRequest.details.memo
                            isSecure:isSecure
                       localCurrency:protocolRequest.requestedFiatAmountCurrencyCode];
            // don't sign tx automatically
            return NO;
        }
        signedCompletion:self.signedCompletionBlock
        publishedCompletion:^(DSTransaction *_Nonnull tx, NSError *_Nullable error, BOOL sent) {
            [self txManagerPublishedCompletion:address
                                          sent:sent
                                      txidWire:tx.txHashData];
        }
        requestRelayCompletion:^(DSTransaction *_Nonnull tx, DSPaymentProtocolACK *_Nonnull ack, BOOL relayedToServer) {
            [self txManagerRequestRelayCompletion:address
                                  protocolRequest:protocolRequest
                                  relayedToServer:relayedToServer
                                               tx:tx];
        }
        errorNotificationBlock:self.errorNotificationBlock];
}

/// Build+sign the synthetic (C10 / file) protocol request via SwiftDashSDK, then confirm.
- (void)confirmProtocolRequestViaSwiftDashSDK:(DSPaymentProtocolRequest *)protocolRequest
                                      address:(NSString *)address {
    [self confirmSwiftDashSDKSendToAddress:address
                                    amount:self.amount
                                      name:protocolRequest.commonName
                                      memo:protocolRequest.details.memo
                             localCurrency:protocolRequest.requestedFiatAmountCurrencyCode
                           protocolRequest:protocolRequest];
}

/// App-side plain-dash: send (C8 step 4): read address/amount/display straight off the intent and
/// hand to the shared SwiftDashSDK build+confirm — no synthetic DSPaymentProtocolRequest, so no
/// `protocolRequestForBlockchainIdentity:onAccount:inContext:` (wallet-identity + CoreData) drag.
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
                             localCurrency:intent.fiatCurrencyCode
                           protocolRequest:nil];
}

/// Push the amount screen for an intent-driven send (destination is the plain address — no PKI/lock).
- (void)requestAmountForPaymentIntent:(DWPaymentIntent *)intent {
    self.paymentIntent = intent;
    [self.delegate paymentProcessor:self
        requestAmountWithDestination:intent.address ?: @""
                              amount:intent.amount
                         contactItem:self.paymentInput.userItem];
}

/// Shared SwiftDashSDK build+sign then show the confirmation UI with the real fee. `protocolRequest`
/// is nil for the app-side intent path, the real request on the DashSync / C10 / file path.
- (void)confirmSwiftDashSDKSendToAddress:(NSString *)address
                                  amount:(uint64_t)amount
                                    name:(nullable NSString *)name
                                    memo:(nullable NSString *)memo
                           localCurrency:(nullable NSString *)localCurrency
                         protocolRequest:(nullable DSPaymentProtocolRequest *)protocolRequest {
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
                                                                    initWithTx:nil
                                                               protocolRequest:protocolRequest
                                                                        amount:amount + preparedSend.fee
                                                                           fee:preparedSend.fee
                                                                       address:address
                                                                          name:name
                                                                          memo:memo
                                                                      isSecure:NO
                                                                 localCurrency:localCurrency
                                                                      userItem:self.paymentInput.userItem
                                                          preparedStandardSend:preparedSend
                                                   broadcastAuthorizationState:DWPaymentOutputBroadcastAuthorizationStateAlreadyAuthorized];

                                               [self.delegate paymentProcessor:self confirmPaymentOutput:paymentOutput];
                                           }];
}

#pragma mark - Transaction Manager Callbacks

- (void)txManagerRequestingAdditionalInfo:(DSRequestingAdditionalInfo)additionalInfoRequestType
                          protocolRequest:(DSPaymentProtocolRequest *)protocolRequest {
    if (additionalInfoRequestType == DSRequestingAdditionalInfo_Amount) {
        [self reqeustAmountForProtocolRequest:protocolRequest];
    }
    else if (additionalInfoRequestType == DSRequestingAdditionalInfo_CancelOrChangeAmount) {
        [self cancelOrChangeAmount];
    }
}

- (BOOL)txManagerSignedCompletion:(BOOL)cancelled error:(NSError *_Nullable)error {
    if (cancelled) {
        [self cancelOrChangeAmount];
    }
    else if (error) {
        [self failedWithError:error
                        title:NSLocalizedString(@"Couldn't make payment", nil)
                      message:error.localizedDescription];
    }
    else {
        // NOP
        // Previous app version hid amount screen here
    }
    return YES;
}

- (void)txManagerPublishedCompletion:(NSString *)address
                                sent:(BOOL)sent
                            txidWire:(NSData *)txidWire {
    if (sent) {
        [self.delegate paymentProcessor:self didSendRequest:self.request txidWire:txidWire contactItem:self.paymentInput.userItem];

        self.didSendRequestDelegateNotified = YES;

        // callbackScheme rides on whichever carrier drove this send (intent for plain-dash:, the
        // synthetic/real request for C10).
        [self handleCallbackSchemeIfNeeded:(self.request.callbackScheme ?: self.paymentIntent.callbackScheme)
                                   address:address
                                  txidWire:txidWire];

        [self reset];
    }
}

- (void)txManagerRequestRelayCompletion:(NSString *)address
                        protocolRequest:(DSPaymentProtocolRequest *_Nonnull)protocolRequest
                        relayedToServer:(BOOL)relayedToServer
                                     tx:(DSTransaction *_Nonnull)tx {
    if (relayedToServer) {
        if (!self.didSendRequestDelegateNotified) {
            [self.delegate paymentProcessor:self didSendRequest:protocolRequest txidWire:tx.txHashData contactItem:self.paymentInput.userItem];
        }

        [self handleCallbackSchemeIfNeeded:protocolRequest.callbackScheme
                                   address:address
                                  txidWire:tx.txHashData];
    }

    [self reset];
}

- (void)txManagerConfirmTx:(DSTransaction *)tx
           protocolRequest:(DSPaymentProtocolRequest *)protocolRequest
                    amount:(uint64_t)amount
                       fee:(uint64_t)fee
                   address:(NSString *)address
                      name:(NSString *_Nullable)name
                      memo:(NSString *_Nullable)memo
                  isSecure:(BOOL)isSecure
             localCurrency:(NSString *_Nullable)localCurrency {
    DWPaymentOutput *paymentOutput = [[DWPaymentOutput alloc] initWithTx:tx
                                                         protocolRequest:protocolRequest
                                                                  amount:amount
                                                                     fee:tx.feeUsed
                                                                 address:address
                                                                    name:name
                                                                    memo:memo
                                                                isSecure:isSecure
                                                           localCurrency:localCurrency
                                                                userItem:self.paymentInput.userItem];
    [self.delegate paymentProcessor:self confirmPaymentOutput:paymentOutput];
}

#pragma mark - Handlers

- (void)reqeustAmountForProtocolRequest:(DSPaymentProtocolRequest *)request {
    self.request = request;

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    NSString *sendingDestination = nil;
    if (request.commonName.length > 0) {
        if (request.isValid && ![request.pkiType isEqual:@"none"]) {
            sendingDestination = [LOCK @" " stringByAppendingString:sanitizeString(request.commonName)];
        }
        else if (request.errorMessage.length > 0) {
            sendingDestination = [REDX @" " stringByAppendingString:sanitizeString(request.commonName)];
        }
        else {
            sendingDestination = sanitizeString(request.commonName);
        }
    }
    else {
        sendingDestination = [NSString addressWithScriptPubKey:request.details.outputScripts.firstObject
                                                       onChain:chain];
    }

    // The amount screen only ever read the output-amount sum off `details` for its pre-fill; compute
    // it here and pass the scalar (C8 step 4 dropped DSPaymentProtocolDetails from the delegate).
    uint64_t prefillAmount = 0;
    for (NSNumber *outputAmount in request.details.outputAmounts) {
        prefillAmount += outputAmount.unsignedLongLongValue;
    }

    [self.delegate paymentProcessor:self
        requestAmountWithDestination:sendingDestination
                              amount:prefillAmount
                         contactItem:self.paymentInput.userItem];
}

- (void)requestUserActionTitle:(nullable NSString *)title
                       message:(nullable NSString *)message
                   actionTitle:(NSString *)actionTitle
                   cancelBlock:(void (^)(void))cancelBlock
                   actionBlock:(void (^)(void))actionBlock {
    [self.delegate paymentProcessor:self
             requestUserActionTitle:title
                            message:message
                        actionTitle:actionTitle
                        cancelBlock:cancelBlock
                        actionBlock:actionBlock];
}

- (void)cancelOrChangeAmount {
    [self.delegate paymentProcessorDidCancelTransactionSigning:self];

    if (self.canChangeAmount && (self.request || self.paymentIntent) && self.amount == 0) {
        void (^cancelBlock)(void) = ^{
            [self cancelPayment];
        };

        void (^changeBlock)(void) = ^{
            if (self.paymentIntent) {
                [self confirmPaymentIntent:self.paymentIntent];
            }
            else {
                [self confirmProtocolRequest:self.request];
            }
        };

        [self requestUserActionTitle:NSLocalizedString(@"Change payment amount?", nil)
                             message:nil
                         actionTitle:NSLocalizedString(@"Change", @"A verb. Action button title for an alert 'Change payment amount?'")
                         cancelBlock:cancelBlock
                         actionBlock:changeBlock];
    }
    else {
        [self cancelPayment];
    }
}

- (void)handleCallbackSchemeIfNeeded:(nullable NSString *)callbackScheme
                             address:(NSString *)address
                            txidWire:(NSData *)txidWire {
    if (callbackScheme) {
        // Same display-order hex as before the txid retype (wire bytes reversed).
        NSString *txid = [NSString hexWithData:txidWire.reverse];
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

- (void)cancelPayment {
    [self cancel];
}

- (void)failedWithError:(nullable NSError *)error title:(nullable NSString *)title message:(nullable NSString *)message {
    [self.delegate paymentProcessor:self didFailWithError:error title:title message:message];
    [self cancel];
}

- (void)cancel {
    self.amount = 0;
    self.canChangeAmount = NO;
    self.shouldClearPasteboard = NO;
}

- (void)reset {
    self.paymentInput = nil;
    self.request = nil;
    self.paymentIntent = nil;
    if (self.shouldClearPasteboard) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = @"";
    }
    [self cancel];
}

@end

NS_ASSUME_NONNULL_END
