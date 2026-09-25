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

/// Recovers a wallet from a seed phrase and starts syncing
@interface DWRecoverWalletCommand : NSObject

- (instancetype)initWithPhrase:(NSString *)phrase;

- (void)execute;

/// `execute` with a verdict: `completion` runs on the main queue with YES
/// once the wallet exists and its mnemonic is persisted, NO when the import
/// was refused (no phrase, no PIN) or failed. Setup must not complete on NO.
- (void)executeWithCompletion:(void (^)(BOOL succeeded))completion;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
