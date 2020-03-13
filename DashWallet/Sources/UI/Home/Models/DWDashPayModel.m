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

- (void)createUsername:(NSString *)username
     partialCompletion:(void (^)(NSError *_Nullable))partialCompletion {
    if (self.registrationState == DWDashPayModelRegistrationState_Initiated) {
        return;
    }
    self.registrationState = DWDashPayModelRegistrationState_Initiated;
    self.lastRegistrationError = nil;

    self.username = username;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *blockchainIdentity = [wallet createBlockchainIdentityOfType:DSBlockchainIdentityType_User
                                                                          forUsername:username
                                                                 usingDerivationIndex:0];
    // clang-format off
    __weak typeof(self) weakSelf = self;
    [blockchainIdentity generateBlockchainIdentityExtendedPublicKeys:^(BOOL exists) {
        if (exists) {
            DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
            NSString *creditFundingRegistrationAddress = [blockchainIdentity registrationFundingAddress];
            [blockchainIdentity fundingTransactionForTopupAmount:DWDP_MIN_BALANCE_TO_CREATE_USERNAME
                                                       toAddress:creditFundingRegistrationAddress
                                                 fundedByAccount:account
                                                      completion:^(DSCreditFundingTransaction *_Nonnull fundingTransaction) {
                [account signTransaction:fundingTransaction
                              withPrompt:NSLocalizedString(@"Would you like to create this user?", nil)
                              completion:^(BOOL signedTransaction, BOOL cancelled) {
                    if (signedTransaction) {
                        if (partialCompletion) {
                            partialCompletion(nil);
                        }
                        
                        DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
                        [chainManager.transactionManager publishTransaction:fundingTransaction
                                                                 completion:^(NSError *_Nullable error) {
                            __strong typeof(weakSelf) strongSelf = weakSelf;
                            if (!strongSelf) {
                                return;
                            }

                            if (error) {
                                strongSelf.lastRegistrationError = error;
                                strongSelf.registrationState = DWDashPayModelRegistrationState_Failure;
                                DSDLog(@"[DWDashPayModel] Registration error: %@", error.localizedDescription);
                            }
                            else {
                                [blockchainIdentity registerInWalletForRegistrationFundingTransaction:fundingTransaction];
                                strongSelf.registrationState = DWDashPayModelRegistrationState_Success;
                                DSDLog(@"[DWDashPayModel] Registration succeeded");
                            }
                        }];
                    }
                    else {
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) {
                            return;
                        }

                        NSError *error = ErrorForCode(DWDashPayErrorCode_CreateBUTxNotSigned);
                        strongSelf.lastRegistrationError = error;
                        strongSelf.registrationState = DWDashPayModelRegistrationState_Failure;
                        
                        if (partialCompletion) {
                            partialCompletion(error);
                        }
                    }
                }];
            }];
        }
        else {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            NSError *error = ErrorForCode(DWDashPayErrorCode_UnableToRegisterBU);
            strongSelf.lastRegistrationError = error;
            strongSelf.registrationState = DWDashPayModelRegistrationState_Failure;
            
            if (partialCompletion) {
                partialCompletion(error);
            }
        }
    }];
    // clang-format on
}

@end
