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
        DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

        _userProfile = [[DWCurrentUserProfileModel alloc] init];

        if (blockchainIdentity) {
            if (username == nil) {
                [DWGlobalOptions sharedInstance].dashpayUsername = blockchainIdentity.currentDashpayUsername;
                username = blockchainIdentity.currentDashpayUsername;
            }

            // username can be nil at this point
            [self updateRegistrationStatusForBlockchainIdentity:blockchainIdentity username:username];
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
#if DASHPAY_SWIFT_SDK_REGISTRATION
        [notificationCenter addObserver:self
                               selector:@selector(bridgeRegistrationStateChanged:)
                                   name:DWIdentityRegistrationBridge.stateChangedNotification
                                 object:nil];
#endif
    }
    return self;
}

- (NSString *)username {
    if (MOCK_DASHPAY) {
        return [DWGlobalOptions sharedInstance].dashpayUsername;
    }

    // Row #17 proper: prefer the SwiftDashSDK-sourced username via
    // `DWCurrentUserIdentityInfo`. The helper itself falls back to
    // `DWGlobalOptions.dashpayUsername` when the DPNS cache is empty
    // (immediately post-register), and we also fall back to it here
    // for legacy DashSync-side identities whose DPNS data the SDK
    // doesn't know about.
    NSString *sdkUsername = DWCurrentUserIdentityInfo.shared.username;
    if (sdkUsername.length > 0) {
        return sdkUsername;
    }
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    return blockchainIdentity.currentDashpayUsername ?: [DWGlobalOptions sharedInstance].dashpayUsername;
}

- (DSBlockchainIdentity *)blockchainIdentity {
    if (MOCK_DASHPAY) {
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

        if (username != nil) {
            return [[DWEnvironment sharedInstance].currentWallet createBlockchainIdentityForUsername:username];
        }
    }

    return [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
}

- (BOOL)registrationCompleted {
    return [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted;
}

- (BOOL)hasIdentity {
    // Row #17 stage A — true for either DashSync-side identity OR
    // SwiftDashSDK-side identity. The legacy `blockchainIdentity`
    // getter returns nil for the SDK path (DashSync has no on-chain
    // footprint for PP-funded identities and no scanner-driven
    // reconstruction), so consumers that only need to know "does
    // this wallet have a DashPay identity?" should read this
    // property instead. Callers that need the `DSBlockchainIdentity`
    // object (Edit Profile, contacts) still read `blockchainIdentity`
    // and handle nil — row #17 proper migrates those.
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    if (blockchainIdentity != nil) {
        return YES;
    }
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
    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;
    return blockchainIdentity == nil;
}

- (void)createUsername:(NSString *)username invitation:(nullable NSURL *)invitationURL {
    self.invitation = invitationURL;
    self.lastRegistrationError = nil;
    [DWGlobalOptions sharedInstance].dashpayUsername = username;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;

    if (invitationURL != nil) {
        DSBlockchainInvitation *invitation = [[DSBlockchainInvitation alloc] initWithInvitationLink:invitationURL.absoluteString inWallet:wallet];

        __weak typeof(self) weakSelf = self;
        [invitation
            acceptInvitationUsingWalletIndex:0
            setDashpayUsername:username
            authenticationPrompt:NSLocalizedString(@"Would you like to accept the invitation?", nil)
            identityRegistrationSteps:[self invitationSteps]
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

                NSLog(@">>> completed invitation %@ - %@", @(stepsCompleted), error);

                [strongSelf handleSteps:stepsCompleted error:error];

                if (!error) {
                    [strongSelf sendContactRequestToInviterUsingInvitationURL:invitationURL];
                }
            }
            completionQueue:dispatch_get_main_queue()];

        return;
    }

    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;

#if DASHPAY_SWIFT_SDK_REGISTRATION
    if (blockchainIdentity == nil) {
        // New user — no existing DashSync identity. Route through
        // SwiftDashSDK. The bridge's state-change notification drives
        // `bridgeRegistrationStateChanged:` which rebuilds
        // `self.registrationStatus` and posts the canonical
        // `DWDashPayRegistrationStatusUpdatedNotification`.
        //
        // The completion is a safety net for early-exit failures that
        // never reach a terminal phase notification: SDK preconditions
        // (no wallet / no network / no model container) throw before
        // the controller is wired, and auth-cancel calls resetState()
        // which clears `bridge.currentUsername` so the observer
        // early-returns without updating model state. In those cases
        // we'd leave `dashpayUsername` (set above at line 131) cached
        // forever — surface the error here.
        __weak typeof(self) weakSelf = self;
        [DWIdentityRegistrationBridge.shared
            startCreateUsername:username
                     completion:^(NSString *_Nullable idHex, NSError *_Nullable error) {
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (strongSelf == nil || error == nil) {
                             return;
                         }
                         // If the notification path already surfaced a
                         // failed state, `registrationStatus` is non-nil
                         // and the UI is showing the right error. Only
                         // clean up when nothing surfaced — i.e. the
                         // coordinator threw before any phase change.
                         if (strongSelf.registrationStatus != nil) {
                             return;
                         }
                         [DWGlobalOptions sharedInstance].dashpayUsername = nil;
                         strongSelf.lastRegistrationError = error;
                         [[NSNotificationCenter defaultCenter]
                             postNotificationName:DWDashPayRegistrationStatusUpdatedNotification
                                           object:nil];
                     }];
        return;
    }
    // Existing-identity user: fall through to DashSync. SDK doesn't yet
    // have an "import existing identity" path (v2 follow-up).
#endif

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
                              withCompletion:^(BOOL success, DSBlockchainIdentity *_Nullable blockchainIdentity, NSError *_Nullable error) {
                                  if (success) {

                                      DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
                                      DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;

                                      [myBlockchainIdentity sendNewFriendRequestToBlockchainIdentity:blockchainIdentity
                                                                                          completion:^(BOOL success, NSArray<NSError *> *_Nullable errors) {
                                                                                              DSLog(@"Friend request sent %i", success);
                                                                                          }];
                                  }
                              }];
}

- (void)sendContactRequestToBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    [myBlockchainIdentity sendNewFriendRequestToBlockchainIdentity:blockchainIdentity
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
        if (options.dashpayUsername == nil && username != nil) {
            options.dashpayUsername = username;
            [self updateRegistrationStatusForBlockchainIdentity:blockchainIdentity
                                                       username:username];
        }
    }
    [self didChangeValueForKey:key];
}

- (void)setHasEnoughBalanceForInvitationNotification:(BOOL)value {
    self.isInvitationNotificationAllowed = ([DWGlobalOptions sharedInstance].dpInvitationFlowEnabled && value);
}

- (void)verifyDeeplink:(NSURL *)url
            completion:(void (^)(BOOL success,
                                 NSString *_Nullable errorTitle,
                                 NSString *_Nullable errorMessage))completion {
    if (MOCK_DASHPAY) {
        completion(YES, nil, nil);
        return;
    }

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    [DSBlockchainInvitation
        verifyInvitationLink:url.absoluteString
                     onChain:chain
                  completion:^(DSTransaction *_Nonnull transaction, bool spent, NSError *_Nonnull error) {
                      NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
                      NSString *username = @"<unknown user>";
                      for (NSURLQueryItem *item in components.queryItems) {
                          if ([item.name isEqualToString:@"du"]) {
                              username = item.value;
                              break;
                          }
                      }
                      if (transaction != nil) {
                          completion(YES, nil, nil);
                      }
                      else {
                          if (spent) {
                              completion(
                                  NO,
                                  NSLocalizedString(@"Invitation already claimed", nil),
                                  [NSString stringWithFormat:NSLocalizedString(@"Your invitation from %@ has been already claimed", nil), username]);
                          }
                          else {
                              completion(
                                  NO,
                                  NSLocalizedString(@"Invalid Inviation", nil),
                                  [NSString stringWithFormat:NSLocalizedString(@"Your invitation from %@ is not valid", nil), username]);
                          }
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

#if DASHPAY_SWIFT_SDK_REGISTRATION
- (void)bridgeRegistrationStateChanged:(NSNotification *)note {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");
    DWIdentityRegistrationBridge *bridge = DWIdentityRegistrationBridge.shared;
    NSString *bridgeUsername = bridge.currentUsername;
    if (bridgeUsername == nil) {
        // Bridge inactive — DashSync path is driving (or nothing in flight).
        return;
    }

    if (bridge.isCompleted) {
        // Mirror the success side-effects of `completeRegistration`
        // EXCEPT clearing `DWGlobalOptions.dashpayUsername` — that
        // method nils it on the assumption that
        // `wallet.defaultBlockchainIdentity.currentDashpayUsername`
        // becomes the source of truth, but the SDK path has no
        // DashSync identity, so nil'ing here would make `self.username`
        // permanently nil. Keep the cached username; row #17 will
        // eventually migrate the read sites off DashSync.
        [DWGlobalOptions sharedInstance].shouldShowInvitationsBadge = YES;
        NSAssert(self.username != nil, @"SDK identity has an empty username");
        self.registrationStatus = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
        return;
    }

    if (bridge.isFailed && bridge.lastErrorMessage != nil) {
        self.lastRegistrationError = [NSError errorWithDomain:@"DWDashPay"
                                                         code:-1
                                                     userInfo:@{NSLocalizedDescriptionKey : bridge.lastErrorMessage}];
    }

    self.registrationStatus = [[DWDPRegistrationStatus alloc] initWithState:bridge.currentState
                                                                     failed:bridge.isFailed
                                                                   username:bridgeUsername];
    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}
#endif

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
    if (MOCK_DASHPAY) {
        [self handleSteps:DSBlockchainIdentityRegistrationStep_All error:nil];
        return;
    }

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    __weak typeof(self) weakSelf = self;
    [blockchainIdentity registerOnNetwork:[self steps]
        withFundingAccount:account
        forTopupAmount:DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        pinPrompt:@"Would you like to create this user?"
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
        pinPrompt:@"Would you like to create this user?"
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

- (DSBlockchainIdentityRegistrationStep)invitationSteps {
    return (DSBlockchainIdentityRegistrationStep_LocalInWalletPersistence |
            DSBlockchainIdentityRegistrationStep_Identity |
            DSBlockchainIdentityRegistrationStep_Username);
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

    const BOOL failed = error != nil;

    if (failed && self.blockchainIdentity.isFromIncomingInvitation) {
        [self cancel];
        [self.blockchainIdentity unregisterLocally];
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

- (void)updateRegistrationStatusForBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity
                                             username:(NSString *)username {
    if (![DWGlobalOptions sharedInstance].dashpayRegistrationCompleted) {
        DWDPRegistrationState state = [self stateForCompletedSteps:blockchainIdentity.stepsCompleted];
        const BOOL isDone = state == DWDPRegistrationState_Done;
        _registrationStatus = [[DWDPRegistrationStatus alloc] initWithState:state failed:!isDone username:username];

        if (isDone) {
            [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted = YES;
            [DWGlobalOptions sharedInstance].dashpayUsername = nil;
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
