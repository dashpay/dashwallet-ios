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

#import "DWDashPayModel.h"

#import "DWCurrentUserProfileModel.h"
#import "DWDPRegistrationStatus.h"
#import "DWDashPayConstants.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWNotificationsData.h"
#import "DWNotificationsProvider.h"
#import <DashSync/DSLogger.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWDashPayRegistrationStatusUpdatedNotification = @"DWDashPayRegistrationStatusUpdatedNotification";

@interface DWDashPayModel ()

@property (nullable, nonatomic, strong) DWDPRegistrationStatus *registrationStatus;
@property (nullable, nonatomic, strong) NSError *lastRegistrationError;

@end

NS_ASSUME_NONNULL_END

@implementation DWDashPayModel

@synthesize userProfile = _userProfile;

- (instancetype)init {
    self = [super init];
    if (self) {
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;
        NSString *username = [DWGlobalOptions sharedInstance].persistedDashPayUsername;

        _userProfile = [[DWCurrentUserProfileModel alloc] init];

        if (blockchainIdentity) {
            if (username == nil) {
                [DWGlobalOptions sharedInstance].persistedDashPayUsername = blockchainIdentity.currentDashpayUsername;
                username = blockchainIdentity.currentDashpayUsername;
            }

            // username can be nil at this point
            [self updateRegistrationStatusForBlockchainIdentity:blockchainIdentity username:username];
        }

        DSLogPrivate(@"DWDP: Current username: %@", [DWGlobalOptions sharedInstance].persistedDashPayUsername);

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(notificationsWillUpdate)
                                   name:DWNotificationsProviderWillUpdateNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(notificationsDidUpdate)
                                   name:DWNotificationsProviderDidUpdateNotification
                                 object:nil];
    }
    return self;
}

- (NSString *)username {
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    return blockchainIdentity.currentDashpayUsername ?: [DWGlobalOptions sharedInstance].persistedDashPayUsername;
}

- (DSBlockchainIdentity *)blockchainIdentity {
    return [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
}

- (BOOL)registrationCompleted {
    return [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted;
}

- (NSUInteger)unreadNotificationsCount {
    if ([DWGlobalOptions sharedInstance].shouldShowInvitationsBadge) {
        return 1;
    }
    return [DWNotificationsProvider sharedInstance].data.unreadItems.count;
}

- (BOOL)shouldPresentRegistrationPaymentConfirmation {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;
    return blockchainIdentity == nil;
}

- (void)createUsername:(NSString *)username {
    self.lastRegistrationError = nil;
    [DWGlobalOptions sharedInstance].persistedDashPayUsername = username;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;

    if (blockchainIdentity) {
        [self createFundingPrivateKeyForBlockchainIdentity:blockchainIdentity isNew:NO];
    }
    else {
        blockchainIdentity = [wallet createBlockchainIdentityForUsername:username];

        // TODO: fix prompt
        [blockchainIdentity
            generateBlockchainIdentityExtendedPublicKeysWithPrompt:NSLocalizedString(@"Generate extended public keys?", nil)
                                                        completion:^(BOOL registered) {
                                                            if (registered) {
                                                                [self createFundingPrivateKeyForBlockchainIdentity:blockchainIdentity
                                                                                                             isNew:YES];
                                                            }
                                                            else {
                                                                [self cancel];
                                                            }
                                                        }];
    }
}

- (BOOL)canRetry {
    return self.username != nil;
}

- (void)retry {
    [self createUsername:self.username];
}

- (void)completeRegistration {
    [DWGlobalOptions sharedInstance].shouldShowInvitationsBadge = YES;
    [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted = YES;
    [DWGlobalOptions sharedInstance].persistedDashPayUsername = nil;
    NSAssert(self.username != nil, @"Default DSBlockchainIdentity has an empty username");
    self.registrationStatus = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

- (void)updateUsernameStatus {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;

    NSString *key = DW_KEYPATH(self, username);
    [self willChangeValueForKey:key];
    if (blockchainIdentity) {
        NSString *username = blockchainIdentity.currentDashpayUsername;
        DWGlobalOptions *options = [DWGlobalOptions sharedInstance];
        if (options.persistedDashPayUsername == nil && username != nil) {
            options.persistedDashPayUsername = username;
            [self updateRegistrationStatusForBlockchainIdentity:blockchainIdentity
                                                       username:username];
        }
    }
    [self didChangeValueForKey:key];
}

#pragma mark - Notifications

- (void)notificationsWillUpdate {
    NSString *key = DW_KEYPATH(self, unreadNotificationsCount);
    [self willChangeValueForKey:key];
}

- (void)notificationsDidUpdate {
    NSString *key = DW_KEYPATH(self, unreadNotificationsCount);
    [self didChangeValueForKey:key];
}

#pragma mark - Private

- (void)createFundingPrivateKeyForBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity isNew:(BOOL)isNew {
    [blockchainIdentity createFundingPrivateKeyWithPrompt:NSLocalizedString(@"Register?", nil)
                                               completion:^(BOOL success, BOOL cancelled) {
                                                   if (success) {
                                                       if (isNew) {
                                                           [self registerIdentity:blockchainIdentity];
                                                       }
                                                       else {
                                                           [self continueRegistering:blockchainIdentity];
                                                       }
                                                   }
                                                   else {
                                                       [self cancel];
                                                   }
                                               }];
}

- (void)registerIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    __weak typeof(self) weakSelf = self;
    [blockchainIdentity registerOnNetwork:[self steps]
        withFundingAccount:account
        forTopupAmount:DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        stepCompletion:^(DSBlockchainIdentityRegistrationStep stepCompleted) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf handleSteps:stepCompleted error:nil];
        }
        completion:^(DSBlockchainIdentityRegistrationStep stepsCompleted, NSError *_Nonnull error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            NSLog(@">>> completed %@ - %@", @(stepsCompleted), error);
            [strongSelf handleSteps:stepsCompleted error:error];
        }];
}

- (void)continueRegistering:(DSBlockchainIdentity *)blockchainIdentity {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    __weak typeof(self) weakSelf = self;
    [blockchainIdentity continueRegisteringOnNetwork:[self steps]
        withFundingAccount:account
        forTopupAmount:DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        stepCompletion:^(DSBlockchainIdentityRegistrationStep stepCompleted) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf handleSteps:stepCompleted error:nil];
        }
        completion:^(DSBlockchainIdentityRegistrationStep stepsCompleted, NSError *_Nonnull error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            NSLog(@">>> completed %@ - %@", @(stepsCompleted), error);
            [strongSelf handleSteps:stepsCompleted error:error];
        }];
}

- (DSBlockchainIdentityRegistrationStep)steps {
    return DSBlockchainIdentityRegistrationStep_RegistrationStepsWithUsername;
}

- (void)handleSteps:(DSBlockchainIdentityRegistrationStep)stepsCompleted error:(nullable NSError *)error {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    NSLog(@">>> %@", @(stepsCompleted));

    if (stepsCompleted == DSBlockchainIdentityRegistrationStep_Cancelled) {
        [self cancel];
        return;
    }

    if (error) {
        self.lastRegistrationError = error;
    }

    DWDPRegistrationState state = [self stateForCompletedSteps:stepsCompleted];

    const BOOL failed = error != nil;
    self.registrationStatus = [[DWDPRegistrationStatus alloc] initWithState:state failed:failed username:self.username];

    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

- (void)cancel {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [DWGlobalOptions sharedInstance].persistedDashPayUsername = nil;
    self.lastRegistrationError = nil;
    self.registrationStatus = nil;

    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

- (void)updateRegistrationStatusForBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity
                                             username:(NSString *)username {
    if (![DWGlobalOptions sharedInstance].dashpayRegistrationCompleted) {
        DWDPRegistrationState state = [self stateForCompletedSteps:blockchainIdentity.stepsCompleted];
        const BOOL isDone = state == DWDPRegistrationState_Done;
        _registrationStatus = [[DWDPRegistrationStatus alloc] initWithState:state failed:!isDone username:username];

        if (isDone) {
            [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted = YES;
            [DWGlobalOptions sharedInstance].persistedDashPayUsername = nil;
            NSAssert(self.username != nil, @"Default DSBlockchainIdentity has an empty username");

            [self.userProfile update];
        }
    }
}

- (DWDPRegistrationState)stateForCompletedSteps:(DSBlockchainIdentityRegistrationStep)stepsCompleted {
    DWDPRegistrationState state;
    if (stepsCompleted < DSBlockchainIdentityRegistrationStep_L1Steps) {
        return DWDPRegistrationState_ProcessingPayment;
    }
    else if (stepsCompleted < DSBlockchainIdentityRegistrationStep_Identity) {
        return DWDPRegistrationState_CreatingID;
    }
    else if (stepsCompleted < DSBlockchainIdentityRegistrationStep_Username) {
        return DWDPRegistrationState_RegistrationUsername;
    }
    else {
        return DWDPRegistrationState_Done;
    }
}

@end
