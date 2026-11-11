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
            if (![self isPayParamsValid:params]) {
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

+ (BOOL)isPayParamsValid:(NSDictionary<NSString *, NSString *> *)params {
    if (params[@"pay"] && params[@"sender"]) {
        return YES;
    }

    return NO;
}

/// The `dash:` URI a `dashwallet://pay=` link stands for. A `sender` that names an app replaces
/// the link's own label with one naming that app, and stays in the URI as the callback scheme.
/// Otherwise (`namingSender` is NO, or `sender` is not a scheme an app can own) `sender` is
/// dropped and the link keeps its own label. `BIP70URI` reads `req-sender` and `req-label` as
/// `sender` and `label`, so neither is passed on: the URI carries one sender and one label, the
/// ones decided here.
+ (nullable NSURL *)paymentURLWithParams:(NSDictionary<NSString *, NSString *> *)params
                            namingSender:(BOOL)namingSender {
    NSMutableDictionary<NSString *, NSString *> *mutableParams = [params mutableCopy];

    NSString *sender = namingSender ? [DWCallbackScheme validated:mutableParams[@"sender"]] : nil;
    NSString *ownLabel = mutableParams[@"label"] ?: mutableParams[@"req-label"];
    [mutableParams removeObjectsForKeys:@[ @"sender", @"req-sender", @"label", @"req-label" ]];

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
