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

#import "DWDPBasicUserItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DWUserSearchModel;
@class DSIdentity;

@protocol DWUserSearchModelDelegate <NSObject>

- (void)userSearchModelDidStartSearch:(DWUserSearchModel *)model;
- (void)userSearchModel:(DWUserSearchModel *)model completedWithItems:(NSArray<id<DWDPBasicUserItem>> *)items;
- (void)userSearchModel:(DWUserSearchModel *)model completedWithError:(NSError *)error;

@end

@interface DWUserSearchModel : NSObject

@property (readonly, nonatomic, copy) NSString *trimmedQuery;
@property (nullable, nonatomic, weak) id<DWUserSearchModelDelegate> delegate;

@property (nullable, nonatomic, weak) UIViewController *context;

- (void)searchWithQuery:(NSString *)searchQuery;
- (void)willDisplayItemAtIndex:(NSInteger)index;

- (id<DWDPBasicUserItem>)itemAtIndex:(NSInteger)index;

- (BOOL)canOpenIdentity:(DSIdentity *)identity;

- (void)acceptContactRequest:(id<DWDPBasicUserItem>)item;
- (void)declineContactRequest:(id<DWDPBasicUserItem>)item;

@end

NS_ASSUME_NONNULL_END
