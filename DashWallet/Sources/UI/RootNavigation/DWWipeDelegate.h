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

@protocol DWWipeDelegate <NSObject>

- (void)didWipeWallet;

/// Begin a full wipe after the user has explicitly confirmed Delete All.
/// Implementers that support this optional path first present the onboarding
/// wipe gate, then trigger the destructive wipe after its progress HUD renders.
@optional
- (void)beginWipeWallet;

@end

NS_ASSUME_NONNULL_END
