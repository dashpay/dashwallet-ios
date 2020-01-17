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

#import <UIKit/UIKit.h>

#import "DWContactItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DWContactListTableViewCell;

@protocol DWContactListTableViewCellDelegate <NSObject>

- (void)contactListTableViewCell:(DWContactListTableViewCell *)cell
                didAcceptContact:(id<DWContactItem>)contact;
- (void)contactListTableViewCell:(DWContactListTableViewCell *)cell
               didDeclineContact:(id<DWContactItem>)contact;

@end

@interface DWContactListTableViewCell : UITableViewCell

@property (nullable, nonatomic, strong) id<DWContactItem> contact;
@property (nullable, nonatomic, weak) id<DWContactListTableViewCellDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
