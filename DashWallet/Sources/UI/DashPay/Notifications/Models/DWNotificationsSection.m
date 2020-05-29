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

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsSection ()

@property (readonly, nonatomic, copy) NSArray<id<DWNotificationDetailsConvertible>> *items;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsSection

- (instancetype)initWithIncomingFRC:(NSFetchedResultsController *)incomingFRC
                         ignoredFRC:(NSFetchedResultsController *)ignoredFRC
                        contactsFRC:(NSFetchedResultsController *)contactsFRC {
    self = [super init];
    if (self) {
        // TODO: merge these three FRC results and sort by date

        NSMutableArray<id<DWNotificationDetailsConvertible>> *items = [NSMutableArray array];
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

- (id<DWNotificationDetails>)notificationDetailsAtIndex:(NSInteger)index {
    id<DWNotificationDetailsConvertible> rawItem = self.items[index];
    return [rawItem asNotificationDetails];
}

@end
