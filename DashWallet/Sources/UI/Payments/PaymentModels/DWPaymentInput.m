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

#import "dashwallet-Swift.h"

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
    // (The write-only DSPaymentRequest courier minted here until C8-fin is gone — its last
    // documented readers, the D2 sweep and the DashPay ?user= rebuild, were both retired.)
    self.paymentIntent = [[DWPaymentIntent alloc] initWithAddress:parsedURI.address
                                                           amount:parsedURI.amount
                                                            label:parsedURI.label
                                                          message:parsedURI.message
                                                   callbackScheme:parsedURI.callbackScheme
                                                 fiatCurrencyCode:parsedURI.fiatCurrencyCode
                                                       fiatAmount:parsedURI.fiatAmount
                                                  dashpayUsername:parsedURI.dashpayUsername];
}

- (nullable NSString *)userDetails {
    NSString *result = nil;
    if (self.bip70Confirmation) {
        result = [self.bip70Confirmation valueForKey:@"memo"];
    }
    else if (self.parsedURI) {
        // The verbatim input stands in for the old `request.string` re-serialization; the sole
        // consumer only asks whether it looks like a Platform address, which the raw string
        // answers identically.
        result = self.parsedURI.rawString;
    }

    NSString *prefixToRemove = @"dash:";
    if ([result hasPrefix:prefixToRemove]) {
        result = [result substringFromIndex:prefixToRemove.length];
    }

    return result;
}

@end

NS_ASSUME_NONNULL_END
