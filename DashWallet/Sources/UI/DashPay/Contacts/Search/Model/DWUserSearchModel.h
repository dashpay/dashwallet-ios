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

#import <Foundation/Foundation.h>

#import "DWContactItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DWUserSearchModel;

@protocol DWUserSearchModelDelegate <NSObject>

- (void)userSearchModel:(DWUserSearchModel *)model completedWithItems:(NSArray<id<DWContactItem>> *)items;
- (void)userSearchModel:(DWUserSearchModel *)model completedWithError:(NSError *)error;

@end

@interface DWUserSearchModel : NSObject

@property (readonly, nonatomic, copy) NSString *trimmedQuery;
@property (nullable, nonatomic, weak) id<DWUserSearchModelDelegate> delegate;

- (void)searchWithQuery:(nullable NSString *)searchQuery;
- (void)willDisplayItemAtIndex:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
