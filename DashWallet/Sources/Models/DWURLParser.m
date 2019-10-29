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

#import "DWURLParser.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Actions

@implementation DWURLAction
@end

@implementation DWURLScanQRAction
@end

#pragma mark - Parser

@implementation DWURLParser

+ (BOOL)canHandleURL:(NSURL *)url {
    if (!url) {
        return NO;
    }

    return [url.scheme isEqual:@"dash"] || [url.scheme isEqual:@"dashwallet"];
}

+ (nullable DWURLAction *)actionForURL:(NSURL *)url {
    if ([url.scheme isEqual:@"dashwallet"]) {
        if ([url.host isEqual:@"scanqr"] || [url.path isEqual:@"/scanqr"]) {
            return [[DWURLScanQRAction alloc] init];
        }
    }

    // TODO: <redesign> impl other URL types

    return nil;
}

@end

NS_ASSUME_NONNULL_END
