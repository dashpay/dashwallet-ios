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

#import "DWUpholdAccountObject.h"
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
                                          completion:(nullable UpholdHTTPLoaderCompletionBlock)completion {
    NSString *authorizationHeader = [NSString stringWithFormat:@"Bearer %@", accessToken];
    [httpRequest addValue:authorizationHeader forHeader:@"Authorization"];

    return (DWUpholdCancellationToken)[self sendRequest:httpRequest
                                             completion:^(id _Nullable parsedData, NSDictionary *_Nullable responseHeaders, NSInteger statusCode, NSError *_Nullable error) {
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
                                                     if (otpRequired) {
                                                         upholdStatusCode = DWUpholdAPIProviderResponseStatusCodeOTPRequired;
                                                     }
                                                     else if (responseHeaders[@"otp-method-id"]) {
                                                         upholdStatusCode = DWUpholdAPIProviderResponseStatusCodeOTPInvalid;
                                                     }
                                                     else {
                                                         upholdStatusCode = DWUpholdAPIProviderResponseStatusCodeUnauthorized;
                                                     }
                                                 }

                                                 if (completion) {
                                                     completion(parsedData, upholdStatusCode);
                                                 }
                                             }];
}

@end

#pragma mark - API Provider

static NSSet<NSString *> *FiatCurrencyCodes() {
    return [NSSet setWithObjects:
                      @"ARS", @"AUD", @"BRL", @"CAD", @"DKK", @"AED", @"EUR", @"HKD", @"INR", @"ILS", @"KES",
                      @"MXN", @"NZD", @"NOK", @"PHP", @"PLN", @"GBP", @"SGD", @"SEK", @"CHF", @"USD", @"JPY", @"CNY", nil];
}

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
    return [loaderManager upholdRequest:httpRequest
                             completion:^(id _Nullable parsedData, NSDictionary *_Nullable responseHeaders, NSInteger statusCode, NSError *_Nullable error) {
                                 NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;
                                 NSString *accessToken = response[@"access_token"];


                                 if (completion) {
                                     completion(accessToken);
                                 }
                             }];
}

+ (DWUpholdCancellationToken)getUserAccountsAccessToken:(NSString *)accessToken completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, NSArray<DWUpholdAccountObject *> *_Nullable accounts))completion {
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:@"v0/me/accounts"];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_GET
                                                parameters:nil];

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest
                                      accessToken:accessToken
                                       completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
                                           NSArray<NSDictionary *> *response = [parsedData isKindOfClass:NSArray.class] ? (NSArray *)parsedData : nil;

                                           NSMutableArray<DWUpholdAccountObject *> *accounts = nil;
                                           if (response) {
                                               accounts = [NSMutableArray array];
                                               for (NSDictionary *accountDictionary in response) {
                                                   DWUpholdAccountObject *account = [[DWUpholdAccountObject alloc] initWithDictionary:accountDictionary];
                                                   if (account) {
                                                       [accounts addObject:account];
                                                   }
                                               }
                                           }

                                           if (completion) {
                                               completion(!!response, upholdStatusCode, [accounts copy]);
                                           }
                                       }];
}

+ (DWUpholdCancellationToken)getCardsAccessToken:(NSString *)accessToken
                                      completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdCardObject *_Nullable dashCard, NSArray<DWUpholdCardObject *> *fiatCards))completion {
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:@"v0/me/cards"];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_GET
                                                parameters:nil];

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest
                                      accessToken:accessToken
                                       completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
                                           NSArray *response = [parsedData isKindOfClass:NSArray.class] ? (NSArray *)parsedData : nil;

                                           NSSet<NSString *> *fiatCurrencyCodes = FiatCurrencyCodes();
                                           NSMutableArray<DWUpholdCardObject *> *dashCards = [NSMutableArray array];
                                           NSMutableArray<DWUpholdCardObject *> *fiatCards = [NSMutableArray array];
                                           for (NSDictionary *dictionary in response) {
                                               if (![dictionary isKindOfClass:NSDictionary.class]) {
                                                   break;
                                               }

                                               NSString *currency = dictionary[@"currency"];
                                               if (![currency isKindOfClass:NSString.class]) {
                                                   break;
                                               }

                                               currency = currency.uppercaseString;

                                               if ([currency isEqualToString:@"DASH"]) {
                                                   DWUpholdCardObject *card = [[DWUpholdCardObject alloc] initWithDictionary:dictionary];
                                                   if (card) {
                                                       [dashCards addObject:card];
                                                   }
                                               }
                                               else if ([fiatCurrencyCodes containsObject:currency]) {
                                                   DWUpholdCardObject *card = [[DWUpholdCardObject alloc] initWithDictionary:dictionary];
                                                   if (card && (card.available.doubleValue > 0.0 || [currency isEqualToString:@"USD"] || [currency isEqualToString:@"EUR"])) {
                                                       [fiatCards addObject:card];
                                                   }
                                               }
                                           }

                                           NSArray<NSSortDescriptor *> *sortDescriptors = @[
                                               [NSSortDescriptor sortDescriptorWithKey:@"starred"
                                                                             ascending:NO],
                                               [NSSortDescriptor sortDescriptorWithKey:@"available"
                                                                             ascending:NO],
                                               [NSSortDescriptor sortDescriptorWithKey:@"position"
                                                                             ascending:YES],
                                           ];

                                           [dashCards sortUsingDescriptors:sortDescriptors];

                                           DWUpholdCardObject *dashCard = dashCards.firstObject;

                                           if (completion) {
                                               completion(!!response, upholdStatusCode, dashCard, fiatCards);
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
    return [loaderManager upholdAuthorizedRequest:httpRequest
                                      accessToken:accessToken
                                       completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
                                           NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

                                           DWUpholdCardObject *card = [[DWUpholdCardObject alloc] initWithDictionary:response];
                                           if (completion) {
                                               completion(!!response, upholdStatusCode, card);
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
    return [loaderManager upholdAuthorizedRequest:httpRequest
                                      accessToken:accessToken
                                       completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
                                           NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

                                           NSString *address = response[@"id"];
                                           if ([address isKindOfClass:NSString.class]) {
                                               [inputCard updateAddress:address];
                                           }

                                           if (completion) {
                                               completion(!!response, upholdStatusCode, inputCard);
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

    // Uphold supports only "." as delimeter
    amount = [amount stringByReplacingOccurrencesOfString:@"," withString:@"."];

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
    return [loaderManager upholdAuthorizedRequest:httpRequest
                                      accessToken:accessToken
                                       completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
                                           NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

                                           DWUpholdTransactionObject *transaction = [[DWUpholdTransactionObject alloc] initWithDictionary:response];
                                           if (completion) {
                                               completion(!!response, upholdStatusCode, transaction);
                                           }
                                       }];
}

+ (DWUpholdCancellationToken)createBuyTransactionForDashCard:(DWUpholdCardObject *)card
                                                     account:(DWUpholdAccountObject *)account
                                                      amount:(NSString *)amount
                                                securityCode:(NSString *)securityCode
                                                 accessToken:(NSString *)accessToken
                                                    otpToken:(nullable NSString *)otpToken
                                                  completion:(void (^)(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdTransactionObject *_Nullable transaction))completion {
    NSParameterAssert(amount);
    NSParameterAssert(securityCode);

    // Uphold supports only "." as delimeter
    amount = [amount stringByReplacingOccurrencesOfString:@"," withString:@"."];

    NSString *urlPath = [NSString stringWithFormat:@"v0/me/cards/%@/transactions", @"6c6d1fea-7ed1-4417-9108-a2ac0252288e"]; // card.identifier];
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:urlPath];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                               contentType:HTTPContentType_JSON
                                                parameters:@{
                                                    @"denomination" : @{
                                                        @"amount" : amount,
                                                        @"currency" : account.currency,
                                                    },
                                                    @"origin" : account.identifier,
                                                    @"securityCode" : securityCode,
                                                }];
    if (otpToken) {
        [self authorizeHTTPRequest:httpRequest otpToken:otpToken];
    }

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest
                                      accessToken:accessToken
                                       completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
                                           NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

                                           DWUpholdTransactionObject *transaction = [[DWUpholdTransactionObject alloc] initWithDictionary:response];
                                           if (completion) {
                                               completion(!!response, upholdStatusCode, transaction);
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

+ (DWUpholdCancellationToken)revokeAccessToken:(NSString *)accessToken {
    NSURL *url = [[self baseURL] URLByAppendingPathComponent:@"oauth2/revoke"];
    NSParameterAssert(url);
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                                parameters:@{
                                                    @"token" : accessToken,
                                                }];

    HTTPLoaderManager *loaderManager = [self loaderManager];
    return [loaderManager upholdAuthorizedRequest:httpRequest accessToken:accessToken completion:nil];
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
    return [loaderManager upholdAuthorizedRequest:httpRequest
                                      accessToken:accessToken
                                       completion:^(id _Nullable parsedData, DWUpholdAPIProviderResponseStatusCode upholdStatusCode) {
                                           NSDictionary *response = [parsedData isKindOfClass:NSDictionary.class] ? (NSDictionary *)parsedData : nil;

                                           DWUpholdTransactionObject *responseValidTransaction = [[DWUpholdTransactionObject alloc] initWithDictionary:response];

                                           if (completion) {
                                               completion(!!responseValidTransaction, upholdStatusCode);
                                           }
                                       }];
}

@end

NS_ASSUME_NONNULL_END
