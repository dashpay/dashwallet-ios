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

#import <Foundation/Foundation.h>

#import "DWHomeProtocol.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@protocol DWRootProtocol <NSObject>

@property (readonly, nonatomic, assign) BOOL hasAWallet;

/**
 The tri-state behind `hasAWallet`, read once per decision. `Unknown` while
 wallet presence cannot be read from the keychain (device locked during a
 background launch): `hasAWallet` is NO then, but it must not be acted on —
 the launch decision waits until protected data is available.
 */
@property (readonly, nonatomic, assign) DWWalletPresence walletPresence;

@property (readonly, nonatomic, strong) id<DWHomeProtocol> homeModel;

@property (nullable, nonatomic, copy) void (^currentNetworkDidChangeBlock)(void);

/**
 NO if running Dashwallet is not allowed on this device for security reasons
 */
@property (readonly, nonatomic, assign) BOOL walletOperationAllowed;

- (void)applicationDidEnterBackground;
- (void)applicationWillResignActiveNotification;
- (BOOL)shouldShowLockScreen;

- (void)setupDidFinish;

- (void)wipeWallet;

@end

NS_ASSUME_NONNULL_END
