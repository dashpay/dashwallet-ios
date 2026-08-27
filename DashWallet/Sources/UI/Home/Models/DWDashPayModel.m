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
#import "DWGlobalOptions.h"
#import "DWLogger.h"
#import "dashwallet-Swift.h"

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
        _userProfile = [[DWCurrentUserProfileModel alloc] init];

        DWLogPrivate(@"DWDP: Current username: %@", [DWGlobalOptions sharedInstance].dashpayUsername);

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        // The badge count derives from the SwiftDashSDK contacts snapshot.
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

- (BOOL)registrationCompleted {
    return [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted;
}

- (BOOL)hasIdentity {
    return DWCurrentUserIdentityInfo.shared.hasIdentity ||
           [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted;
}

- (NSUInteger)unreadNotificationsCount {
    // Incoming requests and established-contact events newer than the
    // last-viewed marker are counted by the app-owned contacts bridge.
    return DWContactsNotificationsBridge.unreadCount;
}

- (BOOL)shouldPresentRegistrationPaymentConfirmation {
    return !DWCurrentUserIdentityInfo.shared.hasIdentity;
}

- (void)createUsername:(NSString *)username {
    // The SwiftUI form normally drives the bridge directly. Keep this protocol
    // method as the SDK-owned compatibility entry point for any retained Obj-C
    // caller and retry UI.
    self.lastRegistrationError = nil;
    [DWGlobalOptions sharedInstance].dashpayUsername = username;

    __weak typeof(self) weakSelf = self;
    [DWIdentityRegistrationBridge.shared
        startCreateUsername:username
                 completion:^(NSString *_Nullable idHex, NSError *_Nullable error) {
                     __strong typeof(weakSelf) strongSelf = weakSelf;
                     if (strongSelf == nil || error == nil) {
                         return;
                     }
                     if (strongSelf.registrationStatus != nil) {
                         return;
                     }
                     [DWGlobalOptions sharedInstance].dashpayUsername = nil;
                     strongSelf.lastRegistrationError = error;
                     [[NSNotificationCenter defaultCenter]
                         postNotificationName:DWDashPayRegistrationStatusUpdatedNotification
                                       object:nil];
                 }];
}

- (BOOL)canRetry {
    return self.username != nil;
}

- (void)retry {
    [self createUsername:self.username];
}

- (void)completeRegistration {
    [DWGlobalOptions sharedInstance].dashpayRegistrationCompleted = YES;
    NSAssert(self.username != nil, @"SDK identity has an empty username");
    self.registrationStatus = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

- (void)updateUsernameStatus {
    NSString *key = DW_KEYPATH(self, username);
    [self willChangeValueForKey:key];
    [self didChangeValueForKey:key];
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
        // permanently nil. Keep the cached username as the app-owned
        // fallback used by the current identity snapshot.
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

@end
