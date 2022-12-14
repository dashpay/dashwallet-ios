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

#import <Foundation/Foundation.h>

#import "DWUpholdClientCancellationToken.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const DWUpholdClientUserDidLogoutNotification;

@class DWUpholdCardObject;
@class DWUpholdTransactionObject;
@class DWUpholdAccountObject;

@interface DWUpholdClient : NSObject

@property (readonly, assign, nonatomic, getter=isAuthorized) BOOL authorized;
@property (nullable, strong, nonatomic) NSDecimalNumber *lastKnownBalance;

+ (instancetype)sharedInstance;

- (NSURL *)startAuthRoutineByURL;
- (void)completeAuthRoutineWithURL:(NSURL *)url completion:(void (^)(BOOL success))completion;

- (void)getAccounts:(void (^)(NSArray<DWUpholdAccountObject *> *_Nullable accounts))completion;
- (void)getCards:(void (^)(DWUpholdCardObject *_Nullable dashCard, NSArray<DWUpholdCardObject *> *fiatCards))completion;

- (DWUpholdCancellationToken)createTransactionForDashCard:(DWUpholdCardObject *)card
                                                   amount:(NSString *)amount
                                                  address:(NSString *)address
                                                 otpToken:(nullable NSString *)otpToken
                                               completion:(void (^)(DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired))completion;
- (DWUpholdCancellationToken)createBuyTransactionForDashCard:(DWUpholdCardObject *)card
                                                     account:(DWUpholdAccountObject *)account
                                                      amount:(NSString *)amount
                                                securityCode:(NSString *)securityCode
                                                    otpToken:(nullable NSString *)otpToken
                                                  completion:(void (^)(DWUpholdTransactionObject *_Nullable transaction, BOOL otpRequired))completion;
- (void)commitTransaction:(DWUpholdTransactionObject *)transaction
                     card:(DWUpholdCardObject *)card
                 otpToken:(nullable NSString *)otpToken
               completion:(void (^)(BOOL success, BOOL otpRequired))completion;
- (void)cancelTransaction:(DWUpholdTransactionObject *)transaction
                     card:(DWUpholdCardObject *)card;

- (nullable NSURL *)buyDashURLForCard:(DWUpholdCardObject *)card;
- (nullable NSURL *)transactionURLForTransaction:(DWUpholdTransactionObject *)transaction;

- (void)updateLastAccessDate;
- (void)logOut;

@end

NS_ASSUME_NONNULL_END
