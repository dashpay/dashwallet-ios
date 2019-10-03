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

#import "DWEnvironment.h"
#import "DWPaymentInput.h"
#import "DWPaymentOutput+Private.h"

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

@property (nullable, nonatomic, weak) id<DWPaymentProcessorDelegate> delegate;

@property (readonly, nullable, nonatomic, strong) DWPaymentInput *paymentInput;

@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, assign) BOOL canChangeAmount;
@property (nonatomic, assign) BOOL shouldClearPasteboard;
@property (nullable, nonatomic, strong) DSPaymentProtocolRequest *request;

// Tx Manager blocks
@property (nonatomic, assign) BOOL didSendRequestDelegateNotified;
@property (nonatomic, copy) DSTransactionChallengeBlock challengeBlock;
@property (nonatomic, copy) DSTransactionSigningCompletionBlock signedCompletionBlock;
@property (nonatomic, copy) DSTransactionErrorNotificationBlock errorNotificationBlock;

@end

@implementation DWPaymentProcessor

- (instancetype)initWithDelegate:(id<DWPaymentProcessorDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;

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

        _errorNotificationBlock = ^(NSString *_Nonnull errorTitle, NSString *_Nonnull errorMessage, BOOL shouldCancel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            if (errorTitle || errorMessage) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf failedWithTitle:errorTitle message:errorMessage];
                });
            }
        };
    }
    return self;
}

- (void)processPaymentInput:(DWPaymentInput *)paymentInput {
    NSParameterAssert(self.delegate);

    self.shouldClearPasteboard = paymentInput.source == DWPaymentInputSource_Pasteboard;

    if (paymentInput.request) {
        self.canChangeAmount = paymentInput.canChangeAmount;
        [self confirmRequest:paymentInput.request];
    }
    else if (paymentInput.protocolRequest) {
        self.canChangeAmount = paymentInput.canChangeAmount;
        [self confirmProtocolRequest:paymentInput.protocolRequest];
    }
}

- (void)processFile:(NSData *)file {
    NSParameterAssert(self.delegate);

    [self handleFile:file];
}

- (void)provideAmount:(uint64_t)amount usedInstantSend:(BOOL)usedInstantSend {
    self.amount = amount;

    NSParameterAssert(self.request);

    [self.request updateForRequestsInstantSend:usedInstantSend
                           requiresInstantSend:self.request.requiresInstantSend];
    [self confirmProtocolRequest:self.request];
}

- (void)confirmPaymentOutput:(DWPaymentOutput *)paymentOutput {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    NSString *address = paymentOutput.address;
    DSPaymentProtocolRequest *protocolRequest = paymentOutput.protocolRequest;

    self.didSendRequestDelegateNotified = NO;

    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
    [chainManager.transactionManager
        signAndPublishTransaction:paymentOutput.tx
        createdFromProtocolRequest:protocolRequest
        fromAccount:account
        toAddress:address
        withPrompt:@""
        forAmount:paymentOutput.amount
        requestingAdditionalInfo:^(DSRequestingAdditionalInfo additionalInfoRequestType) {
            [self txManagerRequestingAdditionalInfo:additionalInfoRequestType
                                    protocolRequest:protocolRequest];
        }
        presentChallenge:self.challengeBlock
        transactionCreationCompletion:^BOOL(DSTransaction *_Nonnull tx, NSString *_Nonnull prompt, uint64_t amount, NSArray<NSString *> *addresses, BOOL isSecure) {
            [self txManagerConfirmTx:tx
                     protocolRequest:protocolRequest
                              amount:amount
                                 fee:tx.feeUsed
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
                                            tx:tx];
        }
        requestRelayCompletion:^(DSTransaction *_Nonnull tx, DSPaymentProtocolACK *_Nonnull ack, BOOL relayedToServer) {
            [self txManagerRequestRelayCompletion:address
                                  protocolRequest:protocolRequest
                                  relayedToServer:relayedToServer
                                               tx:tx];
        }
        errorNotificationBlock:self.errorNotificationBlock];
}

#pragma mark - Private

- (void)confirmRequest:(DSPaymentRequest *)request {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    if (!request.isValid) {
        if ([request.paymentAddress isValidDashPrivateKeyOnChain:chain] ||
            [request.paymentAddress isValidDashBIP38Key]) {
            [self confirmSweep:request];
        }
        else {
            [self failedWithTitle:NSLocalizedString(@"Not a valid dash address", nil) message:nil];
        }
    }
    else if (request.r.length > 0) { // payment protocol over HTTP
        __weak typeof(self) weakSelf = self;
        [DSPaymentRequest
                 fetch:request.r
                scheme:request.scheme
               onChain:chain
               timeout:20.0
            completion:^(DSPaymentProtocolRequest *protocolRequest, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) {
                        return;
                    }

                    if (error && !([request.paymentAddress isValidDashAddressOnChain:chain])) {
                        [strongSelf failedWithTitle:NSLocalizedString(@"Couldn't make payment", nil)
                                            message:error.localizedDescription];
                    }
                    else {
                        [strongSelf confirmProtocolRequest:error ? request.protocolRequest : protocolRequest];
                    }
                });
            }];
    }
    else {
        [self confirmProtocolRequest:request.protocolRequest];
    }
}

- (void)confirmProtocolRequest:(DSPaymentProtocolRequest *)protocolRequest {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;

    NSString *address = [NSString addressWithScriptPubKey:protocolRequest.details.outputScripts.firstObject
                                                  onChain:chain];
    const BOOL addressIsFromPasteboard = self.paymentInput.source == DWPaymentInputSource_Pasteboard;

    self.didSendRequestDelegateNotified = NO;

    [chainManager.transactionManager
        confirmProtocolRequest:protocolRequest
        forAmount:self.amount
        fromAccount:account
        acceptReusingAddress:NO
        addressIsFromPasteboard:addressIsFromPasteboard
        acceptUncertifiedPayee:NO
        requestingAdditionalInfo:^(DSRequestingAdditionalInfo additionalInfoRequestType) {
            [self txManagerRequestingAdditionalInfo:additionalInfoRequestType
                                    protocolRequest:protocolRequest];
        }
        presentChallenge:self.challengeBlock
        transactionCreationCompletion:^BOOL(DSTransaction *_Nonnull tx, NSString *_Nonnull prompt, uint64_t amount, NSArray<NSString *> *addresses, BOOL isSecure) {
            [self txManagerConfirmTx:tx
                     protocolRequest:protocolRequest
                              amount:amount
                                 fee:tx.feeUsed
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
                                            tx:tx];
        }
        requestRelayCompletion:^(DSTransaction *_Nonnull tx, DSPaymentProtocolACK *_Nonnull ack, BOOL relayedToServer) {
            [self txManagerRequestRelayCompletion:address
                                  protocolRequest:protocolRequest
                                  relayedToServer:relayedToServer
                                               tx:tx];
        }
        errorNotificationBlock:self.errorNotificationBlock];
}

- (void)confirmSweep:(DSPaymentRequest *)request {
    NSString *privateKey = request.paymentAddress;
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    const BOOL valid = [privateKey isValidDashPrivateKeyOnChain:chain] || [privateKey isValidDashBIP38Key];
    NSAssert(valid, @"Inconsistent state");
    if (!valid) {
        return;
    }

    [self.delegate paymentProcessor:self showProgressHUDWithMessage:@"Checking private key balance..."];

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    __weak typeof(self) weakSelf = self;
    [account
        sweepPrivateKey:privateKey
                withFee:YES
             completion:^(DSTransaction *_Nullable tx, uint64_t fee, NSError *_Nullable error) {
                 dispatch_async(dispatch_get_main_queue(), ^{
                     __strong typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return;
                     }

                     [strongSelf.delegate paymentInputProcessorHideProgressHUD:strongSelf];
                     [strongSelf handleSweepResultTx:tx error:error fee:fee request:request];
                 });
             }];
}

- (void)handleFile:(NSData *)file {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;

    DSPaymentProtocolRequest *request = [DSPaymentProtocolRequest requestWithData:file onChain:chain];
    if (request) {
        [self confirmProtocolRequest:request];

        return;
    }

    // TODO: reject payments that don't match requested amounts/scripts, implement refunds
    DSPaymentProtocolPayment *payment = [DSPaymentProtocolPayment paymentWithData:file onChain:chain];
    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
    if (payment.transactions.count > 0) {
        NSMutableArray<NSError *> *errors = [NSMutableArray array];
        dispatch_group_t dispatchGroup = dispatch_group_create();

        for (DSTransaction *tx in payment.transactions) {
            dispatch_group_enter(dispatchGroup);
            [chainManager.transactionManager
                publishTransaction:tx
                        completion:^(NSError *error) {
                            if (error) {
                                [errors addObject:error];
                            }
                            else {
                                NSString *result = payment.memo.length > 0
                                                       ? payment.memo
                                                       : NSLocalizedString(@"Received", nil);
                                [self.delegate paymentProcessor:self displayFileProcessResult:result];
                            }

                            dispatch_group_leave(dispatchGroup);
                        }];
        }

        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            if (errors.count > 0) {
                NSArray<NSString *> *errorsDescription =
                    [errors valueForKeyPath:@"@distinctUnionOfObjects.localizedDescription"];
                NSString *description = [errorsDescription componentsJoinedByString:@"\n"];

                [self failedWithTitle:NSLocalizedString(@"Couldn't transmit payment to dash network", nil)
                              message:description];
            }

            [self.delegate paymentProcessorDidFinishProcessingFile:self];
        });

        return;
    }

    DSPaymentProtocolACK *ack = [DSPaymentProtocolACK ackWithData:file onChain:chain];
    if (ack) {
        if (ack.memo.length > 0) {
            [self.delegate paymentProcessor:self displayFileProcessResult:ack.memo];
        }

        [self.delegate paymentProcessorDidFinishProcessingFile:self];

        return;
    }

    [self failedWithTitle:NSLocalizedString(@"Unsupported or corrupted document", nil) message:nil];

    [self.delegate paymentProcessorDidFinishProcessingFile:self];
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
        [self failedWithTitle:NSLocalizedString(@"Couldn't make payment", nil) message:error.localizedDescription];
    }
    else {
        // NOP
        // Previous app version hid amount screen here
    }
    return YES;
}

- (void)txManagerPublishedCompletion:(NSString *)address
                                sent:(BOOL)sent
                                  tx:(DSTransaction *_Nonnull)tx {
    if (sent) {
        [self.delegate paymentProcessor:self didSendRequest:self.request transaction:tx];

        self.didSendRequestDelegateNotified = YES;

        [self handleCallbackSchemeIfNeeded:self.request address:address tx:tx];

        [self reset];
    }
}

- (void)txManagerRequestRelayCompletion:(NSString *)address
                        protocolRequest:(DSPaymentProtocolRequest *_Nonnull)protocolRequest
                        relayedToServer:(BOOL)relayedToServer
                                     tx:(DSTransaction *_Nonnull)tx {
    if (relayedToServer) {
        if (!self.didSendRequestDelegateNotified) {
            [self.delegate paymentProcessor:self didSendRequest:protocolRequest transaction:tx];
        }

        [self handleCallbackSchemeIfNeeded:protocolRequest address:address tx:tx];
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
                                                           localCurrency:localCurrency];
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

    [self.delegate paymentProcessor:self
        requestAmountWithDestination:sendingDestination
                             details:request.details];
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
    if (self.canChangeAmount && self.request && self.amount == 0) {
        void (^cancelBlock)(void) = ^{
            [self cancelPayment];
        };

        void (^changeBlock)(void) = ^{
            [self confirmProtocolRequest:self.request];
        };

        [self requestUserActionTitle:NSLocalizedString(@"Change payment amount?", nil)
                             message:nil
                         actionTitle:NSLocalizedString(@"Change", nil)
                         cancelBlock:cancelBlock
                         actionBlock:changeBlock];

        self.amount = UINT64_MAX;
    }
    else {
        [self cancelPayment];
    }
}

- (void)handleSweepResultTx:(nullable DSTransaction *)tx
                      error:(nullable NSError *)error
                        fee:(uint64_t)fee
                    request:(DSPaymentRequest *)request {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;

    if (error) {
        [self failedWithTitle:NSLocalizedString(@"couldn't sweep balance", nil)
                      message:error.localizedDescription];
    }
    else if (tx) {
        uint64_t amount = fee;
        for (NSNumber *amt in tx.outputAmounts) {
            amount += amt.unsignedLongLongValue;
        }

        NSString *format =
            NSLocalizedString(@"Send %@ (%@) from this private key into your wallet? The dash network will receive a fee of %@ (%@).", nil);
        NSString *message = [NSString stringWithFormat:format,
                                                       [priceManager stringForDashAmount:amount],
                                                       [priceManager localCurrencyStringForDashAmount:amount],
                                                       [priceManager stringForDashAmount:fee],
                                                       [priceManager localCurrencyStringForDashAmount:fee]];

        NSString *actionTitle = [NSString stringWithFormat:@"%@ (%@)",
                                                           [priceManager stringForDashAmount:amount],
                                                           [priceManager localCurrencyStringForDashAmount:amount]];

        [self
            requestUserActionTitle:nil
            message:message
            actionTitle:actionTitle
            cancelBlock:^{
                [self cancelOrChangeAmount];
            }
            actionBlock:^{
                [chainManager.transactionManager
                    publishTransaction:tx
                            completion:^(NSError *error) {
                                if (error) {
                                    [self failedWithTitle:NSLocalizedString(@"couldn't sweep balance", nil)
                                                  message:error.localizedDescription];
                                }
                                else {
                                    [self.delegate paymentProcessor:self
                                                    didSweepRequest:request
                                                        transaction:tx];
                                    [self reset];
                                }
                            }];
            }];
    }
    else {
        [self cancelPayment];
    }
}

- (void)handleCallbackSchemeIfNeeded:(DSPaymentProtocolRequest *)protocolRequest
                             address:(NSString *)address
                                  tx:(DSTransaction *)tx {
    if (protocolRequest.callbackScheme) {
        NSData *txidData = [NSData dataWithBytes:tx.txHash.u8 length:sizeof(UInt256)].reverse;
        NSString *txid = [NSString hexWithData:txidData];
        NSString *callbackString = [protocolRequest.callbackScheme
            stringByAppendingFormat:@"://callback=payack&address=%@&txid=%@",
                                    address,
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

- (void)failedWithTitle:(nullable NSString *)title message:(nullable NSString *)message {
    [self.delegate paymentProcessor:self didFailWithTitle:title message:message];
    [self cancel];
}

- (void)cancel {
    self.amount = 0;
    self.canChangeAmount = NO;
    self.shouldClearPasteboard = NO;
}

- (void)reset {
    self.request = nil;
    if (self.shouldClearPasteboard) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = @"";
    }
    [self cancel];
}

@end

NS_ASSUME_NONNULL_END
