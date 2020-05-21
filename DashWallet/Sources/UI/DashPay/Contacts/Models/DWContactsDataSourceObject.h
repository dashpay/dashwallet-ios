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

#import "DWContactsDataSource.h"

#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsDataSourceObject : NSObject <DWContactsDataSource>

@property (readonly, nonatomic, assign, getter=isEmpty) BOOL empty;
@property (readonly, nonatomic, assign, getter=isSearching) BOOL searching;

- (void)beginReloading;
- (void)endReloading;

- (void)reloadIncomingContactRequests:(NSFetchedResultsController<DSFriendRequestEntity *> *)frc;
- (void)reloadContacts:(NSFetchedResultsController<DSDashpayUserEntity *> *)frc;

@end

NS_ASSUME_NONNULL_END
