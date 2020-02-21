//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWURLRequestHandler.h"

#import <DashSync/DashSync.h>
#import <UIKit/UIKit.h>

#import "DWEnvironment.h"
#import "DWURLActions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWURLRequestHandler

+ (void)handleURLRequest:(DWURLRequestAction *)action {
    if (action.type == DWURLRequestActionType_MasterPublicKey) {
        [self handleMasterPublicKeyRequest:action];
    }
    else if (action.type == DWURLRequestActionType_Address) {
        [self handleAddressRequest:action];
    }
}

#pragma mark - Private

+ (void)handleMasterPublicKeyRequest:(DWURLRequestAction *)action {
    NSString *prompt = [NSString stringWithFormat:NSLocalizedString(@"Application %@ would like to receive your Master Public Key.  This can be used to keep track of your wallet, this can not be used to move your Dash.", nil), action.sender];

    [[DSAuthenticationManager sharedInstance]
              authenticateWithPrompt:prompt
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticatedOrSuccess, BOOL usedBiometrics, BOOL cancelled) {
                              if (authenticatedOrSuccess) {
                                  DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

                                  NSString *masterPublicKeySerialized = [account.bip44DerivationPath serializedExtendedPublicKey];
                                  NSParameterAssert(masterPublicKeySerialized);
                                  if (!masterPublicKeySerialized) {
                                      return;
                                  }

                                  NSString *masterPublicKeyNoPurposeSerialized = [account.bip32DerivationPath serializedExtendedPublicKey];
                                  NSParameterAssert(masterPublicKeyNoPurposeSerialized);
                                  if (!masterPublicKeyNoPurposeSerialized) {
                                      return;
                                  }

                                  NSString *urlString =
                                      [NSString stringWithFormat:
                                                    @"%@://callback=%@&masterPublicKeyBIP32=%@&masterPublicKeyBIP44=%@&account=%@&source=dashwallet",
                                                    action.sender,
                                                    action.request,
                                                    masterPublicKeyNoPurposeSerialized,
                                                    masterPublicKeySerialized,
                                                    @"0"];
                                  NSURL *url = [NSURL URLWithString:urlString];
                                  NSParameterAssert(url);
                                  if (!url) {
                                      return;
                                  }

                                  [[UIApplication sharedApplication] openURL:url
                                                                     options:@{}
                                                           completionHandler:^(BOOL success){
                                                           }];
                              }
                          }];
}

+ (void)handleAddressRequest:(DWURLRequestAction *)action {
    NSString *prompt = [NSString stringWithFormat:NSLocalizedString(@"Application %@ is requesting an address so it can pay you.  Would you like to authorize this?", nil), action.sender];

    [[DSAuthenticationManager sharedInstance]
              authenticateWithPrompt:prompt
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticatedOrSuccess, BOOL usedBiometrics, BOOL cancelled) {
                              if (authenticatedOrSuccess) {
                                  DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

                                  NSString *urlString =
                                      [NSString stringWithFormat:
                                                    @"%@://callback=%@&address=%@&source=dashwallet",
                                                    action.sender,
                                                    action.request,
                                                    account.receiveAddress];

                                  NSURL *url = [NSURL URLWithString:urlString];
                                  NSParameterAssert(url);
                                  if (!url) {
                                      return;
                                  }

                                  [[UIApplication sharedApplication] openURL:url
                                                                     options:@{}
                                                           completionHandler:^(BOOL success){
                                                           }];
                              }
                          }];
}

@end

NS_ASSUME_NONNULL_END
