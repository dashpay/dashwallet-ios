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

NS_ASSUME_NONNULL_BEGIN

@class DWSeedPhraseModel;

@interface DWPreviewSeedPhraseModel : NSObject

@property (readonly, class, nonatomic, assign) BOOL shouldVerifyPassphrase;

/// BIP39 word count used when `getOrCreateNewWallet` has to generate a fresh
/// phrase (12 or 24, as picked on the backup-info screen). Defaults to 12.
/// Ignored once a phrase exists — it never changes an existing wallet.
@property (nonatomic, assign) NSUInteger newWalletWordCount;

- (instancetype)initWithExistingSeedPhrase:(NSString *)seedPhrase;
- (DWSeedPhraseModel *)getOrCreateNewWallet;
- (void)clearAllWallets;

@end

NS_ASSUME_NONNULL_END
