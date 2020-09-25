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
extern NSInteger const DW_PHRASE_LENGTH;

@interface DWRecoverModel : NSObject

@property (readonly, nonatomic, assign) DWRecoverAction action;

- (BOOL)hasWallet;
- (BOOL)isWalletEmpty;

- (NSString *)cleanupPhrase:(NSString *)phrase;
- (nullable NSString *)normalizePhrase:(NSString *)phrase;

- (BOOL)wordIsLocal:(NSString *)word;
- (BOOL)wordIsValid:(NSString *)word;

- (BOOL)phraseIsValid:(NSString *)phrase;

- (void)wipeWallet;
- (BOOL)canWipeWithPhrase:(NSString *)phrase;

- (NSString *)wipeAcceptPhrase;

- (instancetype)initWithAction:(DWRecoverAction)action;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
