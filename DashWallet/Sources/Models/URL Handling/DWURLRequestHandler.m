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

#import <UIKit/UIKit.h>

#import "DWURLActions.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWURLRequestHandler

+ (void)handleURLRequest:(DWURLRequestAction *)action {
    if (action.type == DWURLRequestActionType_Address) {
        [self handleAddressRequest:action];
    }
}

#pragma mark - Private

+ (void)handleAddressRequest:(DWURLRequestAction *)action {
    NSString *prompt = [NSString stringWithFormat:NSLocalizedString(@"Application %@ is requesting an address so it can pay you.  Would you like to authorize this?", nil), action.sender];

    [[DWAuthenticationService shared]
              authenticateWithPrompt:prompt
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticatedOrSuccess, BOOL usedBiometrics, BOOL cancelled) {
                              if (authenticatedOrSuccess) {
                                  NSString *receiveAddress = [DWSwiftDashSDKReceiveAddressReader receiveAddress];

                                  NSString *urlString =
                                      [NSString stringWithFormat:
                                                    @"%@://callback=%@&address=%@&source=dashwallet",
                                                    action.sender,
                                                    action.request,
                                                    receiveAddress];

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
