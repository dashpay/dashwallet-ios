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

#import "DWURLActions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWURLAction
@end

//

@implementation DWURLUpholdAction
@end

//

@implementation DWURLScanQRAction
@end

//

@implementation DWURLRequestAction

- (DWURLRequestActionType)type {
    NSAssert(self.request != nil, @"Type is not available. Action is not configured");

    if ([self.request isEqualToString:@"masterPublicKey"]) {
        return DWURLRequestActionType_MasterPublicKey;
    }
    else if ([self.request isEqualToString:@"address"]) {
        return DWURLRequestActionType_Address;
    }

    return DWURLRequestActionType_Unknown;
}

@end

//

@implementation DWURLPayAction
@end

NS_ASSUME_NONNULL_END
