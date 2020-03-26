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

- (void)createUsername:(NSString *)username {
    if (self.registrationState == DWDashPayModelRegistrationState_Initiated) {
        return;
    }
    self.registrationState = DWDashPayModelRegistrationState_Initiated;
    self.lastRegistrationError = nil;

    self.username = username;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    DSBlockchainIdentity *blockchainIdentity = [wallet createBlockchainIdentityOfType:DSBlockchainIdentityType_User
                                                                          forUsername:username];
    DSBlockchainIdentityRegistrationStep steps = DSBlockchainIdentityRegistrationStep_L1Steps | DSBlockchainIdentityRegistrationStep_Identity | DSBlockchainIdentityRegistrationStep_Username;

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
                strongSelf.registrationState = DWDashPayModelRegistrationState_Success;
            }
        }];
}

@end
