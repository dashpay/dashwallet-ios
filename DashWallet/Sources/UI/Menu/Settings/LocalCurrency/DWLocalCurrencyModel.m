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

#import <objc/runtime.h>

#import "DWWeakContainer.h"
#import <DashSync/DSCurrencyPriceObject.h>
#import <DashSync/DashSync.h>


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

@property (nonatomic, strong) NSNumberFormatter *numberFormatter;
@property (nullable, nonatomic, strong) DSCurrencyPriceObject *currentPrice;

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

        _currentPrice = [priceManager priceForCurrencyCode:priceManager.localCurrencyCode];

        _items = priceManager.prices;
        for (DSCurrencyPriceObject *priceObject in _items) {
            [priceObject setPriceProvider:self];
        }
    }

    return self;
}

- (BOOL)isCurrencyItemsSelected:(id<DWCurrencyItem>)currencyItem {
    if (!self.currentPrice) {
        return NO;
    }

    return [self.currentPrice.code isEqualToString:currencyItem.code];
}

- (void)selectItem:(id<DWCurrencyItem>)item {
    self.currentPrice = (DSCurrencyPriceObject *)item;

    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    priceManager.localCurrencyCode = item.code;
}

#pragma mark - DWCurrencyItemPriceProvider

- (nullable NSString *)formatPrice:(NSNumber *)price {
    if (!price) {
        return nil;
    }

    return [self.numberFormatter stringFromNumber:price];
}

@end

NS_ASSUME_NONNULL_END
