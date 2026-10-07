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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DWPaymentInput;
@class DWPaymentProcessor;
@class DWPaymentOutput;

@protocol DWPaymentProcessorDelegate <NSObject>

// User Actions

// `amount` is the pre-fill for the amount screen in duffs (0 ⇒ empty). Replaces the old
// `DSPaymentProtocolDetails` carrier — the only thing the UI read from it was the output-amount sum.
- (void)paymentProcessor:(DWPaymentProcessor *)processor
    requestAmountWithDestination:(NSString *)sendingDestination
                          amount:(uint64_t)amount;

// Confirmation

// Asked before a payment to `addresses` is authorized and built (a plain send:
// its one address), or before its confirmation sheet (BIP70: every recipient
// of the request and the URI's fallback address, each once). The delegate
// calls `completion` once, on the main queue: YES goes on, NO ends the send
// through `paymentProcessorDidCancelTransactionSigning:`. `isBIP70` says which
// of the two it is, for the delegate's logs.
- (void)paymentProcessor:(DWPaymentProcessor *)processor
      shouldPayAddresses:(NSArray<NSString *> *)addresses
                 isBIP70:(BOOL)isBIP70
              completion:(void (^)(BOOL proceed))completion;

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    confirmPaymentOutput:(DWPaymentOutput *)paymentOutput;

- (void)paymentProcessorDidCancelTransactionSigning:(DWPaymentProcessor *)processor;

// Result

- (void)paymentProcessor:(DWPaymentProcessor *)processor
        didFailWithError:(nullable NSError *)error
                   title:(nullable NSString *)title
                 message:(nullable NSString *)message;

// `txidWire` is the broadcast transaction's wire-order txid (`Transaction.txHashData`
// convention) — the only datum consumers ever read off the old DSTransaction courier;
// the success screen resolves it to the persisted SDK row.
- (void)paymentProcessor:(DWPaymentProcessor *)processor
     didSendWithTxidWire:(NSData *)txidWire;

// The broadcast of `txidWire` got no answer from the network: it may have gone
// through. Not a failure — the send is followed in the history
// (`PendingSendOutcomes`) until the network answers.
- (void)paymentProcessor:(DWPaymentProcessor *)processor
    didSendWithUnknownOutcomeTxidWire:(NSData *)txidWire;

// Broadcast progress

// Brackets the network wait of a confirmed send — a plain broadcast or a BIP70
// payment (up to about a minute when no peer answers): YES right before it starts,
// NO right before its outcome is reported through `didSendWithTxidWire:` or
// `didFailWithError:`.
- (void)paymentProcessor:(DWPaymentProcessor *)processor
     broadcastInProgress:(BOOL)inProgress;

// Progress HUD

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    showProgressHUDWithMessage:(nullable NSString *)message;
- (void)paymentInputProcessorHideProgressHUD:(DWPaymentProcessor *)processor;

@end

// Refactored version of old DWSendViewController logic

@interface DWPaymentProcessor : NSObject

@property (nullable, nonatomic, weak) id<DWPaymentProcessorDelegate> delegate;

- (void)processPaymentInput:(DWPaymentInput *)paymentInput;

- (void)provideAmount:(uint64_t)amount;

- (void)confirmPaymentOutput:(DWPaymentOutput *)paymentOutput;

- (void)reset;

@end

NS_ASSUME_NONNULL_END
