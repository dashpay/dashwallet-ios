//
//  Created by Sam Westrich
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWLocalMasternodeListModel.h"
#import "DWEnvironment.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWLocalMasternodeListModel ()

@property (readonly, copy, nonatomic) NSArray<DSLocalMasternode *> *allItems;
@property (nullable, copy, nonatomic) NSArray<DSLocalMasternode *> *filteredItems;
@property (nullable, nonatomic, copy) NSString *trimmedQuery;
@property (nonatomic, assign, getter=isSearching) BOOL searching;

@end

@implementation DWLocalMasternodeListModel

- (instancetype)init {
    self = [super init];
    if (self) {

        _allItems = [self localMasternodes];
    }

    return self;
}

- (NSArray<DSLocalMasternode *> *)localMasternodes {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSMasternodeManager *masternodeManager = chain.chainManager.masternodeManager;
    return [masternodeManager localMasternodes];
}

- (NSArray<DSLocalMasternode *> *)items {
    if (self.isSearching) {
        return self.filteredItems ?: @[];
    }
    else {
        return self.allItems;
    }
}

- (void)filterItemsWithSearchQuery:(NSString *)query {
    self.searching = query.length > 0;

    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
    NSString *trimmedQuery = [query stringByTrimmingCharactersInSet:whitespaces];
    self.trimmedQuery = trimmedQuery;

    NSPredicate *predicate = [self searchPredicateForTrimmedQuery:trimmedQuery];
    self.filteredItems = [self.allItems filteredArrayUsingPredicate:predicate];
}

#pragma mark - Private

- (NSCompoundPredicate *)searchPredicateForTrimmedQuery:(NSString *)trimmedQuery {
    NSArray<NSString *> *searchItems = [trimmedQuery componentsSeparatedByString:@" "];

    NSMutableArray<NSPredicate *> *searchItemsPredicate = [NSMutableArray array];
    for (NSString *searchString in searchItems) {
        NSCompoundPredicate *orPredicate = [self findMatchesForString:searchString];
        [searchItemsPredicate addObject:orPredicate];
    }

    NSCompoundPredicate *andPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:searchItemsPredicate];

    return andPredicate;
}

- (NSCompoundPredicate *)findMatchesForString:(NSString *)searchString {
    NSMutableArray<NSPredicate *> *searchItemsPredicate = [NSMutableArray array];

    DSLocalMasternode *item = nil;
    NSArray<NSString *> *searchKeyPaths = @[ DW_KEYPATH(item, ipAddressString) ];

    for (NSString *keyPath in searchKeyPaths) {
        NSExpression *leftExpression = [NSExpression expressionForKeyPath:keyPath];
        NSExpression *rightExpression = [NSExpression expressionForConstantValue:searchString];
        NSComparisonPredicateOptions options =
            NSCaseInsensitivePredicateOption | NSDiacriticInsensitivePredicateOption;
        NSComparisonPredicate *comparisonPredicate =
            [NSComparisonPredicate predicateWithLeftExpression:leftExpression
                                               rightExpression:rightExpression
                                                      modifier:NSDirectPredicateModifier
                                                          type:NSContainsPredicateOperatorType
                                                       options:options];
        [searchItemsPredicate addObject:comparisonPredicate];
    }

    NSCompoundPredicate *orPredicate = [NSCompoundPredicate orPredicateWithSubpredicates:searchItemsPredicate];

    return orPredicate;
}

@end

NS_ASSUME_NONNULL_END
