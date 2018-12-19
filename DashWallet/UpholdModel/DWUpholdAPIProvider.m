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
#import "DSHTTPGETOperation.h"
#import "DWUpholdAuthParseResponseOperation.h"
#import "HTTPRequest.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const CLIENT_ID = @"7aadd33b84e942632ed7ffd9b09578bd64be2099";
static NSString *const CLIENT_SECRET = @"7db0b6bbf766233c0eafcad6b9d8667d526c899e";

@implementation DWUpholdAPIProvider

+ (NSOperation *)authOperationWithCode:(NSString *)code completion:(void (^)(NSString *_Nullable accessToken))completion {
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

    DSHTTPGETOperation *httpOperation = [[DSHTTPGETOperation alloc] initWithRequest:request];
    DWUpholdAuthParseResponseOperation *parseOperation = [[DWUpholdAuthParseResponseOperation alloc] init];
    DSChainedOperation *chainOperation = [DSChainedOperation operationWithOperations:@[ httpOperation, parseOperation ]];
    chainOperation.completionBlock = ^{
        if (completion) {
            completion(parseOperation.accessToken);
        }
    };

    return chainOperation;
}

+ (NSString *)baseURLString {
    return @"https://api-sandbox.uphold.com/";
}

@end

NS_ASSUME_NONNULL_END
