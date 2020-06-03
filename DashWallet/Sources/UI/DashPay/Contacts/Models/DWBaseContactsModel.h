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

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>

#import "DWContactsDataSource.h"
#import "DWContactsSortModeProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class DWBaseContactsModel;

@protocol DWContactsModelDelegate <NSObject>

- (void)contactsModelDidUpdate:(DWBaseContactsModel *)model;

@end

@interface DWBaseContactsModel : NSObject <DWContactsSortModeProtocol>

@property (readonly, nonatomic, assign) BOOL hasBlockchainIdentity;
@property (readonly, nonatomic, assign, getter=isEmpty) BOOL empty;
@property (readonly, nonatomic, assign, getter=isSearching) BOOL searching;
@property (readonly, nonatomic, strong) id<DWContactsDataSource> dataSource;
@property (nullable, nonatomic, weak) id<DWContactsModelDelegate> delegate;

- (void)start;
- (void)stop;

- (void)fetchData;

- (void)acceptContactRequest:(id<DWDPBasicItem>)item;

- (void)searchWithQuery:(NSString *)searchQuery;

@end

NS_ASSUME_NONNULL_END
