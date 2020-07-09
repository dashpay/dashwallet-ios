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

#import "DWContactsSearchDataSourceObject.h"

#import "DWContactsDataSource.h"
#import "DWDPContactsItemsFactory.h"
#import "NSPredicate+DWFullTextSearch.h"

#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsSearchDataSourceObject ()

@property (nullable, nonatomic, copy) NSArray<id<DWDPBasicItem>> *filteredContactRequest;
@property (nullable, nonatomic, copy) NSArray<id<DWDPBasicItem>> *filteredContacts;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsSearchDataSourceObject

@synthesize trimmedQuery = _trimmedQuery;

- (instancetype)initWithContactRequestsFRC:(NSFetchedResultsController *)contactRequestsFRC
                               contactsFRC:(NSFetchedResultsController *)contactsFRC
                              itemsFactory:(DWDPContactsItemsFactory *)itemsFactory
                              trimmedQuery:(NSString *)trimmedQuery {
    self = [super init];
    if (self) {
        NSArray<id<DWDPBasicItem>> *contactRequests = [self.class itemsWithFactory:itemsFactory frc:contactRequestsFRC];
        NSArray<id<DWDPBasicItem>> *contacts = [self.class itemsWithFactory:itemsFactory frc:contactsFRC];
        _filteredContactRequest = [self.class filterItems:contactRequests trimmedQuery:trimmedQuery];
        _filteredContacts = [self.class filterItems:contacts trimmedQuery:trimmedQuery];
        _trimmedQuery = [trimmedQuery copy];
    }
    return self;
}

- (BOOL)isEmpty {
    const NSInteger count = self.requestsCount + self.contactsCount;
    return count == 0;
}

- (BOOL)isSearching {
    return YES;
}

- (DWContactsSortMode)sortMode {
    return DWContactsSortMode_ByUsername;
}

- (NSUInteger)requestsCount {
    return self.filteredContactRequest.count;
}

- (NSUInteger)contactsCount {
    return self.filteredContacts.count;
}

- (id<DWDPBasicItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return self.filteredContactRequest[indexPath.row];
    }
    else {
        return self.filteredContacts[indexPath.row];
    }
}

#pragma mark - Private

+ (NSArray<id<DWDPBasicItem>> *)filterItems:(NSArray<id<DWDPBasicItem>> *)items trimmedQuery:(NSString *)trimmedQuery {
    id<DWDPBasicItem> item = nil;
    NSArray<NSString *> *searchKeyPaths = @[ DW_KEYPATH(item, username), DW_KEYPATH(item, displayName) ];
    NSPredicate *predicate = [NSPredicate dw_searchPredicateForTrimmedQuery:trimmedQuery
                                                             searchKeyPaths:searchKeyPaths];
    return [items filteredArrayUsingPredicate:predicate];
}

+ (NSArray<id<DWDPBasicItem>> *)itemsWithFactory:(DWDPContactsItemsFactory *)factory frc:(NSFetchedResultsController *)frc {
    NSMutableArray<id<DWDPBasicItem>> *items = [NSMutableArray array];
    for (NSManagedObject *entity in frc.fetchedObjects) {
        id<DWDPBasicItem> item = [factory itemForEntity:entity];
        [items addObject:item];
    }
    return [items copy];
}

@end
