//
//  Created by administrator
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

#import "NSPredicate+DWFullTextSearch.h"

@implementation NSPredicate (DWFullTextSearch)

+ (NSCompoundPredicate *)dw_searchPredicateForTrimmedQuery:(NSString *)trimmedQuery
                                            searchKeyPaths:(NSArray<NSString *> *)searchKeyPaths {
    NSArray<NSString *> *searchItems = [trimmedQuery componentsSeparatedByString:@" "];

    NSMutableArray<NSPredicate *> *searchItemsPredicate = [NSMutableArray array];
    for (NSString *searchString in searchItems) {
        NSCompoundPredicate *orPredicate = [self dw_findMatchesForString:searchString searchKeyPaths:searchKeyPaths];
        [searchItemsPredicate addObject:orPredicate];
    }

    NSCompoundPredicate *andPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:searchItemsPredicate];

    return andPredicate;
}

+ (NSCompoundPredicate *)dw_findMatchesForString:(NSString *)searchString
                                  searchKeyPaths:(NSArray<NSString *> *)searchKeyPaths {
    NSMutableArray<NSPredicate *> *searchItemsPredicate = [NSMutableArray array];

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
