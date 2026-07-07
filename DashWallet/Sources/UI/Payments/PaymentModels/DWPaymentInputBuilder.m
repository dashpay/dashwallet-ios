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

#import "DWPaymentInputBuilder.h"

#import "DWEnvironment.h"
#import "DWPaymentInput+Private.h"
#import "dashwallet-Swift.h"

#if DASHPAY
#import "DWDashPayConstants.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@implementation DWPaymentInputBuilder

- (DWPaymentInput *)emptyPaymentInputWithSource:(DWPaymentInputSource)source {
    return [[DWPaymentInput alloc] initWithSource:source];
}

- (nullable DWPaymentInput *)payToAddress:(NSString *)address
                                   amount:(uint64_t)amount {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    DWParsedPaymentURI *parsed = [DWParsedPaymentURI parsePaymentString:address];

    NSData *data = address.hexToData.reverse;

    if (data.length == sizeof(UInt256) && [account transactionForHash:*(UInt256 *)data.bytes]) {
        return nil;
    }

    if (parsed.isAddressValidForCurrentNetwork) {
        DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:DWPaymentInputSource_PlainAddress];
        [paymentInput attachParsedURI:parsed];
        paymentInput.paymentIntent.amount = amount; // a send parameter, not a parse fact
        return paymentInput;
    }

    return nil;
}

- (void)payFirstFromArray:(NSArray<NSString *> *)array
                   source:(DWPaymentInputSource)source
               completion:(void (^)(DWPaymentInput *paymentInput))completion {
    NSUInteger i = 0;
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    for (NSString *str in array) {
        DWParsedPaymentURI *parsed = [DWParsedPaymentURI parsePaymentString:str];
        NSData *data = str.hexToData.reverse;

        i++;

        // if the clipboard contains a known txHash, we know it's not a hex encoded private key
        if (data.length == sizeof(UInt256) && [account transactionForHash:*(UInt256 *)data.bytes]) {
            continue;
        }

        if (parsed.isAddressValidForCurrentNetwork) {
            if (completion) {
                DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:source];
                [paymentInput attachParsedURI:parsed];
                completion(paymentInput);
            }

            return;
        }
        else if (parsed.rURL != nil) { // may be BIP73 url: https://github.com/bitcoin/bips/blob/master/bip-0073.mediawiki
            DWBIP70InteractiveCoordinator *coordinator = [[DWBIP70InteractiveCoordinator alloc] init];
            [coordinator fetchAndVerifyWithRequestURL:parsed.rURL
                                               scheme:parsed.scheme
                                       callbackScheme:parsed.callbackScheme
                                           completion:^(DWBIP70ConfirmationBox *_Nullable box, NSError *_Nullable error) {
                                               (void)coordinator;         // retain until completion
                                               if (error || box == nil) { // don't try any more BIP73 urls
                                                   NSIndexSet *filteredIndexes =
                                                       [array indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                                                           return (idx >= i && ([obj hasPrefix:@"dash:"] || [obj hasPrefix:@"pay:"] || ![NSURL URLWithString:obj]));
                                                       }];
                                                   NSArray<NSString *> *filteredArray = [array objectsAtIndexes:filteredIndexes];
                                                   [self payFirstFromArray:filteredArray source:source completion:completion];
                                               }
                                               else {
                                                   if (completion) {
                                                       DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:source];
                                                       paymentInput.bip70Confirmation = box;
                                                       completion(paymentInput);
                                                   }
                                               }
                                           }];

            return;
        }
    }

    if (completion) {
        DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:source];
        completion(paymentInput);
    }
}

- (DWPaymentInput *)paymentInputWithURL:(NSURL *)url {
    // The parser normalizes `pay:`/`dashwallet:` → `dash:` natively, so the scheme fork is gone.
    DWParsedPaymentURI *parsed = [DWParsedPaymentURI parsePaymentString:url.absoluteString];

    // A deep link carrying a valid Dash address is a "deep link"; otherwise it's a generic URL.
    DWPaymentInputSource sourceType = parsed.isAddressValidForCurrentNetwork
                                          ? DWPaymentInputSource_DeepLink
                                          : DWPaymentInputSource_URL;

    DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:sourceType];
    [paymentInput attachParsedURI:parsed];

    return paymentInput;
}

#if DASHPAY
- (DWPaymentInput *)paymentInputWithUserItem:(id<DWDPBasicUserItem>)userItem {
    if (MOCK_DASHPAY) {
        NSString *address = @"yeRZBWYfeNE4yVUHV4ZLs83Ppn9aMRH57A"; // testnet faucet
        DSChain *chain = [DWEnvironment sharedInstance].currentChain;
        DSPaymentRequest *paymentRequest = [DSPaymentRequest requestWithString:address onChain:chain];

        DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:DWPaymentInputSource_BlockchainUser];
        paymentInput.userItem = userItem;
        paymentInput.canChangeAmount = YES;
        paymentInput.request = paymentRequest;
        paymentInput.request.dashpayUsername = userItem.username;

        return paymentInput;
    }

    DSFriendRequestEntity *friendRequest = [userItem friendRequestToPay];
    NSParameterAssert(friendRequest);

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    DSIncomingFundsDerivationPath *derivationPath = [account derivationPathForFriendshipWithIdentifier:friendRequest.friendshipIdentifier];
    NSAssert(derivationPath.extendedPublicKeyData, @"Extended public key must exist already");
    NSString *address = derivationPath.receiveAddress;

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSPaymentRequest *paymentRequest = [DSPaymentRequest requestWithString:address onChain:chain];

    DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:DWPaymentInputSource_BlockchainUser];
    paymentInput.userItem = userItem;
    paymentInput.canChangeAmount = YES;
    paymentInput.request = paymentRequest;

    return paymentInput;
}
#endif

@end

NS_ASSUME_NONNULL_END
