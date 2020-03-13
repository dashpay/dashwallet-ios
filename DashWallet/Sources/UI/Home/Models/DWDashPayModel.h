//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWDashPayProtocol.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain DWDashPayErrorDomain;

typedef NS_ENUM(NSInteger, DWDashPayErrorCode) {
    DWDashPayErrorCode_UnableToRegisterBU = 1,
    DWDashPayErrorCode_CreateBUTxNotSigned = 2,
};

@interface DWDashPayModel : NSObject <DWDashPayProtocol>

@end

NS_ASSUME_NONNULL_END
