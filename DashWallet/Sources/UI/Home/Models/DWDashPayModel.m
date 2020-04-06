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

#import "DWDashPayConstants.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain DWDashPayErrorDomain = @"org.dash.wallet.dashpay-error";

static NSError *ErrorForCode(DWDashPayErrorCode code) {
    NSString *localizedDescription = nil;
    switch (code) {
        case DWDashPayErrorCode_UnableToRegisterBU:
            localizedDescription = NSLocalizedString(@"Unable to register blockchain user.", nil);
            break;
        case DWDashPayErrorCode_CreateBUTxNotSigned:
            localizedDescription = NSLocalizedString(@"Create username transaction was not signed.", nil);
    }

    NSDictionary *userInfo = nil;
    if (localizedDescription) {
        userInfo = @{NSLocalizedDescriptionKey : localizedDescription};
    }

    return [NSError errorWithDomain:DWDashPayErrorDomain code:code userInfo:userInfo];
}

@interface DWDashPayModel ()

@property (nullable, nonatomic, copy) NSString *username;

@property (nonatomic, assign) DWDashPayModelRegistrationState registrationState;
@property (nullable, nonatomic, strong) NSError *lastRegistrationError;

@end

NS_ASSUME_NONNULL_END

@implementation DWDashPayModel

@synthesize stateUpdateHandler;

- (instancetype)init {
    self = [super init];
    if (self) {
        if ([DWGlobalOptions sharedInstance].dashpayUsernameRegistered) {
            self.registrationState = DWDashPayModelRegistrationState_Success;
        }

        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;
        self.username = blockchainIdentity.currentUsername;
    }
    return self;
}

- (void)createUsername:(NSString *)username {
    if (self.registrationState == DWDashPayModelRegistrationState_Initiated) {
        return;
    }
    self.registrationState = DWDashPayModelRegistrationState_Initiated;
    self.lastRegistrationError = nil;

    self.username = username;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    DSBlockchainIdentity *blockchainIdentity = wallet.defaultBlockchainIdentity;
    if (blockchainIdentity == nil) {
        blockchainIdentity = [wallet createBlockchainIdentityOfType:DSBlockchainIdentityType_User
                                                        forUsername:username];
    }

    // TODO: fix prompt
    [blockchainIdentity generateBlockchainIdentityExtendedPublicKeysWithPrompt:@"Generate extended public keys?"
                                                                    completion:^(BOOL registered) {
                                                                        if (!registered) {
                                                                            return;
                                                                        }

                                                                        [self registerIdentity:blockchainIdentity];
                                                                    }];
}

- (void)registerIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    DSBlockchainIdentityRegistrationStep steps = [self stepsForBlockchainIdentity:blockchainIdentity];

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    __weak typeof(self) weakSelf = self;
    [blockchainIdentity registerOnNetwork:steps
        withFundingAccount:account
        forTopupAmount:DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        stepCompletion:^(DSBlockchainIdentityRegistrationStep stepCompleted) {
            NSLog(@">>>> %@", @(stepCompleted));
        }
        completion:^(DSBlockchainIdentityRegistrationStep stepsCompleted, NSError *_Nonnull error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            if (error) {
                strongSelf.lastRegistrationError = error;
                strongSelf.registrationState = DWDashPayModelRegistrationState_Failure;
            }
            else {
                [DWGlobalOptions sharedInstance].dashpayUsernameRegistered = YES;
                strongSelf.registrationState = DWDashPayModelRegistrationState_Success;
            }

            if (strongSelf.stateUpdateHandler) {
                strongSelf.stateUpdateHandler(strongSelf);
            }
        }];
}

- (DSBlockchainIdentityRegistrationStep)stepsForBlockchainIdentity:(DSBlockchainIdentity *)identity {
    DSBlockchainIdentityRegistrationStatus registrationStatus = identity.registrationStatus;
    switch (registrationStatus) {
        case DSBlockchainIdentityRegistrationStatus_Unknown:
            return (DSBlockchainIdentityRegistrationStep_L1Steps |
                    DSBlockchainIdentityRegistrationStep_Identity |
                    DSBlockchainIdentityRegistrationStep_Username);
        case DSBlockchainIdentityRegistrationStatus_Registered: {
            NSString *username = identity.currentUsername;
            if (username) {
                DSBlockchainIdentityUsernameStatus usernameStatus = [identity statusOfUsername:username];
                switch (usernameStatus) {
                    case DSBlockchainIdentityUsernameStatus_NotPresent:
                    case DSBlockchainIdentityUsernameStatus_TakenOnNetwork:
                        return DSBlockchainIdentityRegistrationStep_Username;
                    case DSBlockchainIdentityUsernameStatus_Initial:
                    case DSBlockchainIdentityUsernameStatus_PreorderRegistrationPending:
                    case DSBlockchainIdentityUsernameStatus_Preordered:
                    case DSBlockchainIdentityUsernameStatus_RegistrationPending:
                    case DSBlockchainIdentityUsernameStatus_Confirmed:
                        // Registration already in progress or done
                        return DSBlockchainIdentityRegistrationStep_None;
                }
            }
            else {
                return DSBlockchainIdentityRegistrationStep_Username;
            }
        }
        case DSBlockchainIdentityRegistrationStatus_Registering:
            // Registration already in progress
            return DSBlockchainIdentityRegistrationStep_None;
        case DSBlockchainIdentityRegistrationStatus_NotRegistered:
            // Registration already in progress
            return DSBlockchainIdentityRegistrationStep_None;
    }
}

@end
