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


@implementation DWDashPayModel

- (void)createUsername:(NSString *)username {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *blockchainIdentity = [wallet createBlockchainIdentityOfType:DSBlockchainIdentityType_User
                                                                          forUsername:username
                                                                 usingDerivationIndex:0];
    // clang-format off
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
                        DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
                        [chainManager.transactionManager publishTransaction:fundingTransaction
                                                                 completion:^(NSError *_Nullable error) {
                            if (error) {
                                // TODO: propagate error
                                DSDLog(@"Error: %@", error.localizedDescription);
                            }
                            else {
                                [blockchainIdentity registerInWalletForRegistrationFundingTransaction:fundingTransaction];

                                // TODO: registration completed
                            }
                        }];
                    }
                    else {
                        DSDLog(@"DWDashPayModel: Create username transaction was not signed.");
                    }
                }];
            }];
        }
        else {
            // TODO: propagate error
            DSDLog(@"DWDashPayModel: Unable to register blockchain user.");
        }
    }];
    // clang-format on
}

@end
