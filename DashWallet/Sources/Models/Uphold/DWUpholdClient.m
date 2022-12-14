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

#import "DWUpholdAPIProvider.h"
#import "DWUpholdAccountObject.h"
#import "DWUpholdCardObject.h"
#import "DWUpholdConstants.h"
#import "DWUpholdTransactionObject.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const UPHOLD_ACCESS_TOKEN = @"DW_UPHOLD_ACCESS_TOKEN";
static NSString *const UPHOLD_LAST_ACCESS = @"DW_UPHOLD_LAST_ACCESS";
static NSString *const UPHOLD_LAST_KNOWN_BALANCE = @"UPHOLD_LAST_KNOWN_BALANCE";

static NSTimeInterval const UPHOLD_KEEP_ALIVE_INTERVAL = 60.0 * 10.0; // 10 min

NSString *const DWUpholdClientUserDidLogoutNotification = @"DWUpholdClientUserDidLogoutNotification";

@interface DWUpholdClient ()

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
        [self performLogOutShouldNotifyObservers:NO];
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
    [DWUpholdAPIProvider authOperationWithCode:code
                                    completion:^(NSString *_Nullable accessToken) {
                                        __strong typeof(weakSelf) strongSelf = weakSelf;
                                        if (!strongSelf) {
                                            return;
                                        }

                                        strongSelf.accessToken = accessToken;
                                        if (accessToken) {
                                            setKeychainString(accessToken, UPHOLD_ACCESS_TOKEN, YES);
                                            strongSelf.lastAccessDate = [NSDate date];
                                        }

                                        if (completion) {
                                            completion(!!accessToken);
                                        }
                                    }];
}

- (void)getAccounts:(void (^)(NSArray<DWUpholdAccountObject *> *_Nullable accounts))completion {
    NSParameterAssert(self.accessToken);

    __weak typeof(self) weakSelf = self;
    [DWUpholdAPIProvider getUserAccountsAccessToken:self.accessToken
                                         completion:^(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, NSArray<DWUpholdAccountObject *> *_Nullable accounts) {
                                             __strong typeof(weakSelf) strongSelf = weakSelf;
                                             if (!strongSelf) {
                                                 return;
                                             }

                                             NSAssert(statusCode != DWUpholdAPIProviderResponseStatusCodeOTPRequired, @"OTP shouldn't be required here");

                                             // We support funding only by `card` accounts
                                             // (and seems there is no other way to fund your Uphold account via API using other types)
                                             NSArray<DWUpholdAccountObject *> *cardAccounts = nil;
                                             if (success) {
                                                 NSPredicate *predicate = [NSPredicate predicateWithFormat:@"type == %@",
                                                                                                           @(DWUpholdAccountObjectTypeCard)];
                                                 cardAccounts = [accounts filteredArrayUsingPredicate:predicate];
                                             }

                                             if (completion) {
                                                 completion(cardAccounts);
                                             }

                                             if (statusCode == DWUpholdAPIProviderResponseStatusCodeUnauthorized) {
                                                 [strongSelf performLogOutShouldNotifyObservers:YES];
                                             }
                                         }];
}

- (void)getCards:(void (^)(DWUpholdCardObject *_Nullable dashCard, NSArray<DWUpholdCardObject *> *fiatCards))completion {
    NSParameterAssert(self.accessToken);

    __weak typeof(self) weakSelf = self;
    [DWUpholdAPIProvider getCardsAccessToken:self.accessToken
                                  completion:^(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdCardObject *_Nullable dashCard, NSArray<DWUpholdCardObject *> *fiatCards) {
                                      __strong typeof(weakSelf) strongSelf = weakSelf;
                                      if (!strongSelf) {
                                          return;
                                      }

                                      NSAssert(statusCode != DWUpholdAPIProviderResponseStatusCodeOTPRequired, @"OTP shouldn't be required here");

                                      if (success) {
                                          if (dashCard) {
                                              [strongSelf setLastKnownBalance:dashCard.available];

                                              if (!dashCard.address) {
                                                  [strongSelf createDashCardAddress:dashCard
                                                                         completion:^(DWUpholdCardObject *_Nullable card) {
                                                                             if (completion) {
                                                                                 completion(card, fiatCards);
                                                                             }
                                                                         }];
                                              }
                                              else {
                                                  if (completion) {
                                                      completion(dashCard, fiatCards);
                                                  }
                                              }
                                          }
                                          else {
                                              [strongSelf createDashCard:^(DWUpholdCardObject *_Nullable card) {
                                                  if (completion) {
                                                      completion(card, fiatCards);
                                                  }
                                              }];
                                          }
                                      }
                                      else {
                                          if (completion) {
                                              completion(nil, @[]);
                                          }

                                          if (statusCode == DWUpholdAPIProviderResponseStatusCodeUnauthorized) {
                                              [strongSelf performLogOutShouldNotifyObservers:YES];
                                          }
                                      }
                                  }];
}

- (DWUpholdCancellationToken)createTransactionForDashCard:(DWUpholdCardObject *)card
                                                   amount:(NSString *)amount
                                                  address:(NSString *)address
                                                 otpToken:(nullable NSString *)otpToken
                                               completion:(void (^)(DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired))completion {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(card);
    NSParameterAssert(amount);
    NSParameterAssert(address);

    __weak typeof(self) weakSelf = self;
    return [DWUpholdAPIProvider createTransactionForDashCard:card
                                                      amount:amount
                                                     address:address
                                                 accessToken:self.accessToken
                                                    otpToken:otpToken
                                                  completion:^(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdTransactionObject *_Nullable transaction) {
                                                      __strong typeof(weakSelf) strongSelf = weakSelf;
                                                      if (!strongSelf) {
                                                          return;
                                                      }

                                                      if (completion) {
                                                          BOOL otpRequired = (statusCode == DWUpholdAPIProviderResponseStatusCodeOTPRequired) ||
                                                                             (statusCode == DWUpholdAPIProviderResponseStatusCodeOTPInvalid);
                                                          completion(success ? transaction : nil, otpRequired);
                                                      }

                                                      if (statusCode == DWUpholdAPIProviderResponseStatusCodeUnauthorized) {
                                                          [strongSelf performLogOutShouldNotifyObservers:YES];
                                                      }
                                                  }];
}

- (DWUpholdCancellationToken)createBuyTransactionForDashCard:(DWUpholdCardObject *)card
                                                     account:(DWUpholdAccountObject *)account
                                                      amount:(NSString *)amount
                                                securityCode:(NSString *)securityCode
                                                    otpToken:(nullable NSString *)otpToken
                                                  completion:(void (^)(DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired))completion {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(card);
    NSParameterAssert(account);
    NSParameterAssert(amount);
    NSParameterAssert(securityCode);

    __weak typeof(self) weakSelf = self;
    return [DWUpholdAPIProvider createBuyTransactionForDashCard:card
                                                        account:account
                                                         amount:amount
                                                   securityCode:securityCode
                                                    accessToken:self.accessToken
                                                       otpToken:otpToken
                                                     completion:^(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdTransactionObject *_Nullable transaction) {
                                                         __strong typeof(weakSelf) strongSelf = weakSelf;
                                                         if (!strongSelf) {
                                                             return;
                                                         }

                                                         if (completion) {
                                                             BOOL otpRequired = (statusCode == DWUpholdAPIProviderResponseStatusCodeOTPRequired) ||
                                                                                (statusCode == DWUpholdAPIProviderResponseStatusCodeOTPInvalid);
                                                             completion(success ? transaction : nil, otpRequired);
                                                         }

                                                         if (statusCode == DWUpholdAPIProviderResponseStatusCodeUnauthorized) {
                                                             [strongSelf performLogOutShouldNotifyObservers:YES];
                                                         }
                                                     }];
}

- (void)commitTransaction:(DWUpholdTransactionObject *)transaction
                     card:(DWUpholdCardObject *)card
                 otpToken:(nullable NSString *)otpToken
               completion:(void (^)(BOOL success, BOOL otpRequired))completion {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(transaction);
    NSParameterAssert(card);

    __weak typeof(self) weakSelf = self;
    [DWUpholdAPIProvider commitTransaction:transaction
                                      card:card
                               accessToken:self.accessToken
                                  otpToken:otpToken
                                completion:^(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode) {
                                    __strong typeof(weakSelf) strongSelf = weakSelf;
                                    if (!strongSelf) {
                                        return;
                                    }

                                    if (completion) {
                                        BOOL otpRequired = (statusCode == DWUpholdAPIProviderResponseStatusCodeOTPRequired) ||
                                                           (statusCode == DWUpholdAPIProviderResponseStatusCodeOTPInvalid);
                                        completion(success, otpRequired);
                                    }

                                    if (statusCode == DWUpholdAPIProviderResponseStatusCodeUnauthorized) {
                                        [strongSelf performLogOutShouldNotifyObservers:YES];
                                    }
                                }];
}

- (void)cancelTransaction:(DWUpholdTransactionObject *)transaction
                     card:(DWUpholdCardObject *)card {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(transaction);
    NSParameterAssert(card);

    __weak typeof(self) weakSelf = self;
    [DWUpholdAPIProvider cancelTransaction:transaction
                                      card:card
                               accessToken:self.accessToken
                                  otpToken:nil
                                completion:^(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode) {
                                    __strong typeof(weakSelf) strongSelf = weakSelf;
                                    if (!strongSelf) {
                                        return;
                                    }

                                    NSAssert(statusCode != DWUpholdAPIProviderResponseStatusCodeOTPRequired, @"OTP shouldn't be required here");

                                    if (statusCode == DWUpholdAPIProviderResponseStatusCodeUnauthorized) {
                                        [strongSelf performLogOutShouldNotifyObservers:YES];
                                    }
                                }];
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
    [self performLogOutShouldNotifyObservers:YES];
}

#pragma mark - Private

- (void)createDashCard:(void (^)(DWUpholdCardObject *_Nullable card))completion {
    NSParameterAssert(self.accessToken);

    __weak typeof(self) weakSelf = self;
    [DWUpholdAPIProvider createDashCardAccessToken:self.accessToken
                                        completion:^(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdCardObject *_Nullable card) {
                                            __strong typeof(weakSelf) strongSelf = weakSelf;
                                            if (!strongSelf) {
                                                return;
                                            }

                                            NSAssert(statusCode != DWUpholdAPIProviderResponseStatusCodeOTPRequired, @"OTP shouldn't be required here");

                                            if (success && card) {
                                                [strongSelf createDashCardAddress:card completion:completion];
                                            }
                                            else {
                                                if (completion) {
                                                    completion(nil);
                                                }

                                                if (statusCode == DWUpholdAPIProviderResponseStatusCodeUnauthorized) {
                                                    [strongSelf performLogOutShouldNotifyObservers:YES];
                                                }
                                            }
                                        }];
}

- (void)createDashCardAddress:(DWUpholdCardObject *)card completion:(void (^)(DWUpholdCardObject *_Nullable card))completion {
    NSParameterAssert(self.accessToken);
    NSParameterAssert(card);
    NSAssert(!card.address, @"Card has address already");

    __weak typeof(self) weakSelf = self;
    [DWUpholdAPIProvider createAddressForDashCard:card
                                      accessToken:self.accessToken
                                       completion:^(BOOL success, DWUpholdAPIProviderResponseStatusCode statusCode, DWUpholdCardObject *_Nullable card) {
                                           __strong typeof(weakSelf) strongSelf = weakSelf;
                                           if (!strongSelf) {
                                               return;
                                           }

                                           NSAssert(statusCode != DWUpholdAPIProviderResponseStatusCodeOTPRequired, @"OTP shouldn't be required here");

                                           if (completion) {
                                               completion(success ? card : nil);
                                           }

                                           if (statusCode == DWUpholdAPIProviderResponseStatusCodeUnauthorized) {
                                               [strongSelf performLogOutShouldNotifyObservers:YES];
                                           }
                                       }];
}

- (nullable NSDate *)lastAccessDate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:UPHOLD_LAST_ACCESS];
}

- (void)setLastAccessDate:(nullable NSDate *)lastAccessDate {
    [[NSUserDefaults standardUserDefaults] setObject:lastAccessDate forKey:UPHOLD_LAST_ACCESS];
}

- (nullable NSDecimalNumber *)lastKnownBalance {
    return [[NSUserDefaults standardUserDefaults] objectForKey:UPHOLD_LAST_KNOWN_BALANCE];
}

- (void)setLastKnownBalance:(nullable NSDecimalNumber *)balance {
    [[NSUserDefaults standardUserDefaults] setObject:balance forKey:UPHOLD_LAST_KNOWN_BALANCE];
}

- (void)performLogOutShouldNotifyObservers:(BOOL)shouldNotify {
    NSAssert([NSThread isMainThread], @"Not allowed to call on thread other than main");

    if (self.accessToken) {
        [DWUpholdAPIProvider revokeAccessToken:self.accessToken];
    }

    self.accessToken = nil;
    self.lastAccessDate = nil;
    setKeychainData(nil, UPHOLD_ACCESS_TOKEN, YES);

    if (shouldNotify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DWUpholdClientUserDidLogoutNotification object:nil];
    }
}

@end

NS_ASSUME_NONNULL_END
