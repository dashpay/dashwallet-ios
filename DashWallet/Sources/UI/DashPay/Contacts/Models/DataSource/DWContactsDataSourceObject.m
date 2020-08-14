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

#import "DWContactsDataSourceObject.h"

#import "DWDPContactsItemsFactory.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsDataSourceObject ()

@property (nullable, readonly, nonatomic, strong) NSFetchedResultsController *requestsFRC;
@property (nullable, readonly, nonatomic, strong) NSFetchedResultsController *contactsFRC;
@property (readonly, nonatomic, strong) DWDPContactsItemsFactory *itemsFactory;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsDataSourceObject

@synthesize sortMode = _sortMode;

- (instancetype)initWithRequestsFRC:(NSFetchedResultsController *)requestsFRC
                        contactsFRC:(NSFetchedResultsController *)contactsFRC
                       itemsFactory:(DWDPContactsItemsFactory *)itemsFactory
                           sortMode:(DWContactsSortMode)sortMode {
    self = [super init];
    if (self) {
        _requestsFRC = requestsFRC;
        _contactsFRC = contactsFRC;
        _itemsFactory = itemsFactory;
        _sortMode = sortMode;
    }
    return self;
}

- (BOOL)isEmpty {
    if (self.requestsFRC == nil && self.contactsFRC == nil) {
        return YES;
    }

    const NSInteger count = self.requestsCount + self.contactsCount;
    return count == 0;
}

- (BOOL)isSearching {
    return NO;
}

- (NSString *)trimmedQuery {
    return nil;
}

- (NSUInteger)requestsCount {
    return self.requestsFRC.sections.firstObject.numberOfObjects;
}

- (NSUInteger)contactsCount {
    return self.contactsFRC.sections.firstObject.numberOfObjects;
}

- (id<DWDPBasicUserItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NSManagedObject *entity = [self.requestsFRC objectAtIndexPath:indexPath];
        id<DWDPBasicUserItem> item = [self.itemsFactory itemForEntity:entity];
        return item;
    }
    else {
        NSIndexPath *transformedIndexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:0];
        NSManagedObject *entity = [self.contactsFRC objectAtIndexPath:transformedIndexPath];
        id<DWDPBasicUserItem> item = [self.itemsFactory itemForEntity:entity];
        return item;
    }
}

@end
