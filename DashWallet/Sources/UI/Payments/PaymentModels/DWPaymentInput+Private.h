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

#import "DWPaymentInput.h"

NS_ASSUME_NONNULL_BEGIN

@class DWPaymentIntent;

@interface DWPaymentInput ()

@property (nullable, nonatomic, strong) DWParsedPaymentURI *parsedURI;
/// App-side send carrier projected from `parsedURI`. The processor consumes THIS for a
/// plain-`dash:` send (C8 step 4).
@property (nullable, nonatomic, strong) DWPaymentIntent *paymentIntent;
@property (nullable, nonatomic, strong) id bip70Confirmation;
@property (nullable, nonatomic, strong) id<DWDPBasicUserItem> userItem;

- (instancetype)initWithSource:(DWPaymentInputSource)source;

/// Attach the parsed URI and build its send-side `DWPaymentIntent`. The box owns all
/// routing/validity decisions; the intent drives the send.
- (void)attachParsedURI:(DWParsedPaymentURI *)parsedURI;

@end

NS_ASSUME_NONNULL_END
