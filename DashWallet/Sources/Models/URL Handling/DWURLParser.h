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

#import "DWURLActions.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWURLParser : NSObject

+ (BOOL)allowsURLHandling;
+ (BOOL)canHandleURL:(NSURL *)url;

+ (nullable DWURLAction *)actionForURL:(NSURL *)url;

/// The `dash:` URI for a `dashwallet://pay=` link the wallet read itself (a scan, a paste, an NFC
/// tag) and no app opened: the link's address, parameters and own label, without `sender`. No app
/// asked for that payment, so none is named on the confirmation or called back after it.
/// nil for anything `actionForURL:` does not turn into a payment.
+ (nullable NSURL *)paymentURLForScannedLink:(NSURL *)url;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
