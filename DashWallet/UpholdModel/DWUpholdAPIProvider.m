//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWUpholdAPIProvider.h"

#import <DashSync/DSNetworking.h>

#import "DWUpholdCardObject+Internal.h"
#import "DWUpholdConstants.h"
#import "DWUpholdTransactionObject.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - HTTPLoaderManager helper

typedef void (^UpholdHTTPLoaderCompletionBlock)(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode);

@interface HTTPLoaderManager (DWUphold)

- (DWUpholdCancellationToken)upholdRequest:(HTTPRequest *)httpRequest completion:(HTTPLoaderCompletionBlock)completion;

@end

@implementation HTTPLoaderManager (DWUphold)

- (DWUpholdCancellationToken)upholdRequest:(HTTPRequest *)httpRequest completion:(HTTPLoaderCompletionBlock)completion {
    return (DWUpholdCancellationToken)[self sendRequest:httpRequest completion:completion];
}

- (DWUpholdCancellationToken)upholdAuthorizedRequest:(HTTPRequest *)httpRequest
                                         accessToken:(NSString *)accessToken
                                          completion:(UpholdHTTPLoaderCompletionBlock)completion {
    NSString *authorizationHeader = [NSString stringWithFormat:@"Bearer %@", accessToken];
    [httpRequest addValue:authorizationHeader forHeader:@"Authorization"];

    return (DWUpholdCancellationToken)[self sendRequest:httpRequest completion:^(id _Nullable parsedData, NSDictionary *_Nullable responseHeaders, NSInteger statusCode, NSError *_Nullable error) {
        NSDictionary *response = (NSDictionary *)parsedData;
        BOOL hasOTPError = NO;
        if ([response isKindOfClass:NSDictionary.class]) {
            NSDictionary *errors = response[@"errors"];
            if ([errors isKindOfClass:NSDictionary.class] && errors[@"token"] != nil) {
                hasOTPError = YES;
            }
        }

        DWUpholdAPIProviderResponseStatusCode upholdStatusCode = DWUpholdAPIProviderResponseStatusCodeOK;
        NSString *otpTokenHeader = responseHeaders[@"OTP-Token"];
        BOOL otpRequired = (otpTokenHeader && [otpTokenHeader caseInsensitiveCompare:@"required"] == NSOrderedSame) || hasOTPError;
        if (statusCode == 401) {
            upholdStatusCode = otpRequired ? DWUpholdAPIProviderResponseStatusCodeOTPRequired : DWUpholdAPIProviderResponseStatusCodeUnauthorized;
        }

        if (completion) {
            completion(parsedData, upholdStatusCode);
        }
    }];
}

@end

#pragma mark - API Provider

@implementation DWUpholdAPIProvider

+ (DWUpholdCancellationToken)authOperationWithCode:(NSString *)code
                                        completion:(void (^)(NSString *_Nullable accessToken))completion {
    NSParameterAssert(code);

    NSURL *url = [[self baseURL] URLByAppendingPathComponent:@"oauth2/token"];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                                parameters:@{
                                                    @"code" : code,
                                                    @"grant_type" : @"authorization_code",
                                                }];
    [httpRequest setBasicAuthWithUsername:[DWUpholdConstants clientID]
                                 password:[DWUpholdConstants clientSecret]];

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdRequest:httpRequest completion:^(id _Nullable parsedData, NSDictionary *_Nullable responseHeaders, NSInteger statusCode, NSError *_Nullable error) {
        NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;
        NSString *accessToken = response[@"access_token"];

        if (completion) {
            completion(accessToken);
        }
    }];
}

+ (DWUpholdCancellationToken)getDashCardAccessToken:(NSString *)accessToken
                                         completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdCardObject *_Nullable card))completion {
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:@"v0/me/cards"];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_GET
                                                parameters:nil];

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest accessToken:accessToken completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
        NSArray *response = [parsedData isKindOfClass:NSArray.class] ? (NSArray *)parsedData : nil;

        NSDictionary *dashCardDictionary = nil;
        for (NSDictionary *dictionary in response) {
            if (![dictionary isKindOfClass:NSDictionary.class]) {
                break;
            }

            NSString *currency = dictionary[@"currency"];
            if (![currency isKindOfClass:NSString.class]) {
                break;
            }

            if ([currency caseInsensitiveCompare:@"DASH"] == NSOrderedSame) {
                dashCardDictionary = dictionary;
                break;
            }
        }

        DWUpholdCardObject *card = nil;
        if (dashCardDictionary) {
            card = [[DWUpholdCardObject alloc] initWithDictionary:dashCardDictionary];
        }

        if (completion) {
            completion(!!card, upholdStatusCode, card);
        }
    }];
}


+ (DWUpholdCancellationToken)createDashCardAccessToken:(NSString *)accessToken
                                            completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdCardObject *_Nullable card))completion {
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:@"v0/me/cards"];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                               contentType:HTTPContentType_JSON
                                                parameters:@{
                                                    @"label" : @"Dash Card",
                                                    @"currency" : @"DASH",
                                                }];

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest accessToken:accessToken completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
        NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

        DWUpholdCardObject *card = [[DWUpholdCardObject alloc] initWithDictionary:response];
        if (completion) {
            completion(!!card, upholdStatusCode, card);
        }
    }];
}

+ (DWUpholdCancellationToken)createAddressForDashCard:(DWUpholdCardObject *)inputCard
                                          accessToken:(NSString *)accessToken
                                           completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdCardObject *_Nullable card))completion {
    NSString *urlPath = [NSString stringWithFormat:@"v0/me/cards/%@/addresses", inputCard.identifier];
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:urlPath];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                               contentType:HTTPContentType_JSON
                                                parameters:@{
                                                    @"network" : @"dash",
                                                }];

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest accessToken:accessToken completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
        NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

        NSString *address = response[@"id"];
        if ([address isKindOfClass:NSString.class]) {
            [inputCard updateAddress:address];
        }

        if (completion) {
            completion(!!inputCard.address, upholdStatusCode, inputCard);
        }
    }];
}

+ (DWUpholdCancellationToken)createTransactionForDashCard:(DWUpholdCardObject *)card
                                                   amount:(NSString *)amount
                                                  address:(NSString *)address
                                              accessToken:(NSString *)accessToken
                                                 otpToken:(nullable NSString *)otpToken
                                               completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdTransactionObject *_Nullable transaction))completion {
    NSParameterAssert(amount);
    NSParameterAssert(address);
    NSString *urlPath = [NSString stringWithFormat:@"v0/me/cards/%@/transactions", card.identifier];
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:urlPath];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                               contentType:HTTPContentType_JSON
                                                parameters:@{
                                                    @"denomination" : @{
                                                        @"amount" : amount,
                                                        @"currency" : @"DASH",
                                                    },
                                                    @"destination" : address,
                                                }];
    if (otpToken) {
        [self authorizeHTTPRequest:httpRequest otpToken:otpToken];
    }

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest accessToken:accessToken completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
        NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

        DWUpholdTransactionObject *transaction = [[DWUpholdTransactionObject alloc] initWithDictionary:response];
        if (completion) {
            completion(!!transaction, upholdStatusCode, transaction);
        }
    }];
}

+ (DWUpholdCancellationToken)commitTransaction:(DWUpholdTransactionObject *)transaction
                                          card:(DWUpholdCardObject *)card
                                   accessToken:(NSString *)accessToken
                                      otpToken:(nullable NSString *)otpToken
                                    completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode))completion {
    DWUpholdCancellationToken token = [self transactionAction:@"commit"
                                                  transaction:transaction
                                                         card:card
                                                  accessToken:accessToken
                                                     otpToken:otpToken
                                                   completion:completion];

    return token;
}

+ (DWUpholdCancellationToken)cancelTransaction:(DWUpholdTransactionObject *)transaction
                                          card:(DWUpholdCardObject *)card
                                   accessToken:(NSString *)accessToken
                                      otpToken:(nullable NSString *)otpToken
                                    completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode))completion {
    DWUpholdCancellationToken token = [self transactionAction:@"cancel"
                                                  transaction:transaction
                                                         card:card
                                                  accessToken:accessToken
                                                     otpToken:otpToken
                                                   completion:completion];

    return token;
}

#pragma mark - Private

+ (NSURL *)baseURL {
    NSString *baseURLString = [DWUpholdConstants baseURLString];
    NSURL *baseURL = [NSURL URLWithString:baseURLString];
    NSParameterAssert(baseURL);

    return baseURL;
}

+ (HTTPLoaderManager *)loaderManager {
    static HTTPLoaderManager *_sharedLoaderManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        HTTPLoaderFactory *loaderFactory = [DSNetworkingCoordinator sharedInstance].loaderFactory;
        _sharedLoaderManager = [[HTTPLoaderManager alloc] initWithFactory:loaderFactory];
    });
    return _sharedLoaderManager;
}

+ (void)authorizeHTTPRequest:(HTTPRequest *)request otpToken:(NSString *)otpToken {
    [request addValue:otpToken forHeader:@"OTP-Token"];
}

+ (DWUpholdCancellationToken)transactionAction:(NSString *)action
                                   transaction:(DWUpholdTransactionObject *)transaction
                                          card:(DWUpholdCardObject *)card
                                   accessToken:(NSString *)accessToken
                                      otpToken:(nullable NSString *)otpToken
                                    completion:(void (^_Nullable)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode))completion {
    NSAssert([action isEqualToString:@"commit"] || [action isEqualToString:@"cancel"], @"Invalid action on transaction");

    NSString *urlPath = [NSString stringWithFormat:@"v0/me/cards/%@/transactions/%@/%@",
                                                   card.identifier,
                                                   transaction.identifier,
                                                   action];
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:urlPath];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                                parameters:nil];
    if (otpToken) {
        [self authorizeHTTPRequest:httpRequest otpToken:otpToken];
    }

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest accessToken:accessToken completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
        NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

        DWUpholdTransactionObject *responseValidTransaction = [[DWUpholdTransactionObject alloc] initWithDictionary:response];

        if (completion) {
            completion(!!responseValidTransaction, upholdStatusCode);
        }
    }];
}

@end

NS_ASSUME_NONNULL_END
