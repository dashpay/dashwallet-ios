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

#import <UIKit/UIKit.h>

#import "DWDemoDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@class DWPaymentInput;
@protocol DWPayModelProtocol;

@interface DWBasePayViewController : UIViewController

@property (nonatomic, strong) id<DWPayModelProtocol> payModel;

@property (nonatomic, assign) BOOL demoMode;
@property (nullable, nonatomic, weak) id<DWDemoDelegate> demoDelegate;

@property (nonatomic, assign) BOOL locksBalance;

- (void)performScanQRCodeAction;
/// Assume pasteboard contains needed data and pay
- (void)performPayToPasteboardAction;
- (void)performNFCReadingAction;
- (void)performPayToURL:(NSURL *)url;
/// Pay a send this flow has already fully specified — the address and the
/// amount are both known and there is nothing left to ask for.
///
/// Deliberately not `performPayToURL:` with a `dash:…?amount=` string: that
/// classifies a URI carrying a valid address as a DEEP LINK, and the processor
/// answers a deep link by pushing the legacy amount screen — prefilled with the
/// number the caller already collected. This routes straight to the
/// confirmation with the real fee instead.
- (void)performPayToAddress:(NSString *)address amount:(uint64_t)amount;

/// Hand an already-built input to the classic payment processor.
///
/// Declared for the Swift subclasses that shadow the scan delegate to fill a
/// form instead: an input their form cannot hold — a BIP70 request, which
/// carries a fetched confirmation rather than an address — still has to go
/// somewhere, and this is where the base class sends it.
- (void)processPaymentInput:(DWPaymentInput *)input;

/// Present the shared send-success screen for an already-broadcast
/// transaction. `txidWire` is the wire-order txid (`Transaction.txHashData`
/// byte order).
///
/// Declared for the Swift subclasses whose send does NOT run through the
/// classic payment processor and therefore never reaches
/// `paymentControllerDidFinishTransaction:txidWire:` — the DashPay
/// pay-to-contact step, whose SDK call builds, signs and broadcasts in one
/// shot. This is the same presentation (and the same Close handling behind
/// it) an address send gets; the delegate wiring lives in the base class,
/// which is where the conformance is.
- (void)presentSendSuccessWithTxidWire:(NSData *)txidWire;

@end

NS_ASSUME_NONNULL_END
