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

#import "DWUpholdClient.h"

#import "DSOperationQueue.h"
#import "DWUpholdAPIProvider.h"
#import "DWUpholdCardObject.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const INITIAL_URL_FORMAT = @"https://sandbox.uphold.com/authorize/7aadd33b84e942632ed7ffd9b09578bd64be2099?scope=accounts:read%%20cards:read%%20cards:write%%20transactions:deposit%%20transactions:read%%20transactions:transfer:application%%20transactions:transfer:others%%20transactions:transfer:self%%20transactions:withdraw%%20transactions:commit:otp%%20user:read&state=%@";

static NSString *const UPHOLD_ACCESS_TOKEN = @"DW_UPHOLD_ACCESS_TOKEN";

@interface DWUpholdClient ()

@property (strong, nonatomic) DSOperationQueue *operationQueue;

@property (nullable, copy, nonatomic) NSString *upholdState;
@property (nullable, copy, nonatomic) NSString *accessToken;

@end

@implementation DWUpholdClient

+ (instancetype)sharedInstance {
    static DWUpholdClient *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _operationQueue = [[DSOperationQueue alloc] init];
        _operationQueue.maxConcurrentOperationCount = 1;
        _operationQueue.name = @"org.dash.upholdclient";

        _accessToken = getKeychainString(UPHOLD_ACCESS_TOKEN, nil);
    }
    return self;
}

- (BOOL)isAuthorized {
    return !!self.accessToken;
}

- (NSURL *)startAuthRoutineByURL {
    NSUUID *uuid = [NSUUID UUID];
    self.upholdState = [NSString stringWithFormat:@"oauth2:%@", uuid.UUIDString];
    NSString *urlString = [NSString stringWithFormat:INITIAL_URL_FORMAT, self.upholdState];
    NSURL *url = [NSURL URLWithString:urlString];
    NSParameterAssert(url);
    return url;
}

- (void)completeAuthRoutineWithURL:(NSURL *)url completion:(void (^)(BOOL success))completion {
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSArray<NSURLQueryItem *> *queryItems = urlComponents.queryItems;
    NSString *state = nil;
    NSString *code = nil;
    for (NSURLQueryItem *item in queryItems) {
        if ([item.name isEqualToString:@"state"]) {
            state = item.value;
        }
        else if ([item.name isEqualToString:@"code"]) {
            code = item.value;
        }

        if (state && code) {
            break;
        }
    }

    if (![state isEqualToString:self.upholdState] || !code) {
        if (completion) {
            completion(NO);
        }

        return;
    }

    __weak typeof(self) weakSelf = self;
    NSOperation *operation = [DWUpholdAPIProvider authOperationWithCode:code completion:^(NSString *_Nullable accessToken) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.accessToken = accessToken;
        if (accessToken) {
            setKeychainString(accessToken, UPHOLD_ACCESS_TOKEN, YES);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(!!accessToken);
            }
        });
    }];
    [self.operationQueue addOperation:operation];
}

- (void)getDashCard:(void (^)(DWUpholdCardObject *_Nullable card))completion {
    NSParameterAssert(self.accessToken);

    __weak typeof(self) weakSelf = self;
    NSOperation *operation = [DWUpholdAPIProvider getDashCardAccessToken:self.accessToken completion:^(BOOL success, DWUpholdCardObject *_Nullable card) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        if (success) {
            if (card) {
                if (!card.address) {
                    [strongSelf createDashCardAddress:card completion:completion];
                }
                else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) {
                            completion(card);
                        }
                    });
                }
            }
            else {
                [strongSelf createDashCard:completion];
            }
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil);
                }
            });
        }
    }];
    [self.operationQueue addOperation:operation];
}

#pragma mark - Private

- (void)createDashCard:(void (^)(DWUpholdCardObject *_Nullable card))completion {
    NSParameterAssert(self.accessToken);
    
    __weak typeof(self) weakSelf = self;
    NSOperation *operation = [DWUpholdAPIProvider createDashCardAccessToken:self.accessToken completion:^(BOOL success, DWUpholdCardObject *_Nullable card) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        if (success && card) {
            [strongSelf createDashCardAddress:card completion:completion];
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil);
                }
            });
        }
    }];
    [self.operationQueue addOperation:operation];
}

- (void)createDashCardAddress:(DWUpholdCardObject *)card completion:(void (^)(DWUpholdCardObject *_Nullable card))completion {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(card);
    NSAssert(!card.address, @"Card has address already");

    NSOperation *operation = [DWUpholdAPIProvider createAddressForDashCard:card accessToken:self.accessToken completion:^(BOOL success, DWUpholdCardObject * _Nullable card) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(success ? card : nil);
            }
        });
    }];
    [self.operationQueue addOperation:operation];
}

@end

NS_ASSUME_NONNULL_END
