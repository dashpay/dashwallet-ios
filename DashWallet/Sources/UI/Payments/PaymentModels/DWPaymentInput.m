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

#import "DWPaymentInput+Private.h"

#import "DWEnvironment.h"
#import "dashwallet-Swift.h"

#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWPaymentInput

- (instancetype)initWithSource:(DWPaymentInputSource)source {
    self = [super init];
    if (self) {
        _source = source;
    }
    return self;
}

- (void)attachParsedURI:(DWParsedPaymentURI *)parsedURI {
    self.parsedURI = parsedURI;

    // Build the app-side send carrier the processor consumes for a plain-dash: send (C8 step 4).
    // Its `amount` is settable — `payToAddress:amount:` supplies a fixed send amount on top.
    self.paymentIntent = [[DWPaymentIntent alloc] initWithAddress:parsedURI.address
                                                           amount:parsedURI.amount
                                                            label:parsedURI.label
                                                          message:parsedURI.message
                                                   callbackScheme:parsedURI.callbackScheme
                                                 fiatCurrencyCode:parsedURI.fiatCurrencyCode
                                                       fiatAmount:parsedURI.fiatAmount
                                                  dashpayUsername:parsedURI.dashpayUsername];

    // Mint the write-only DSPaymentRequest courier from the already-parsed fields. The URI SEND path
    // is fully off it now (it reads `paymentIntent`); the only remaining readers are the sweep path
    // (`request.paymentAddress`, D2) and the DashPay `?user=` rebuild (`request.dashpayUsername`,
    // C10). Removing this mint waits on migrating those — it is the last `currentChain` read on the
    // URI path (the courier constructor requires a chain). TODO(D2/C10): drop when sweep + DashPay move.
    DSPaymentRequest *courier = [DSPaymentRequest requestWithString:@""
                                                            onChain:[DWEnvironment sharedInstance].currentChain];
    courier.scheme = parsedURI.scheme;
    courier.paymentAddress = parsedURI.address;
    courier.amount = parsedURI.amount;
    courier.label = parsedURI.label;
    courier.message = parsedURI.message;
    courier.r = parsedURI.rURL.absoluteString;
    courier.callbackScheme = parsedURI.callbackScheme;
    courier.dashpayUsername = parsedURI.dashpayUsername;
    courier.requestedFiatCurrencyCode = parsedURI.fiatCurrencyCode;
    courier.requestedFiatCurrencyAmount = parsedURI.fiatAmount;
    self.request = courier;
}

- (nullable NSString *)userDetails {
    NSString *result = nil;
    if (self.bip70Confirmation) {
        result = [self.bip70Confirmation valueForKey:@"memo"];
    }
    else if (self.parsedURI) {
        // URI path reads the parse box, not the DSPaymentRequest courier (C8 step 4). The verbatim
        // input stands in for the old `request.string` re-serialization; the sole consumer only
        // asks whether it looks like a Platform address, which the raw string answers identically.
        result = self.parsedURI.rawString;
    }
    else if (self.request) {
        result = self.request.string;
    }
    else if (self.protocolRequest) {
        result = (self.protocolRequest.details.memo ?: self.protocolRequest.details.paymentURL) ?: @"<?>";
    }

    NSString *prefixToRemove = @"dash:";
    if ([result hasPrefix:prefixToRemove]) {
        result = [result substringFromIndex:prefixToRemove.length];
    }

    return result;
}

@end

NS_ASSUME_NONNULL_END
