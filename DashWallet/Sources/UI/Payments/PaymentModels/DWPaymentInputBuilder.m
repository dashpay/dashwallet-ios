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

NS_ASSUME_NONNULL_BEGIN

@implementation DWPaymentInputBuilder

- (DWPaymentInput *)emptyPaymentInputWithSource:(DWPaymentInputSource)source {
    return [[DWPaymentInput alloc] initWithSource:source];
}

- (void)payFirstFromArray:(NSArray<NSString *> *)array
                   source:(DWPaymentInputSource)source
               completion:(void (^)(DWPaymentInput *paymentInput))completion {
    NSUInteger i = 0;
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    for (NSString *str in array) {
        NSString *requestString = str;
        if ([requestString hasPrefix:@"pay:"]) {
            requestString = [str stringByReplacingOccurrencesOfString:@"pay:" withString:@"dash:" options:0 range:NSMakeRange(0, 4)];
        }
        DSPaymentRequest *request = [DSPaymentRequest requestWithString:requestString onChain:chain];
        NSData *data = str.hexToData.reverse;

        i++;

        // if the clipboard contains a known txHash, we know it's not a hex encoded private key
        if (data.length == sizeof(UInt256) && [account transactionForHash:*(UInt256 *)data.bytes]) {
            continue;
        }

        if ([request.paymentAddress isValidDashAddressOnChain:chain] || [str isValidDashPrivateKeyOnChain:chain] || [str isValidDashBIP38Key] ||
            (request.r.length > 0 && ([request.scheme isEqual:@"dash:"]))) {
            if (completion) {
                DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:source];
                paymentInput.request = request;
                completion(paymentInput);
            }

            return;
        }
        else if (request.r.length > 0) { // may be BIP73 url: https://github.com/bitcoin/bips/blob/master/bip-0073.mediawiki
            [request fetchBIP70WithTimeout:5.0
                                completion:^(DSPaymentProtocolRequest *_Nonnull protocolRequest, NSError *_Nonnull error) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        if (error) { // don't try any more BIP73 urls
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
                                                paymentInput.protocolRequest = protocolRequest;
                                                completion(paymentInput);
                                            }
                                        }
                                    });
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
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSPaymentRequest *request = nil;
    if ([url.scheme isEqualToString:@"pay"]) {
        NSString *path = url.absoluteString;
        if ([path hasPrefix:@"pay:"]) {
            path = [path stringByReplacingOccurrencesOfString:@"pay:" withString:@"dash:" options:0 range:NSMakeRange(0, 4)];
        }
        request = [DSPaymentRequest requestWithString:path onChain:chain];
    }
    else {
        request = [DSPaymentRequest requestWithURL:url onChain:chain];
    }

    DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:DWPaymentInputSource_URL];
    paymentInput.request = request;

    return paymentInput;
}

- (DWPaymentInput *)paymentInputWithUserItem:(id<DWDPBasicUserItem>)userItem {
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

@end

NS_ASSUME_NONNULL_END
