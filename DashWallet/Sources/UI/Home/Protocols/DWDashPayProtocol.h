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
@class DSBlockchainIdentity;
@class DWCurrentUserProfileModel;

@protocol DWDashPayProtocol <NSObject>

@property (nullable, readonly, nonatomic, copy) NSString *username;
@property (nullable, readonly, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;
@property (nullable, readonly, nonatomic, strong) DWDPRegistrationStatus *registrationStatus;
@property (readonly, nonatomic, strong) DWCurrentUserProfileModel *userProfile;
@property (nullable, readonly, nonatomic, strong) NSError *lastRegistrationError;
@property (readonly, nonatomic, assign) BOOL registrationCompleted;
@property (readonly, nonatomic, assign) NSUInteger unreadNotificationsCount;
/// `YES` when the wallet has a DashPay identity from EITHER source —
/// DashSync's `defaultBlockchainIdentity` (Core-funded path,
/// reconstructed by DashSync's on-chain scanner) or
/// SwiftDashSDK's `PersistentIdentity` row (any funding path,
/// reflected by `DWGlobalOptions.dashpayRegistrationCompleted` after
/// `DWIdentityRegistrationCoordinator` finishes). Row #17 stage A:
/// the home-screen avatar visibility gate consults this so SDK-only
/// identities surface in the UI without waiting for the full read-
/// site migration. Callers that need the `DSBlockchainIdentity`
/// object itself (Edit Profile, contacts) still read
/// `blockchainIdentity` directly and get nil for the SDK path —
/// row #17 proper migrates those.
@property (readonly, nonatomic, assign) BOOL hasIdentity;

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
