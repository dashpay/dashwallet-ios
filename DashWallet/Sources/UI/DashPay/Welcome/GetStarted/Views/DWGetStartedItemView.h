//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWGetStartedItemType) {
    DWGetStartedItemType_1,
    DWGetStartedItemType_Inactive2,
    DWGetStartedItemType_Active2,
    DWGetStartedItemType_Inactive3,
    DWGetStartedItemType_Active3,
};

@interface DWGetStartedItemView : UIView

- (instancetype)initWithItemType:(DWGetStartedItemType)itemType completed:(BOOL)completed;

@end

NS_ASSUME_NONNULL_END
