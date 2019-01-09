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
#import "DWUpholdConstants.h"
#import "DWUpholdTransactionObject.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const UPHOLD_ACCESS_TOKEN = @"DW_UPHOLD_ACCESS_TOKEN";
static NSString *const UPHOLD_LAST_ACCESS = @"DW_UPHOLD_LAST_ACCESS";

static NSTimeInterval const UPHOLD_KEEP_ALIVE_INTERVAL = 60.0 * 10.0; // 10 min

#pragma mark - NSOperation Extension

@interface NSOperation (DWUpholdClient) <DWUpholdClientCancellationToken>

@end

@implementation NSOperation (DWUpholdClient)

@end

#pragma mark - Client

@interface DWUpholdClient ()

@property (strong, nonatomic) DSOperationQueue *operationQueue;

@property (nullable, copy, nonatomic) NSString *upholdState;
@property (nullable, copy, nonatomic) NSString *accessToken;
@property (nullable, strong, nonatomic) NSDate *lastAccessDate;

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
    if (!self.accessToken) {
        return NO;
    }

    NSTimeInterval timeInterval = -[self.lastAccessDate timeIntervalSinceNow];
    if (timeInterval > UPHOLD_KEEP_ALIVE_INTERVAL) {
        [self logOut];
        return NO;
    }

    [self updateLastAccessDate];

    return YES;
}

- (NSURL *)startAuthRoutineByURL {
    NSUUID *uuid = [NSUUID UUID];
    self.upholdState = [NSString stringWithFormat:@"oauth2:%@", uuid.UUIDString];
    NSString *urlString = [NSString stringWithFormat:[DWUpholdConstants authorizeURLFormat], self.upholdState];
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
            strongSelf.lastAccessDate = [NSDate date];
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

- (id<DWUpholdClientCancellationToken>)createTransactionForDashCard:(DWUpholdCardObject *)card
                                                             amount:(NSString *)amount
                                                            address:(NSString *)address
                                                           otpToken:(nullable NSString *)otpToken
                                                         completion:(void (^)(DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired))completion {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(card);
    NSParameterAssert(amount);
    NSParameterAssert(address);

    NSOperation *operation = [DWUpholdAPIProvider createTransactionForDashCard:card amount:amount address:address accessToken:self.accessToken otpToken:otpToken completion:^(BOOL success, DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(success ? transaction : nil, otpRequired);
            }
        });
    }];
    [self.operationQueue addOperation:operation];

    return operation;
}

- (void)commitTransaction:(DWUpholdTransactionObject *)transaction
                     card:(DWUpholdCardObject *)card
                 otpToken:(nullable NSString *)otpToken
               completion:(void (^)(BOOL success, BOOL otpRequired))completion {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(transaction);
    NSParameterAssert(card);

    NSOperation *operation = [DWUpholdAPIProvider commitTransaction:transaction
                                                               card:card
                                                        accessToken:self.accessToken
                                                           otpToken:otpToken
                                                         completion:^(BOOL success, BOOL otpRequired) {
                                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                                 if (completion) {
                                                                     completion(success, otpRequired);
                                                                 }
                                                             });
                                                         }];
    [self.operationQueue addOperation:operation];
}

- (void)cancelTransaction:(DWUpholdTransactionObject *)transaction
                     card:(DWUpholdCardObject *)card {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(transaction);
    NSParameterAssert(card);

    NSOperation *operation = [DWUpholdAPIProvider cancelTransaction:transaction
                                                               card:card
                                                        accessToken:self.accessToken
                                                           otpToken:nil];
    [self.operationQueue addOperation:operation];
}

- (nullable NSURL *)buyDashURLForCard:(DWUpholdCardObject *)card {
    if (!card.identifier) {
        return nil;
    }

    NSString *urlString = [NSString stringWithFormat:[DWUpholdConstants buyCardURLFormat], card.identifier];
    NSURL *url = [NSURL URLWithString:urlString];
    NSParameterAssert(url);

    return url;
}

- (nullable NSURL *)transactionURLForTransaction:(DWUpholdTransactionObject *)transaction {
    if (!transaction.identifier) {
        return nil;
    }

    NSString *urlString = [NSString stringWithFormat:[DWUpholdConstants transactionURLFormat], transaction.identifier];
    NSURL *url = [NSURL URLWithString:urlString];
    NSParameterAssert(url);

    return url;
}

- (void)updateLastAccessDate {
    if (self.accessToken) {
        self.lastAccessDate = [NSDate date];
    }
}

- (void)logOut {
    self.accessToken = nil;
    self.lastAccessDate = nil;
    setKeychainData(nil, UPHOLD_ACCESS_TOKEN, YES);
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

    NSOperation *operation = [DWUpholdAPIProvider createAddressForDashCard:card accessToken:self.accessToken completion:^(BOOL success, DWUpholdCardObject *_Nullable card) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(success ? card : nil);
            }
        });
    }];
    [self.operationQueue addOperation:operation];
}

- (nullable NSDate *)lastAccessDate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:UPHOLD_LAST_ACCESS];
}

- (void)setLastAccessDate:(nullable NSDate *)lastAccessDate {
    [[NSUserDefaults standardUserDefaults] setObject:lastAccessDate forKey:UPHOLD_LAST_ACCESS];
}

@end

NS_ASSUME_NONNULL_END
