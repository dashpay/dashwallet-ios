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

#import "DWUpholdCardObject+Internal.h"
#import "DWUpholdCardObject.h"
#import "DWUpholdConstants.h"
#import "DWUpholdTransactionObject.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const UPHOLD_ACCESS_TOKEN = @"DW_UPHOLD_ACCESS_TOKEN";
static NSString *const UPHOLD_LAST_KNOWN_BALANCE = @"UPHOLD_LAST_KNOWN_BALANCE";

NSString *const DWUpholdClientUserDidLogoutNotification = @"DWUpholdClientUserDidLogoutNotification";

static NSSet<NSString *> *FiatCurrencyCodes(void) {
    return [NSSet setWithObjects:
                      @"ARS", @"AUD", @"BRL", @"CAD", @"DKK", @"AED", @"EUR", @"HKD", @"INR", @"ILS", @"KES",
                      @"MXN", @"NZD", @"NOK", @"PHP", @"PLN", @"GBP", @"SGD", @"SEK", @"CHF", @"USD", @"JPY", @"CNY", nil];
}

static BOOL DWUpholdStatusRequiresOTP(UpholdAPIResponseStatus status) {
    return status == UpholdAPIResponseStatusOtpRequired || status == UpholdAPIResponseStatusOtpInvalid;
}

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
        _accessToken = [DWKeychainStore stringForAccount:UPHOLD_ACCESS_TOKEN];
    }
    return self;
}

- (BOOL)isAuthorized {
    if (!self.accessToken) {
        return NO;
    }

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
    [[UpholdClientObjcBridge shared] authorizeWithCode:code
                                            completion:^(NSString *_Nullable accessToken) {
                                                __strong typeof(weakSelf) strongSelf = weakSelf;
                                                if (!strongSelf) {
                                                    return;
                                                }

                                                strongSelf.accessToken = accessToken;
                                                if (accessToken) {
                                                    [DWKeychainStore setString:accessToken
                                                                    forAccount:UPHOLD_ACCESS_TOKEN
                                                                 authenticated:YES];
                                                    strongSelf.lastAccessDate = [NSDate date];
                                                }

                                                if (completion) {
                                                    completion(!!accessToken);
                                                }
                                            }];
}

- (void)getCards:(void (^)(DWUpholdCardObject *_Nullable dashCard, NSArray<DWUpholdCardObject *> *fiatCards))completion {
    NSParameterAssert(self.accessToken);

    __weak typeof(self) weakSelf = self;
    [[UpholdClientObjcBridge shared] getCardsWithAccessToken:self.accessToken
                                                  completion:^(NSArray<NSDictionary *> *_Nullable response, UpholdAPIResponseStatus statusCode) {
                                                      __strong typeof(weakSelf) strongSelf = weakSelf;
                                                      if (!strongSelf) {
                                                          return;
                                                      }

                                                      NSAssert(statusCode != UpholdAPIResponseStatusOtpRequired, @"OTP shouldn't be required here");

                                                      NSMutableArray<DWUpholdCardObject *> *dashCards = [NSMutableArray array];
                                                      NSMutableArray<DWUpholdCardObject *> *fiatCards = [NSMutableArray array];
                                                      NSSet<NSString *> *fiatCurrencyCodes = FiatCurrencyCodes();
                                                      for (NSDictionary *dictionary in response) {
                                                          if (![dictionary isKindOfClass:NSDictionary.class]) {
                                                              break;
                                                          }

                                                          NSString *currency = dictionary[@"currency"];
                                                          if (![currency isKindOfClass:NSString.class]) {
                                                              break;
                                                          }

                                                          currency = currency.uppercaseString;
                                                          DWUpholdCardObject *card = [[DWUpholdCardObject alloc] initWithDictionary:dictionary];
                                                          if ([currency isEqualToString:@"DASH"]) {
                                                              if (card) {
                                                                  [dashCards addObject:card];
                                                              }
                                                          }
                                                          else if ([fiatCurrencyCodes containsObject:currency] &&
                                                                   card &&
                                                                   (card.available.doubleValue > 0.0 ||
                                                                    [currency isEqualToString:@"USD"] ||
                                                                    [currency isEqualToString:@"EUR"])) {
                                                              [fiatCards addObject:card];
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

                                                      if (response && statusCode == UpholdAPIResponseStatusOk) {
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

                                                          if (statusCode == UpholdAPIResponseStatusUnauthorized) {
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
    return [[UpholdClientObjcBridge shared] createTransactionWithCardIdentifier:card.identifier
                                                                         amount:amount
                                                                        address:address
                                                                       otpToken:otpToken
                                                                    accessToken:self.accessToken
                                                                     completion:^(NSDictionary *_Nullable response, UpholdAPIResponseStatus statusCode) {
                                                                         __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                         if (!strongSelf) {
                                                                             return;
                                                                         }

                                                                         DWUpholdTransactionObject *transaction =
                                                                             [[DWUpholdTransactionObject alloc] initWithDictionary:response];
                                                                         if (completion) {
                                                                             completion(transaction, DWUpholdStatusRequiresOTP(statusCode));
                                                                         }

                                                                         if (statusCode == UpholdAPIResponseStatusUnauthorized) {
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
    [[UpholdClientObjcBridge shared] commitTransactionWithCardIdentifier:card.identifier
                                                   transactionIdentifier:transaction.identifier
                                                                otpToken:otpToken
                                                             accessToken:self.accessToken
                                                              completion:^(NSDictionary *_Nullable response, UpholdAPIResponseStatus statusCode) {
                                                                  __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                  if (!strongSelf) {
                                                                      return;
                                                                  }

                                                                  DWUpholdTransactionObject *responseTransaction =
                                                                      [[DWUpholdTransactionObject alloc] initWithDictionary:response];
                                                                  if (completion) {
                                                                      completion(responseTransaction != nil, DWUpholdStatusRequiresOTP(statusCode));
                                                                  }

                                                                  if (statusCode == UpholdAPIResponseStatusUnauthorized) {
                                                                      [strongSelf performLogOutShouldNotifyObservers:YES];
                                                                  }
                                                              }];
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

- (void)logOut {
    [self performLogOutShouldNotifyObservers:YES];
}

#pragma mark - Private

- (void)createDashCard:(void (^)(DWUpholdCardObject *_Nullable card))completion {
    NSParameterAssert(self.accessToken);

    __weak typeof(self) weakSelf = self;
    [[UpholdClientObjcBridge shared] createDashCardWithAccessToken:self.accessToken
                                                        completion:^(NSDictionary *_Nullable response, UpholdAPIResponseStatus statusCode) {
                                                            __strong typeof(weakSelf) strongSelf = weakSelf;
                                                            if (!strongSelf) {
                                                                return;
                                                            }

                                                            NSAssert(statusCode != UpholdAPIResponseStatusOtpRequired, @"OTP shouldn't be required here");

                                                            DWUpholdCardObject *card = [[DWUpholdCardObject alloc] initWithDictionary:response];
                                                            if (card) {
                                                                [strongSelf createDashCardAddress:card completion:completion];
                                                            }
                                                            else {
                                                                if (completion) {
                                                                    completion(nil);
                                                                }

                                                                if (statusCode == UpholdAPIResponseStatusUnauthorized) {
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
    [[UpholdClientObjcBridge shared] createAddressWithCardIdentifier:card.identifier
                                                         accessToken:self.accessToken
                                                          completion:^(NSDictionary *_Nullable response, UpholdAPIResponseStatus statusCode) {
                                                              __strong typeof(weakSelf) strongSelf = weakSelf;
                                                              if (!strongSelf) {
                                                                  return;
                                                              }

                                                              NSAssert(statusCode != UpholdAPIResponseStatusOtpRequired, @"OTP shouldn't be required here");

                                                              NSString *address = response[@"id"];
                                                              if ([address isKindOfClass:NSString.class]) {
                                                                  [card updateAddress:address];
                                                              }

                                                              if (completion) {
                                                                  completion(response ? card : nil);
                                                              }

                                                              if (statusCode == UpholdAPIResponseStatusUnauthorized) {
                                                                  [strongSelf performLogOutShouldNotifyObservers:YES];
                                                              }
                                                          }];
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
        [[UpholdClientObjcBridge shared] revokeWithAccessToken:self.accessToken];
    }

    self.accessToken = nil;
    self.lastAccessDate = nil;
    [DWKeychainStore setData:nil forAccount:UPHOLD_ACCESS_TOKEN authenticated:YES];

    if (shouldNotify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DWUpholdClientUserDidLogoutNotification object:nil];
    }
}

@end

NS_ASSUME_NONNULL_END
