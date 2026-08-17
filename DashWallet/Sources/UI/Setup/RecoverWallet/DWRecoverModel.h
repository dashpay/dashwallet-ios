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

#import "DWRecoverAction.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const DW_WIPE;
extern NSString *const DW_WIPE_STRONG;
extern NSString *const DW_WATCH;
extern NSInteger const DW_PHRASE_MIN_LENGTH;
extern NSInteger const DW_PHRASE_MULTIPLE;

@interface DWRecoverModel : NSObject

@property (readonly, nonatomic, assign) DWRecoverAction action;

- (BOOL)hasWallet;

/// Whether a PIN record exists in the keychain. In ResetPin mode the screen's
/// copy depends on it: an existing PIN is "reset", a missing record (partial
/// keychain restore, interrupted setup) is "set".
- (BOOL)hasPinSet;

// `isWalletEmpty`, wipe/reset-PIN phrase authorization, and mnemonic helpers
// are provided by the Swift extension
// `DWRecoverModel+Mnemonic.swift` (SwiftDashSDK) and reach Obj-C callers
// through the generated `dashwallet-Swift.h`.

- (void)wipeWallet;

- (NSString *)wipeAcceptPhrase;

- (instancetype)initWithAction:(DWRecoverAction)action;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
