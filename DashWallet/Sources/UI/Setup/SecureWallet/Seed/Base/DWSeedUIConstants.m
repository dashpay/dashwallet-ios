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

#import "DWSeedUIConstants.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

CGFloat const DW_TOP_DEFAULT_PADDING = 64.0;
CGFloat const DW_TOP_COMPACT_PADDING = 16.0;
CGFloat const DW_BOTTOM_PADDING = 12.0;

CGFloat DWTitleSeedPhrasePadding(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 12.0;
    }
    else {
        return 20.0;
    }
}

NS_ASSUME_NONNULL_END
