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

#import "DWURLParser.h"

#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWURLParser

+ (BOOL)allowsURLHandling {
    // Don't allow URL handling without a wallet
    return DWWalletEnvironment.hasWallet;
}

+ (BOOL)canHandleURL:(NSURL *)url {
    if (!url) {
        return NO;
    }

    return [url.scheme isEqual:@"dash"] || [url.scheme isEqual:@"dashwallet"] ||
           [url.scheme isEqual:@"pay"] || [DWDashConnectDeepLink canHandleURL:url];
}

+ (nullable DWURLAction *)actionForURL:(NSURL *)url {
    NSString *dashConnectURI = [DWDashConnectDeepLink uriFromURL:url];
    if (dashConnectURI) {
        DWURLDashConnectAction *action = [[DWURLDashConnectAction alloc] init];
        action.uri = dashConnectURI;

        return action;
    }

    if ([url.absoluteString containsString:@"uphold"]) {
        DWURLIntegrationAction *action = [[DWURLIntegrationAction alloc] init];
        action.url = url;

        return action;
    }

    if ([url.scheme isEqual:@"dashwallet"]) {
        if ([url.host isEqual:@"scanqr"] || [url.path isEqual:@"/scanqr"]) {
            return [[DWURLScanQRAction alloc] init];
        }

        if ([url.host hasPrefix:@"request"] || [url.path isEqual:@"/request"]) {
            NSDictionary<NSString *, NSString *> *params = [self parseParamsFromURL:url];
            if (![self isRequestParamsValid:params]) {
                return nil;
            }

            // The answer goes to `sender`, so a request without an app to answer has no use.
            NSString *sender = [DWCallbackScheme validated:params[@"sender"]];
            if (!sender) {
                return nil;
            }

            DWURLRequestAction *action = [[DWURLRequestAction alloc] init];
            action.sender = sender;
            action.request = params[@"request"];

            return action;
        }
        else if ([url.host hasPrefix:@"pay"] || [url.path isEqual:@"/pay"]) {
            NSDictionary<NSString *, NSString *> *params = [self parseParamsFromURL:url];
            if (![self isPayParamsValid:params] || [self hasAmbiguousPaymentParameterInURL:url]) {
                return nil;
            }

            NSURL *paymentURL = [self paymentURLWithParams:params namingSender:YES];
            if (!paymentURL) {
                return nil;
            }

            DWURLPayAction *action = [[DWURLPayAction alloc] init];
            action.paymentURL = paymentURL;

            return action;
        }
    }
    else if ([url.scheme isEqual:@"dash"] || [url.scheme isEqual:@"pay"]) {
        DWURLPayAction *action = [[DWURLPayAction alloc] init];
        action.paymentURL = url;

        return action;
    }

    return nil;
}

+ (nullable NSURL *)paymentURLForScannedLink:(NSURL *)url {
    // Same routing as a deep link, so a scan pays exactly the links a deep link pays.
    if (![url.scheme isEqual:@"dashwallet"] ||
        ![[self actionForURL:url] isKindOfClass:DWURLPayAction.class]) {
        return nil;
    }

    return [self paymentURLWithParams:[self parseParamsFromURL:url] namingSender:NO];
}

#pragma mark - Private

+ (NSDictionary<NSString *, NSString *> *)parseParamsFromURL:(NSURL *)url {
    NSArray<NSString *> *components = [url.host componentsSeparatedByString:@"&"];
    NSMutableDictionary<NSString *, NSString *> *params = [[NSMutableDictionary alloc] init];
    for (NSString *param in components) {
        NSArray *paramArray = [param componentsSeparatedByString:@"="];
        if (paramArray.count == 2) {
            [params setObject:paramArray[1] forKey:paramArray[0]];
        }
    }

    return [params copy];
}

/// `parseParamsFromURL` keeps the last of a repeated key and drops a pair it cannot split, so a
/// recipient, amount or merchant request given twice, or malformed, could vanish or be replaced,
/// leaving a different recipient, an open amount or a different request. Such a link is refused, as is one carrying payment fields
/// or a requirement (`req-`) in its query, which the rewrite never reads, or a requirement it would drop as malformed.
+ (BOOL)hasAmbiguousPaymentParameterInURL:(NSURL *)url {
    NSArray<NSString *> *paymentKeys = @[ @"pay", @"amount", @"req-amount", @"r", @"req-r" ];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([paymentKeys containsObject:item.name] || [item.name hasPrefix:@"req-"]) {
            return YES;
        }
    }

    NSUInteger recipients = 0;
    NSUInteger amounts = 0;
    NSUInteger requests = 0;
    NSUInteger requiredSenders = 0;
    NSUInteger senders = 0;
    for (NSString *param in [url.host componentsSeparatedByString:@"&"]) {
        NSArray<NSString *> *pair = [param componentsSeparatedByString:@"="];
        NSString *key = pair.firstObject;
        BOOL isRecipient = [key isEqualToString:@"pay"];
        BOOL isAmount = [key isEqualToString:@"amount"] || [key isEqualToString:@"req-amount"];
        BOOL isRequest = [key isEqualToString:@"r"] || [key isEqualToString:@"req-r"];
        BOOL isRequirement = [key hasPrefix:@"req-"];
        // The app called back, and the one a required callback must match: one of each, or the
        // last of several would decide.
        BOOL isSender = [key isEqualToString:@"sender"];
        if (!isRecipient && !isAmount && !isRequest && !isRequirement && !isSender) {
            continue;
        }
        BOOL isRequiredSender = [key isEqualToString:@"req-sender"];
        if ((pair.count != 2 && !isSender) || (isRecipient && ++recipients > 1) || (isAmount && ++amounts > 1) ||
            (isRequest && ++requests > 1) || (isRequiredSender && ++requiredSenders > 1) ||
            (isSender && ++senders > 1)) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isRequestParamsValid:(NSDictionary<NSString *, NSString *> *)params {
    if (params[@"request"] &&
        params[@"sender"] &&
        (!params[@"account"] || [params[@"account"] isEqualToString:@"0"])) {
        if ([params[@"request"] isEqualToString:@"address"]) {
            return YES;
        }
    }

    return NO;
}

/// `pay` is interpolated into the `dash:` URI, so it must be a bare destination: base58 and bech32m
/// use ASCII letters and digits only. Anything else (`?`, `&`, `#`, `%`, `:`) could carry fields that
/// the rewrite then replaces before the payment parser checks them.
+ (BOOL)isPayParamsValid:(NSDictionary<NSString *, NSString *> *)params {
    static NSCharacterSet *notInDestination;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        notInDestination = [[NSCharacterSet characterSetWithCharactersInString:
                                                @"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"] invertedSet];
    });
    NSString *pay = params[@"pay"];
    if (pay.length == 0 || [pay rangeOfCharacterFromSet:notInDestination].location != NSNotFound) {
        return NO;
    }
    if (params[@"sender"]) {
        return YES;
    }

    return NO;
}

/// The `dash:` URI a `dashwallet://pay=` link stands for. A `sender` that names an app replaces
/// the link's own label with one naming that app, and stays in the URI as the callback scheme.
/// Otherwise (`namingSender` is NO, or `sender` is not a scheme an app can own) `sender` is
/// dropped and the link keeps its own label. `BIP70URI` reads `req-sender` and `req-label` as
/// `sender` and `label`, so neither is passed on: the URI carries one sender and one label, the
/// ones decided here. A scanned link (`namingSender` NO) keeps `req-sender`, so the payment parser
/// refuses a callback that no scan can send.
+ (nullable NSURL *)paymentURLWithParams:(NSDictionary<NSString *, NSString *> *)params
                            namingSender:(BOOL)namingSender {
    NSMutableDictionary<NSString *, NSString *> *mutableParams = [params mutableCopy];

    NSString *sender = namingSender ? [DWCallbackScheme validated:mutableParams[@"sender"]] : nil;
    // An opened link meets a required callback only when it names the same app as `sender`.
    if (namingSender && mutableParams[@"req-sender"] &&
        ![[DWCallbackScheme validated:mutableParams[@"req-sender"]] isEqualToString:sender]) {
        return nil;
    }
    NSString *ownLabel = mutableParams[@"label"] ?: mutableParams[@"req-label"];
    [mutableParams removeObjectsForKeys:@[ @"sender", @"label", @"req-label" ]];
    if (namingSender) {
        [mutableParams removeObjectForKey:@"req-sender"];
    }

    if (sender) {
        mutableParams[@"sender"] = sender;
        mutableParams[@"label"] = [NSString stringWithFormat:
                                                NSLocalizedString(@"Application %@ is requesting a payment to", nil),
                                                sender];
    }
    else if (ownLabel) {
        mutableParams[@"label"] = ownLabel;
    }

    NSString *componentsString = [NSString stringWithFormat:@"dash:%@", mutableParams[@"pay"]];
    NSURLComponents *components = [NSURLComponents componentsWithString:componentsString];
    if (!components) {
        return nil;
    }

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];

    if (mutableParams[@"label"]) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"label" value:mutableParams[@"label"]]];
    }

    for (NSString *key in mutableParams) {
        if ([key isEqualToString:@"label"]) {
            continue;
        }

        [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:mutableParams[key]]];
    }
    components.queryItems = queryItems;

    NSURL *paymentURL = components.URL;

    return paymentURL;
}

@end

NS_ASSUME_NONNULL_END
