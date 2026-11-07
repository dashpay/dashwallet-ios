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

#import "DWPaymentInput.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPaymentInputBuilder : NSObject

- (DWPaymentInput *)emptyPaymentInputWithSource:(DWPaymentInputSource)source;

/// Wrap an already-parsed payment string. The parse carries the routing /
/// validity verdicts; this only attaches the source tag.
- (DWPaymentInput *)paymentInputWithParsedURI:(DWParsedPaymentURI *)parsedURI
                                       source:(DWPaymentInputSource)source;

/// Wrap a fetched + verified BIP70 request (`DWBIP70ConfirmationBox`).
- (DWPaymentInput *)paymentInputWithBIP70Confirmation:(id)bip70Confirmation
                                               source:(DWPaymentInputSource)source;

- (nullable DWPaymentInput *)payToAddress:(NSString *)address
                                   amount:(uint64_t)amount;
- (void)payFirstFromArray:(NSArray<NSString *> *)array
                   source:(DWPaymentInputSource)source
               completion:(void (^)(DWPaymentInput *paymentInput))completion;

- (DWPaymentInput *)paymentInputWithURL:(NSURL *)url;

#if DASHPAY
#endif

@end

NS_ASSUME_NONNULL_END
