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

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWDashPayRegistrationStatusUpdatedNotification = @"DWDashPayRegistrationStatusUpdatedNotification";

@interface DWDashPayModel ()

@property (nullable, nonatomic, copy) NSString *username;
@property (nullable, nonatomic, strong) DWDPRegistrationStatus *registrationStatus;
@property (nullable, nonatomic, strong) NSError *lastRegistrationError;

@end

NS_ASSUME_NONNULL_END

@implementation DWDashPayModel

- (instancetype)init {
    self = [super init];
    if (self) {
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;
        NSString *username = blockchainIdentity.currentUsername;

        if ([DWGlobalOptions sharedInstance].dashpayUsernameRegistered) {
            NSAssert(username != nil, @"Username is invalid");
            _registrationStatus = [[DWDPRegistrationStatus alloc] initWithState:DWDPRegistrationState_Done
                                                                         failed:NO
                                                                       username:username];
        }
        // else TODO: set registration status

        _username = username;
    }
    return self;
}

- (void)createUsername:(NSString *)username {
    self.lastRegistrationError = nil;
    self.username = username;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;

    if (blockchainIdentity) {
        blockchainIdentity.type = DSBlockchainIdentityType_User;
        [self createFundingPrivateKeyForBlockchainIdentity:blockchainIdentity isNew:NO];
    }
    else {
        blockchainIdentity = [wallet createBlockchainIdentityOfType:DSBlockchainIdentityType_User
                                                        forUsername:username];

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

- (void)retry {
    NSAssert(self.username != nil, @"Username is invalid.");

    [self createUsername:self.username];
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

            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf handleSteps:stepCompleted error:nil];
            });
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

            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf handleSteps:stepCompleted error:nil];
            });
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
    return (DSBlockchainIdentityRegistrationStep_L1Steps |
            DSBlockchainIdentityRegistrationStep_Identity |
            DSBlockchainIdentityRegistrationStep_Username);
}

- (void)handleSteps:(DSBlockchainIdentityRegistrationStep)stepsCompleted error:(nullable NSError *)error {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    NSLog(@">>> %@", @(stepsCompleted));

    if (error) {
        self.lastRegistrationError = error;
    }

    DWDPRegistrationState state;
    if (stepsCompleted < DSBlockchainIdentityRegistrationStep_L1Steps) {
        state = DWDPRegistrationState_ProcessingPayment;
    }
    else if (stepsCompleted < DSBlockchainIdentityRegistrationStep_Identity) {
        state = DWDPRegistrationState_CreatingID;
    }
    else if (stepsCompleted < DSBlockchainIdentityRegistrationStep_Username) {
        state = DWDPRegistrationState_RegistrationUsername;
    }
    else {
        state = DWDPRegistrationState_Done;
    }

    const BOOL failed = error != nil;
    self.registrationStatus = [[DWDPRegistrationStatus alloc] initWithState:state failed:failed username:self.username];

    if (state == DWDPRegistrationState_Done) {
        [DWGlobalOptions sharedInstance].dashpayUsernameRegistered = YES;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

- (void)cancel {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    self.username = nil;
    self.lastRegistrationError = nil;
    self.registrationStatus = nil;

    [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayRegistrationStatusUpdatedNotification object:nil];
}

@end
