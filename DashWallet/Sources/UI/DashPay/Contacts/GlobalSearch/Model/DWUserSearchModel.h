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

#import "DWDPBasicItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DWUserSearchModel;
@class DSBlockchainIdentity;

@protocol DWUserSearchModelDelegate <NSObject>

- (void)userSearchModelDidStartSearch:(DWUserSearchModel *)model;
- (void)userSearchModel:(DWUserSearchModel *)model completedWithItems:(NSArray<id<DWDPBasicItem>> *)items;
- (void)userSearchModel:(DWUserSearchModel *)model completedWithError:(NSError *)error;

@end

@interface DWUserSearchModel : NSObject

@property (readonly, nonatomic, copy) NSString *trimmedQuery;
@property (nullable, nonatomic, weak) id<DWUserSearchModelDelegate> delegate;

- (void)searchWithQuery:(NSString *)searchQuery;
- (void)willDisplayItemAtIndex:(NSInteger)index;

- (id<DWDPBasicItem>)itemAtIndex:(NSInteger)index;

- (BOOL)canOpenBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity;

- (void)acceptContactRequest:(id<DWDPBasicItem>)item;

@end

NS_ASSUME_NONNULL_END
