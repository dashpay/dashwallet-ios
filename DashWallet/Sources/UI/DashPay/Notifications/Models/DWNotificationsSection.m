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

#import "DWNotificationsSection.h"

#import "DWNotificationItemConvertible.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsSection ()

@property (readonly, nonatomic, strong) DWDPNotificationItemsFactory *itemsFactory;
@property (readonly, nonatomic, copy) NSArray<id<DWNotificationItemConvertible>> *items;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsSection

- (instancetype)initWithFactory:(DWDPNotificationItemsFactory *)factory
                    incomingFRC:(NSFetchedResultsController<DSFriendRequestEntity *> *)incomingFRC
                     ignoredFRC:(NSFetchedResultsController<DSFriendRequestEntity *> *)ignoredFRC
                    contactsFRC:(NSFetchedResultsController<DSDashpayUserEntity *> *)contactsFRC {
    self = [super init];
    if (self) {
        _itemsFactory = factory;

        // TODO: merge these three FRC results and sort by date
        NSMutableArray<id<DWNotificationItemConvertible>> *items = [NSMutableArray array];
        [items addObjectsFromArray:incomingFRC.fetchedObjects];
        [items addObjectsFromArray:ignoredFRC.fetchedObjects];
        [items addObjectsFromArray:contactsFRC.fetchedObjects];

        _items = [items copy];
    }
    return self;
}

- (NSUInteger)count {
    return self.items.count;
}

- (id<DWDPBasicItem>)itemAtIndex:(NSInteger)index {
    id<DWNotificationItemConvertible> rawItem = self.items[index];
    return [rawItem asNotificationItemWithFactory:self.itemsFactory];
}

@end
