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
#import "DWLogger.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWDashPayRegistrationStatusUpdatedNotification = @"DWDashPayRegistrationStatusUpdatedNotification";

@interface DWDashPayModel ()

@property (nullable, nonatomic, strong) DWDPRegistrationStatus *registrationStatus;
@property (nullable, nonatomic, strong) NSError *lastRegistrationError;
@property (nonatomic, assign) BOOL isInvitationNotificationAllowed;
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

        DWLogPrivate(@"DWDP: Current username: %@", [DWGlobalOptions sharedInstance].dashpayUsername);

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        // Row #18: the badge count now derives from the SwiftDashSDK
        // contacts service; its snapshot-change notification replaces
        // the retired DWNotificationsProvider will/did pair.
        [notificationCenter addObserver:self
                               selector:@selector(contactsSnapshotDidChange)
                                   name:@"DWSwiftDashSDKContactsDidChangeNotification"
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(bridgeRegistrationStateChanged:)
                                   name:DWIdentityRegistrationBridge.stateChangedNotification
                                 object:nil];
    }
    return self;
}

- (NSString *)username {
    if (MOCK_DASHPAY) {
        return [DWGlobalOptions sharedInstance].dashpayUsername;
    }

    // SwiftDashSDK-sourced username via `DWCurrentUserIdentityInfo`.
    // The helper itself falls back to `DWGlobalOptions.dashpayUsername`
    // when the DPNS cache is empty (immediately post-register), so
    // this getter terminates on the global as a last resort. The
    // legacy `defaultBlockchainIdentity.currentDashpayUsername` tail
    // was dropped — both registration paths (SDK and the deprecated
    // DashSync one) mirror into `DWGlobalOptions.dashpayUsername`, so
    // it never fired in practice.
    return DWCurrentUserIdentityInfo.shared.username ?: [DWGlobalOptions sharedInstance].dashpayUsername;
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

    // Row #18: SwiftDashSDK contacts service (incoming requests +
    // established-contact events newer than the last-viewed marker).
    return DWContactsNotificationsBridge.unreadCount;
}

- (BOOL)shouldPresentRegistrationPaymentConfirmation {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;
    return blockchainIdentity == nil;
}

- (void)createUsername:(NSString *)username {
    // Invitation-funded registration no longer goes through this
    // model — the SwiftUI form drives
    // `DWIdentityRegistrationCoordinator.startClaimInvitation` directly
    // (see CreateUsernameViewModel).
    self.lastRegistrationError = nil;
    [DWGlobalOptions sharedInstance].dashpayUsername = username;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;

    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;

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

#pragma mark - Notifications

- (void)contactsSnapshotDidChange {
    // The service posts after its snapshot is already rebuilt, so the
    // will/did pair brackets a value that has, in fact, changed.
    NSString *key = DW_KEYPATH(self, unreadNotificationsCount);
    [self willChangeValueForKey:key];
    [self didChangeValueForKey:key];
}

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
        // Contested submissions complete with the username deliberately
        // unmirrored (masternode voting pending) — self.username is nil by
        // construction until checkPendingContestResolution finalizes the win.
        BOOL contestedPending = [DWContestedNameStatusService.shared isPendingLabel:bridgeUsername];
        NSAssert(contestedPending || self.username != nil, @"SDK identity has an empty username");
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
