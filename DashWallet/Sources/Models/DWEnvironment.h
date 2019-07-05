//
//  Created by Sam Westrich
//  Copyright © 2018-2019 Dash Core Group. All rights reserved.
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

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

#define WALLET_NEEDS_BACKUP_KEY @"WALLET_NEEDS_BACKUP"

NS_ASSUME_NONNULL_BEGIN

@interface DWEnvironment : NSObject

@property (nonatomic, strong, nonnull) DSChain *currentChain;
@property (nonatomic, readonly) DSWallet *currentWallet;
@property (nonatomic, readonly) NSArray *allWallets;
@property (nonatomic, readonly) DSAccount *currentAccount;
@property (nonatomic, strong) DSChainManager *currentChainManager;
@property (nonatomic, readonly) SystemSoundID pingsound;

+ (instancetype _Nullable)sharedInstance;
- (void)clearAllWallets;
- (void)switchToMainnetWithCompletion:(void (^)(BOOL success))completion;
- (void)switchToTestnetWithCompletion:(void (^)(BOOL success))completion;
- (void)reset;
- (void)playPingSound;

@end

NS_ASSUME_NONNULL_END
