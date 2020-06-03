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

#import "DWContactsSearchDataSource.h"

#import "DWContactsDataSource.h"
#import "DWDPContactsItemsFactory.h"
#import "NSPredicate+DWFullTextSearch.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsSearchDataSource ()

@property (readonly, nonatomic, copy) NSArray<id<DWDPBasicItem>> *firstSection;
@property (readonly, nonatomic, copy) NSArray<id<DWDPBasicItem>> *secondSection;

@property (nullable, nonatomic, copy) NSArray<id<DWDPBasicItem>> *filteredFirstSection;
@property (nullable, nonatomic, copy) NSArray<id<DWDPBasicItem>> *filteredSecondSection;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsSearchDataSource

- (instancetype)initWithFactory:(DWDPContactsItemsFactory *)factory
                       firstFRC:(NSFetchedResultsController *)firstFRC
                      secondFRC:(NSFetchedResultsController *)secondFRC {
    self = [super init];
    if (self) {
        _firstSection = [self.class itemsWithFactory:factory frc:firstFRC];
        _secondSection = [self.class itemsWithFactory:factory frc:secondFRC];
    }
    return self;
}

- (void)filterWithTrimmedQuery:(NSString *)trimmedQuery {
    id<DWDPBasicItem> item = nil;
    NSArray<NSString *> *searchKeyPaths = @[ DW_KEYPATH(item, username), DW_KEYPATH(item, displayName) ];
    NSPredicate *predicate = [NSPredicate dw_searchPredicateForTrimmedQuery:trimmedQuery
                                                             searchKeyPaths:searchKeyPaths];
    self.filteredFirstSection = [self.firstSection filteredArrayUsingPredicate:predicate];
    self.filteredSecondSection = [self.secondSection filteredArrayUsingPredicate:predicate];
}

#pragma mark - Private

+ (NSArray<id<DWDPBasicItem>> *)itemsWithFactory:(DWDPContactsItemsFactory *)factory frc:(NSFetchedResultsController *)frc {
    NSMutableArray<id<DWDPBasicItem>> *items = [NSMutableArray array];
    for (NSManagedObject *entity in frc.fetchedObjects) {
        id<DWDPBasicItem> item = [factory itemForEntity:entity];
        [items addObject:item];
    }
    return [items copy];
}

@end
