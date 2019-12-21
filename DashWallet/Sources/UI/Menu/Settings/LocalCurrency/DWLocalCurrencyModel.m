//
//  Created by Andrew Podkovyrin
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

#import "DWLocalCurrencyModel.h"

#import <DashSync/DSCurrencyPriceObject.h>
#import <DashSync/DashSync.h>
#import <objc/runtime.h>

#import "DWWeakContainer.h"

NS_ASSUME_NONNULL_BEGIN

@protocol DWCurrencyItemPriceProvider <NSObject>

- (nullable NSString *)formatPrice:(NSNumber *)price;

@end

@interface DSCurrencyPriceObject (DWCurrencyItem_Protocol) <DWCurrencyItem>

@property (nullable, nonatomic, copy) NSString *dw_priceString;
@property (nullable, nonatomic, strong) DWWeakContainer *dw_providerContainer;

@end

@implementation DSCurrencyPriceObject (DWCurrencyItem_Protocol)

- (nullable NSString *)priceString {
    if (!self.dw_priceString) {
        DWWeakContainer *container = self.dw_providerContainer;
        if (container &&
            container.object &&
            [container.object conformsToProtocol:@protocol(DWCurrencyItemPriceProvider)]) {
            id<DWCurrencyItemPriceProvider> priceProvider = container.object;
            self.dw_priceString = [priceProvider formatPrice:self.price];
        }
    }
    return self.dw_priceString;
}

- (void)setPriceProvider:(id<DWCurrencyItemPriceProvider>)priceProvider {
    self.dw_providerContainer = [DWWeakContainer containerWithObject:priceProvider];
}

#pragma mark - Private

- (nullable NSString *)dw_priceString {
    return objc_getAssociatedObject(self, @selector(dw_priceString));
}

- (void)setDw_priceString:(nullable NSString *)dw_priceString {
    objc_setAssociatedObject(self, @selector(dw_priceString), dw_priceString, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (nullable DWWeakContainer *)dw_providerContainer {
    return objc_getAssociatedObject(self, @selector(dw_providerContainer));
}

- (void)setDw_providerContainer:(nullable DWWeakContainer *)dw_providerContainer {
    objc_setAssociatedObject(self, @selector(dw_providerContainer), dw_providerContainer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

#pragma mark -

@interface DWLocalCurrencyModel () <DWCurrencyItemPriceProvider>

@property (readonly, copy, nonatomic) NSArray<id<DWCurrencyItem>> *allItems;
@property (nullable, copy, nonatomic) NSArray<id<DWCurrencyItem>> *filteredItems;
@property (nullable, nonatomic, copy) NSString *trimmedQuery;
@property (nonatomic, assign, getter=isSearching) BOOL searching;
@property (nonatomic, assign) NSUInteger selectedIndex;

@property (nonatomic, strong) NSNumberFormatter *numberFormatter;

@end

@implementation DWLocalCurrencyModel

- (instancetype)init {
    self = [super init];
    if (self) {
        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        numberFormatter.maximumFractionDigits = 2;
        numberFormatter.minimumFractionDigits = 2;
        _numberFormatter = numberFormatter;

        DSPriceManager *priceManager = [DSPriceManager sharedInstance];
        DSCurrencyPriceObject *price = [priceManager priceForCurrencyCode:priceManager.localCurrencyCode];
        _selectedIndex = price ? [priceManager.prices indexOfObject:price] : 0;

        _allItems = priceManager.prices;
        for (DSCurrencyPriceObject *priceObject in _allItems) {
            [priceObject setPriceProvider:self];
        }
    }

    return self;
}

- (NSArray<id<DWCurrencyItem>> *)items {
    if (self.isSearching) {
        return self.filteredItems ?: @[];
    }
    else {
        return self.allItems;
    }
}

- (void)selectItem:(id<DWCurrencyItem>)item {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    priceManager.localCurrencyCode = item.code;

    DSCurrencyPriceObject *price = [priceManager priceForCurrencyCode:priceManager.localCurrencyCode];
    self.selectedIndex = price ? [priceManager.prices indexOfObject:price] : 0;
}

- (void)filterItemsWithSearchQuery:(NSString *)query {
    self.searching = query.length > 0;

    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
    NSString *trimmedQuery = [query stringByTrimmingCharactersInSet:whitespaces];
    self.trimmedQuery = trimmedQuery;

    NSPredicate *predicate = [self searchPredicateForTrimmedQuery:trimmedQuery];
    self.filteredItems = [self.allItems filteredArrayUsingPredicate:predicate];
}

#pragma mark - DWCurrencyItemPriceProvider

- (nullable NSString *)formatPrice:(NSNumber *)price {
    if (!price) {
        return nil;
    }

    return [self.numberFormatter stringFromNumber:price];
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

    id<DWCurrencyItem> item = nil;
    NSArray<NSString *> *searchKeyPaths = @[ DW_KEYPATH(item, code), DW_KEYPATH(item, name) ];

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
