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

#import "DWDPRegistrationStatus.h"
#import "DWDashPayConstants.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWNotificationsData.h"
#import "DWNotificationsProvider.h"
#import "dashwallet-Swift.h"
#import <DashSync/DSLogger.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWDashPayRegistrationStatusUpdatedNotification = @"DWDashPayRegistrationStatusUpdatedNotification";
NSNotificationName const DWDashPaySentContactRequestToInviter = @"kDWDashPaySentContactRequestToInviter";

@interface DWDashPayModel ()

@property (nullable, nonatomic, strong) DWDPRegistrationStatus *registrationStatus;
@property (nullable, nonatomic, strong) NSError *lastRegistrationError;
@property (nonatomic, assign) BOOL isInvitationNotificationAllowed;
@property (nullable, nonatomic, strong) NSURL *invitation;
@end

NS_ASSUME_NONNULL_END

@implementation DWDashPayModel

@synthesize userProfile = _userProfile;

- (instancetype)init {
    self = [super init];
    if (self) {
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        DSIdentity *identity = wallet.defaultIdentity;
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

        _userProfile = [[DWCurrentUserProfileModel alloc] init];

        if (identity) {
            if (username == nil) {
                [DWGlobalOptions sharedInstance].dashpayUsername = identity.currentDashpayUsername;
                username = identity.currentDashpayUsername;
            }

            // username can be nil at this point
            [self updateRegistrationStatusForIdentity:identity username:username];
        }

        DSLogPrivate(@"DWDP: Current username: %@", [DWGlobalOptions sharedInstance].dashpayUsername);

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
    if (MOCK_DASHPAY) {
        return [DWGlobalOptions sharedInstance].dashpayUsername;
    }

    DSIdentity *identity = [DWEnvironment sharedInstance].currentWallet.defaultIdentity;
    return identity.currentDashpayUsername ?: [DWGlobalOptions sharedInstance].dashpayUsername;
}

- (DSIdentity *)identity {
    if (MOCK_DASHPAY) {
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

        if (username != nil) {
            return [[DWEnvironment sharedInstance].currentWallet createIdentityForUsername:username];
        }
    }

    return [DWEnvironment sharedInstance].currentWallet.defaultIdentity;
}

- (BOOL)registrationCompleted {
    return [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted;
}

- (NSUInteger)unreadNotificationsCount {
    if (self.isInvitationNotificationAllowed &&
        [DWGlobalOptions sharedInstance].shouldShowInvitationsBadge) {
        return 1;
    }

    return [DWNotificationsProvider sharedInstance].data.unreadItems.count;
}

- (BOOL)shouldPresentRegistrationPaymentConfirmation {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *identity = wallet.defaultIdentity;
    return identity == nil;
}

- (void)createUsername:(NSString *)username invitation:(nullable NSURL *)invitationURL {
    self.invitation = invitationURL;
    self.lastRegistrationError = nil;
    [DWGlobalOptions sharedInstance].dashpayUsername = username;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;

    if (invitationURL != nil) {
        DSInvitation *invitation = [[DSInvitation alloc] initWithInvitationLink:invitationURL.absoluteString inWallet:wallet];

        __weak typeof(self) weakSelf = self;
        [invitation
            acceptInvitationUsingWalletIndex:0
            setDashpayUsername:username
            authenticationPrompt:NSLocalizedString(@"Would you like to accept the invitation?", nil)
            identityRegistrationSteps:[self invitationSteps]
            stepCompletion:^(DSIdentityRegistrationStep stepCompleted) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                [strongSelf handleSteps:stepCompleted errors:@[]];
            }
            completion:^(DSIdentityRegistrationStep stepsCompleted, NSArray<NSError *> *errors) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                NSLog(@">>> completed invitation %@ - %@", @(stepsCompleted), errors);

                [strongSelf handleSteps:stepsCompleted errors:errors];

                if (!errors) {
                    [strongSelf sendContactRequestToInviterUsingInvitationURL:invitationURL];
                }
            }
            completionQueue:dispatch_get_main_queue()];

        return;
    }

    DSIdentity *identity = wallet.defaultIdentity;

    if (identity) {
        [self createFundingPrivateKeyForIdentity:identity isNew:NO];
    }
    else {
        identity = [wallet createIdentityForUsername:username];

        // TODO: fix prompt
        [identity generateIdentityExtendedPublicKeysWithPrompt:NSLocalizedString(@"Generate extended public keys?", nil)
                                                    completion:^(BOOL registered) {
                                                        if (registered)
                                                            [self createFundingPrivateKeyForIdentity:identity isNew:YES];
                                                        else
                                                            [self cancel];
                                                    }];
    }
}

- (void)sendContactRequestToInviterUsingInvitationURL:(NSURL *)invitationURL {
    NSURLComponents *components = [NSURLComponents componentsWithURL:invitationURL resolvingAgainstBaseURL:NO];
    NSString *username;

    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"du"]) {
            username = item.value;
            break;
        }
    }

    if (!username) {
        return;
    }

    DSIdentitiesManager *manager = [DWEnvironment sharedInstance].currentChainManager.identitiesManager;
    __weak typeof(self) weakSelf = self;
    [manager searchIdentityByDashpayUsername:username
                              withCompletion:^(BOOL success, DSIdentity *_Nullable identity, NSError *_Nullable error) {
                                  if (success) {
                                      DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
                                      DSIdentity *myIdentity = wallet.defaultIdentity;
                                      [myIdentity sendNewFriendRequestToIdentity:identity
                                                                      completion:^(BOOL success, NSArray<NSError *> *_Nullable errors) {
                                                                          DSLog(@"Friend request sent %i", success);
                                                                      }];
                                  }
                              }];
}

- (void)sendContactRequestToIdentity:(DSIdentity *)identity {

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *myIdentity = wallet.defaultIdentity;
    [myIdentity sendNewFriendRequestToIdentity:identity
                                    completion:^(BOOL success, NSArray<NSError *> *_Nullable errors){
                                    }];
}

- (BOOL)canRetry {
    return self.username != nil;
}

- (void)retry {
    [self createUsername:self.username invitation:self.invitation];
}

- (void)completeRegistration {
    [DWGlobalOptions sharedInstance].shouldShowInvitationsBadge = YES;
    [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted = YES;

    if (!MOCK_DASHPAY) {
        [DWGlobalOptions sharedInstance].dashpayUsername = nil;
    }

    NSAssert(self.username != nil, @"Default DSIdentity has an empty username");
    self.registrationStatus = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

- (void)updateUsernameStatus {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *identity = wallet.defaultIdentity;

    NSString *key = DW_KEYPATH(self, username);
    [self willChangeValueForKey:key];
    if (identity) {
        NSString *username = identity.currentDashpayUsername;
        DWGlobalOptions *options = [DWGlobalOptions sharedInstance];
        if (options.dashpayUsername == nil && username != nil) {
            options.dashpayUsername = username;
            [self updateRegistrationStatusForIdentity:identity
                                             username:username];
        }
    }
    [self didChangeValueForKey:key];
}

- (void)setHasEnoughBalanceForInvitationNotification:(BOOL)value {
    self.isInvitationNotificationAllowed = ([DWGlobalOptions sharedInstance].dpInvitationFlowEnabled && value);
}

- (void)verifyDeeplink:(NSURL *)url
            completion:(void (^)(DSTransaction *_Nullable assetLockTx,
                                 NSString *_Nullable errorTitle,
                                 NSString *_Nullable errorMessage))completion {
    if (MOCK_DASHPAY) {
        DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
        DSTransaction *fakeLockTx = [account recentTransactions][0];
        completion(fakeLockTx, nil, nil);
        return;
    }

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    [DSInvitation verifyInvitationLink:url.absoluteString
                               onChain:chain
                            completion:^(Result_ok_dashcore_blockdata_transaction_Transaction_err_dash_spv_platform_error_Error *result) {
                                NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
                                NSString *username = @"<unknown user>";
                                for (NSURLQueryItem *item in components.queryItems) {
                                    if ([item.name isEqualToString:@"du"]) {
                                        username = item.value;
                                        break;
                                    }
                                }
                                BOOL success = result->ok;
                                Result_ok_dashcore_blockdata_transaction_Transaction_err_dash_spv_platform_error_Error_destroy(result);
                                if (success) {
                                    // TODO MOCK_DASHPAY: return the assetLockTx in the callback
                                    completion(nil, nil, nil);
                                    //        } else if (spent) {
                                    //            completion(NO, NSLocalizedString(@"Invitation already claimed", nil), DSLocalizedFormat(@"Your invitation from %@ has been already claimed", nil, username));
                                }
                                else {
                                    completion(nil, NSLocalizedString(@"Invalid Inviation", nil), DSLocalizedFormat(@"Your invitation from %@ is not valid", nil, username));
                                }
                            }
                       completionQueue:dispatch_get_main_queue()];
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

- (void)createFundingPrivateKeyForIdentity:(DSIdentity *)identity isNew:(BOOL)isNew {
    [identity createFundingPrivateKeyWithPrompt:NSLocalizedString(@"Register?", nil)
                                     completion:^(BOOL success, BOOL cancelled) {
                                         if (success) {
                                             if (isNew) {
                                                 [self registerIdentity:identity];
                                             }
                                             else {
                                                 [self continueRegistering:identity];
                                             }
                                         }
                                         else {
                                             [self cancel];
                                         }
                                     }];
}

- (void)registerIdentity:(DSIdentity *)identity {
    if (MOCK_DASHPAY) {
        [self handleSteps:DSIdentityRegistrationStep_All errors:@[]];
        return;
    }

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    __weak typeof(self) weakSelf = self;
    [identity registerOnNetwork:[self steps]
        withFundingAccount:account
        forTopupAmount:DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        pinPrompt:@"Would you like to create this user?"
        stepCompletion:^(DSIdentityRegistrationStep stepCompleted) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf handleSteps:stepCompleted errors:@[]];
        }
        completion:^(DSIdentityRegistrationStep stepsCompleted, NSArray<NSError *> *errors) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            NSLog(@">>> completed %@ - %@", @(stepsCompleted), errors);
            [strongSelf handleSteps:stepsCompleted errors:errors];
        }];
}

- (void)continueRegistering:(DSIdentity *)identity {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    __weak typeof(self) weakSelf = self;
    [identity continueRegisteringOnNetwork:[self steps]
        withFundingAccount:account
        forTopupAmount:DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        pinPrompt:@"Would you like to create this user?"
        stepCompletion:^(DSIdentityRegistrationStep stepCompleted) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf handleSteps:stepCompleted errors:@[]];
        }
        completion:^(DSIdentityRegistrationStep stepsCompleted, NSArray<NSError *> *errors) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            NSLog(@">>> completed %@ - %@", @(stepsCompleted), errors);
            [strongSelf handleSteps:stepsCompleted errors:errors];
        }];
}

- (DSIdentityRegistrationStep)steps {
    return DSIdentityRegistrationStep_RegistrationStepsWithUsername;
}

- (DSIdentityRegistrationStep)invitationSteps {
    return (DSIdentityRegistrationStep_LocalInWalletPersistence |
            DSIdentityRegistrationStep_Identity |
            DSIdentityRegistrationStep_Username);
}

- (void)handleSteps:(DSIdentityRegistrationStep)stepsCompleted errors:(NSArray<NSError *> *)errors {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    NSLog(@">>> %@", @(stepsCompleted));

    if (stepsCompleted == DSIdentityRegistrationStep_Cancelled) {
        [self cancel];
        return;
    }

    if (errors) {
        self.lastRegistrationError = errors.lastObject;
    }

    const BOOL failed = [errors count];

    if (failed && self.identity.isFromIncomingInvitation) {
        [self cancel];
        [self.identity unregisterLocally];
        return;
    }

    DWDPRegistrationState state = [self stateForCompletedSteps:stepsCompleted];
    self.registrationStatus = [[DWDPRegistrationStatus alloc] initWithState:state failed:failed username:self.username];

    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

- (void)cancel {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [DWGlobalOptions sharedInstance].dashpayUsername = nil;
    self.lastRegistrationError = nil;
    self.registrationStatus = nil;

    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

- (void)updateRegistrationStatusForIdentity:(DSIdentity *)identity
                                   username:(NSString *)username {
    if (![DWGlobalOptions sharedInstance].dashpayRegistrationCompleted) {
        DWDPRegistrationState state = [self stateForCompletedSteps:identity.stepsCompleted];
        const BOOL isDone = state == DWDPRegistrationState_Done;
        _registrationStatus = [[DWDPRegistrationStatus alloc] initWithState:state failed:!isDone username:username];

        if (isDone) {
            [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted = YES;
            [DWGlobalOptions sharedInstance].dashpayUsername = nil;
            // NSAssert(self.username != nil, @"Default DSIdentity has an empty username");

            [self.userProfile update];
        }
    }
}

- (DWDPRegistrationState)stateForCompletedSteps:(DSIdentityRegistrationStep)stepsCompleted {
    DWDPRegistrationState state;
    if (stepsCompleted < DSIdentityRegistrationStep_L1Steps) {
        return DWDPRegistrationState_ProcessingPayment;
    }
    else if (stepsCompleted < DSIdentityRegistrationStep_Identity) {
        return DWDPRegistrationState_CreatingID;
    }
    else if (stepsCompleted < DSIdentityRegistrationStep_Username) {
        return DWDPRegistrationState_RegistrationUsername;
    }
    else {
        return DWDPRegistrationState_Done;
    }
}

@end
