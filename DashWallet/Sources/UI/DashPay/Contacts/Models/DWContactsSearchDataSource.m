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
#import "DWUserDetailsConvertible.h"
#import "NSPredicate+DWFullTextSearch.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsSearchDataSource ()

@property (readonly, nonatomic, copy) NSArray<id<DWUserDetails>> *firstSection;
@property (readonly, nonatomic, copy) NSArray<id<DWUserDetails>> *secondSection;

@property (nullable, nonatomic, copy) NSArray<id<DWUserDetails>> *filteredFirstSection;
@property (nullable, nonatomic, copy) NSArray<id<DWUserDetails>> *filteredSecondSection;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsSearchDataSource

- (instancetype)initWithIncomingFRC:(NSFetchedResultsController<DSFriendRequestEntity *> *)incomingFRC
                        contactsFRC:(NSFetchedResultsController<DSDashpayUserEntity *> *)contactsFRC {
    self = [super init];
    if (self) {
        _firstSection = [self.class allItemsFromFRC:
                                        (NSFetchedResultsController<id<DWUserDetailsConvertible>> *)incomingFRC];
        _secondSection = [self.class allItemsFromFRC:
                                         (NSFetchedResultsController<id<DWUserDetailsConvertible>> *)contactsFRC];
    }
    return self;
}

- (void)filterWithTrimmedQuery:(NSString *)trimmedQuery {
    id<DWUserDetails> item = nil;
    NSArray<NSString *> *searchKeyPaths = @[ DW_KEYPATH(item, username), DW_KEYPATH(item, displayName) ];
    NSPredicate *predicate = [NSPredicate dw_searchPredicateForTrimmedQuery:trimmedQuery
                                                             searchKeyPaths:searchKeyPaths];
    self.filteredFirstSection = [self.firstSection filteredArrayUsingPredicate:predicate];
    self.filteredSecondSection = [self.secondSection filteredArrayUsingPredicate:predicate];
}

#pragma mark - Private

+ (NSArray<id<DWUserDetails>> *)allItemsFromFRC:(NSFetchedResultsController<id<DWUserDetailsConvertible>> *)frc {
    NSMutableArray<id<DWUserDetails>> *items = [NSMutableArray array];
    for (id<DWUserDetailsConvertible> entity in frc.fetchedObjects) {
        id<DWUserDetails> item = [entity asUserDetails];
        [items addObject:item];
    }
    return [items copy];
}

@end
