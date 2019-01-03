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

#import "DSChainedOperation.h"
#import "DSHTTPOperation.h"
#import "DWUpholdAuthParseResponseOperation.h"
#import "DWUpholdCardObject.h"
#import "DWUpholdCreateCardAddressParseResponseOperation.h"
#import "DWUpholdCreateCardParseResponseOperation.h"
#import "DWUpholdCreateTransactionParseResponseOperation.h"
#import "DWUpholdGetCardParseResponseOperation.h"
#import "DWUpholdProcessTransactionParseResponseOperation.h"
#import "DWUpholdTransactionObject.h"
#import "HTTPRequest.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const CLIENT_ID = @"7aadd33b84e942632ed7ffd9b09578bd64be2099";
static NSString *const CLIENT_SECRET = @"7db0b6bbf766233c0eafcad6b9d8667d526c899e";

@implementation DWUpholdAPIProvider

+ (NSOperation *)authOperationWithCode:(NSString *)code
                            completion:(void (^)(NSString *_Nullable accessToken))completion {
    NSParameterAssert(code);

    NSString *urlString = [[self baseURLString] stringByAppendingPathComponent:@"oauth2/token"];
    NSURL *url = [NSURL URLWithString:urlString];
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                                parameters:@{
                                                    @"code" : code,
                                                    @"grant_type" : @"authorization_code",
                                                }];
    [httpRequest setBasicAuthWithUsername:CLIENT_ID password:CLIENT_SECRET];

    NSURLRequest *request = [httpRequest urlRequest];

    DSHTTPOperation *httpOperation = [[DSHTTPOperation alloc] initWithRequest:request];
    DWUpholdAuthParseResponseOperation *parseOperation = [[DWUpholdAuthParseResponseOperation alloc] init];
    DSChainedOperation *chainOperation = [DSChainedOperation operationWithOperations:@[ httpOperation, parseOperation ]];
    chainOperation.completionBlock = ^{
        if (completion) {
            completion(parseOperation.accessToken);
        }
    };

    return chainOperation;
}

+ (NSOperation *)getDashCardAccessToken:(NSString *)accessToken
                             completion:(void (^)(BOOL success, DWUpholdCardObject *_Nullable card))completion {
    NSString *urlString = [[self baseURLString] stringByAppendingPathComponent:@"v0/me/cards"];
    NSURL *url = [NSURL URLWithString:urlString];
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_GET
                                                parameters:nil];
    [self authorizeHTTPRequest:httpRequest accessToken:accessToken];

    NSURLRequest *request = [httpRequest urlRequest];

    DSHTTPOperation *httpOperation = [[DSHTTPOperation alloc] initWithRequest:request];
    DWUpholdGetCardParseResponseOperation *parseOperation = [[DWUpholdGetCardParseResponseOperation alloc] init];
    DSChainedOperation *chainOperation = [DSChainedOperation operationWithOperations:@[ httpOperation, parseOperation ]];
    chainOperation.completionBlock = ^{
        if (completion) {
            BOOL success = !httpOperation.internalErrors.firstObject && !parseOperation.internalErrors.firstObject;
            completion(success, parseOperation.card);
        }
    };

    return chainOperation;
}


+ (NSOperation *)createDashCardAccessToken:(NSString *)accessToken
                                completion:(void (^)(BOOL success, DWUpholdCardObject *_Nullable card))completion {
    NSString *urlString = [[self baseURLString] stringByAppendingPathComponent:@"v0/me/cards"];
    NSURL *url = [NSURL URLWithString:urlString];
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                               contentType:HTTPContentType_JSON
                                                parameters:@{
                                                    @"label" : @"Dash Card",
                                                    @"currency" : @"DASH",
                                                }];
    [self authorizeHTTPRequest:httpRequest accessToken:accessToken];

    NSURLRequest *request = [httpRequest urlRequest];

    DSHTTPOperation *httpOperation = [[DSHTTPOperation alloc] initWithRequest:request];
    DWUpholdCreateCardParseResponseOperation *parseOperation = [[DWUpholdCreateCardParseResponseOperation alloc] init];
    DSChainedOperation *chainOperation = [DSChainedOperation operationWithOperations:@[ httpOperation, parseOperation ]];
    chainOperation.completionBlock = ^{
        if (completion) {
            BOOL success = !httpOperation.internalErrors.firstObject && !parseOperation.internalErrors.firstObject;
            completion(success, parseOperation.card);
        }
    };

    return chainOperation;
}

+ (NSOperation *)createAddressForDashCard:(DWUpholdCardObject *)inputCard
                              accessToken:(NSString *)accessToken
                               completion:(void (^)(BOOL success, DWUpholdCardObject *_Nullable card))completion {
    NSString *urlPath = [NSString stringWithFormat:@"v0/me/cards/%@/addresses", inputCard.identifier];
    NSString *urlString = [[self baseURLString] stringByAppendingPathComponent:urlPath];
    NSURL *url = [NSURL URLWithString:urlString];
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                               contentType:HTTPContentType_JSON
                                                parameters:@{
                                                    @"network" : @"dash",
                                                }];
    [self authorizeHTTPRequest:httpRequest accessToken:accessToken];

    NSURLRequest *request = [httpRequest urlRequest];

    DSHTTPOperation *httpOperation = [[DSHTTPOperation alloc] initWithRequest:request];
    DWUpholdCreateCardAddressParseResponseOperation *parseOperation =
        [[DWUpholdCreateCardAddressParseResponseOperation alloc] initWithCard:inputCard];
    DSChainedOperation *chainOperation = [DSChainedOperation operationWithOperations:@[ httpOperation, parseOperation ]];
    chainOperation.completionBlock = ^{
        if (completion) {
            BOOL success = !httpOperation.internalErrors.firstObject &&
                           !parseOperation.internalErrors.firstObject &&
                           parseOperation.card.address;
            completion(success, parseOperation.card);
        }
    };

    return chainOperation;
}

+ (NSOperation *)createTransactionForDashCard:(DWUpholdCardObject *)card
                                       amount:(NSString *)amount
                                      address:(NSString *)address
                                  accessToken:(NSString *)accessToken
                                     otpToken:(nullable NSString *)otpToken
                                   completion:(void (^)(BOOL success, DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired))completion {
    NSParameterAssert(amount);
    NSParameterAssert(address);
    NSString *urlPath = [NSString stringWithFormat:@"v0/me/cards/%@/transactions", card.identifier];
    NSString *urlString = [[self baseURLString] stringByAppendingPathComponent:urlPath];
    NSURL *url = [NSURL URLWithString:urlString];
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
    [self authorizeHTTPRequest:httpRequest accessToken:accessToken];
    if (otpToken) {
        [self authorizeHTTPRequest:httpRequest otpToken:otpToken];
    }

    NSURLRequest *request = [httpRequest urlRequest];

    DSHTTPOperation *httpOperation = [[DSHTTPOperation alloc] initWithRequest:request];
    DWUpholdCreateTransactionParseResponseOperation *parseOperation =
        [[DWUpholdCreateTransactionParseResponseOperation alloc] init];
    DSChainedOperation *chainOperation = [DSChainedOperation operationWithOperations:@[ httpOperation, parseOperation ]];
    chainOperation.completionBlock = ^{
        if (completion) {
            BOOL success = !httpOperation.internalErrors.firstObject && !parseOperation.internalErrors.firstObject;
            DSHTTPOperationResult *httpOperationResult = httpOperation.result;
            NSString *otpTokenHeader = httpOperationResult.responseHeaders[@"OTP-Token"];
            BOOL otpRequired = (otpTokenHeader && [otpTokenHeader caseInsensitiveCompare:@"required"] == NSOrderedSame);
            completion(success, parseOperation.transaction, otpRequired);
        }
    };

    return chainOperation;
}

+ (NSOperation *)commitTransaction:(DWUpholdTransactionObject *)transaction
                              card:(DWUpholdCardObject *)card
                       accessToken:(NSString *)accessToken
                          otpToken:(nullable NSString *)otpToken
                        completion:(void (^)(BOOL success, BOOL otpRequired))completion {
    NSOperation *operation = [self transactionAction:@"commit"
                                         transaction:transaction
                                                card:card
                                         accessToken:accessToken
                                            otpToken:otpToken
                                          completion:completion];

    return operation;
}

+ (NSOperation *)cancelTransaction:(DWUpholdTransactionObject *)transaction
                              card:(DWUpholdCardObject *)card
                       accessToken:(NSString *)accessToken
                          otpToken:(nullable NSString *)otpToken {
    NSOperation *operation = [self transactionAction:@"cancel"
                                         transaction:transaction
                                                card:card
                                         accessToken:accessToken
                                            otpToken:otpToken
                                          completion:nil];

    return operation;
}

#pragma mark - Private

+ (NSString *)baseURLString {
    return @"https://api-sandbox.uphold.com/";
}

+ (void)authorizeHTTPRequest:(HTTPRequest *)request accessToken:(NSString *)accessToken {
    NSString *authorizationHeader = [NSString stringWithFormat:@"Bearer %@", accessToken];
    [request addValue:authorizationHeader forHeader:@"Authorization"];
}

+ (void)authorizeHTTPRequest:(HTTPRequest *)request otpToken:(NSString *)otpToken {
    [request addValue:otpToken forHeader:@"OTP-Token"];
}

+ (NSOperation *)transactionAction:(NSString *)action
                       transaction:(DWUpholdTransactionObject *)transaction
                              card:(DWUpholdCardObject *)card
                       accessToken:(NSString *)accessToken
                          otpToken:(nullable NSString *)otpToken
                        completion:(void (^_Nullable)(BOOL success, BOOL otpRequired))completion {
    NSAssert([action isEqualToString:@"commit"] || [action isEqualToString:@"cancel"], @"Invalid action on transaction");

    NSString *urlPath = [NSString stringWithFormat:@"v0/me/cards/%@/transactions/%@/%@",
                                                   card.identifier,
                                                   transaction.identifier,
                                                   action];
    NSString *urlString = [[self baseURLString] stringByAppendingPathComponent:urlPath];
    NSURL *url = [NSURL URLWithString:urlString];
    HTTPRequest *httpRequest = [HTTPRequest requestWithURL:url
                                                    method:HTTPRequestMethod_POST
                                                parameters:nil];
    [self authorizeHTTPRequest:httpRequest accessToken:accessToken];
    if (otpToken) {
        [self authorizeHTTPRequest:httpRequest otpToken:otpToken];
    }

    NSURLRequest *request = [httpRequest urlRequest];

    DSHTTPOperation *httpOperation = [[DSHTTPOperation alloc] initWithRequest:request];
    DWUpholdProcessTransactionParseResponseOperation *parseOperation =
        [[DWUpholdProcessTransactionParseResponseOperation alloc] init];
    DSChainedOperation *chainOperation = [DSChainedOperation operationWithOperations:@[ httpOperation, parseOperation ]];
    chainOperation.completionBlock = ^{
        if (completion) {
            BOOL success = !httpOperation.internalErrors.firstObject && !parseOperation.internalErrors.firstObject;
            DSHTTPOperationResult *httpOperationResult = httpOperation.result;
            NSString *otpTokenHeader = httpOperationResult.responseHeaders[@"OTP-Token"];
            BOOL otpRequired = (otpTokenHeader && [otpTokenHeader caseInsensitiveCompare:@"required"] == NSOrderedSame) ||
                               parseOperation.result == DWUpholdProcessTransactionParseResponseOperationResultOTPError;
            if (otpRequired) {
                success = NO;
            }
            completion(success, otpRequired);
        }
    };

    return chainOperation;
}

@end

NS_ASSUME_NONNULL_END
