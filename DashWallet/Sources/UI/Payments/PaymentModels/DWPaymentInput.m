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

    // Mint the write-only DSPaymentRequest courier from the already-parsed fields. Nothing reads it
    // for a decision — the box owns those. It exists only to feed DashSync's protocol-request
    // conversion (`protocolRequestFromPaymentRequest:`, C8 step 4), the sweep path, and the
    // `userDetails` reconstruction below. This is the single residual `currentChain` read on the
    // URI path (the courier constructor requires a chain).
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
