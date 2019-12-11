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

NS_ASSUME_NONNULL_BEGIN

@implementation DWURLParser

+ (BOOL)allowsURLHandling {
    // Don't allow URL handling without a wallet
    return [DWEnvironment sharedInstance].currentChain.hasAWallet;
}

+ (BOOL)canHandleURL:(NSURL *)url {
    if (!url) {
        return NO;
    }

    return [url.scheme isEqual:@"dash"] || [url.scheme isEqual:@"dashwallet"];
}

+ (nullable DWURLAction *)actionForURL:(NSURL *)url {
    if ([url.absoluteString containsString:@"uphold"]) {
        DWURLUpholdAction *action = [[DWURLUpholdAction alloc] init];
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

            DWURLRequestAction *action = [[DWURLRequestAction alloc] init];
            action.sender = params[@"sender"];
            action.request = params[@"request"];

            return action;
        }
        else if ([url.host hasPrefix:@"pay"] || [url.path isEqual:@"/pay"]) {
            NSDictionary<NSString *, NSString *> *params = [self parseParamsFromURL:url];
            if (![self isPayParamsValid:params]) {
                return nil;
            }

            NSURL *paymentURL = [self paymentURLWithParams:params];
            if (!paymentURL) {
                return nil;
            }

            DWURLPayAction *action = [[DWURLPayAction alloc] init];
            action.paymentURL = paymentURL;

            return action;
        }
    }
    else if ([url.scheme isEqual:@"dash"]) {
        DWURLPayAction *action = [[DWURLPayAction alloc] init];
        action.paymentURL = url;

        return action;
    }

    return nil;
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
        if ([params[@"request"] isEqualToString:@"masterPublicKey"]) {
            return YES;
        }
        else if ([params[@"request"] isEqualToString:@"address"]) {
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

+ (nullable NSURL *)paymentURLWithParams:(NSDictionary<NSString *, NSString *> *)params {
    NSMutableDictionary<NSString *, NSString *> *mutableParams = [params mutableCopy];

    if (mutableParams[@"label"]) {
        [mutableParams removeObjectForKey:@"label"];
    }

    NSString *componentsString = [NSString stringWithFormat:@"dash:%@", mutableParams[@"pay"]];
    NSURLComponents *components = [NSURLComponents componentsWithString:componentsString];
    if (!components) {
        return nil;
    }

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];

    NSString *labelValue = [NSString stringWithFormat:
                                         NSLocalizedString(@"Application %@ is requesting a payment to", nil),
                                         [mutableParams[@"sender"] capitalizedString]];
    NSURLQueryItem *labelItem = [NSURLQueryItem queryItemWithName:@"label" value:labelValue];
    [queryItems addObject:labelItem];

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
