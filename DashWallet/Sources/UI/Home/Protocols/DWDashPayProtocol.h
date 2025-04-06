//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const DWDashPayRegistrationStatusUpdatedNotification;
extern NSNotificationName const DWDashPaySentContactRequestToInviter;

@class DWDPRegistrationStatus;
@class DSIdentity;
@class DWCurrentUserProfileModel;

@protocol DWDashPayProtocol <NSObject>

@property (nullable, readonly, nonatomic, copy) NSString *username;
@property (nullable, readonly, nonatomic, strong) DSIdentity *identity;
@property (nullable, readonly, nonatomic, strong) DWDPRegistrationStatus *registrationStatus;
@property (readonly, nonatomic, strong) DWCurrentUserProfileModel *userProfile;
@property (nullable, readonly, nonatomic, strong) NSError *lastRegistrationError;
@property (readonly, nonatomic, assign) BOOL registrationCompleted;
@property (readonly, nonatomic, assign) NSUInteger unreadNotificationsCount;

- (BOOL)shouldPresentRegistrationPaymentConfirmation;
- (void)createUsername:(NSString *)username invitation:(nullable NSURL *)invitation;
- (BOOL)canRetry;
- (void)retry;
- (void)completeRegistration;
- (void)updateUsernameStatus;
- (void)setHasEnoughBalanceForInvitationNotification:(BOOL)value;

- (void)verifyDeeplink:(NSURL *)url
            completion:(void (^)(BOOL success,
                                 NSString *_Nullable errorTitle,
                                 NSString *_Nullable errorMessage))completion;

@end

NS_ASSUME_NONNULL_END
