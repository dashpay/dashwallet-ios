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

#import "DWCurrencyItemPriceProvider.h"
#import "DWCurrencyObject.h"
#import "NSPredicate+DWFullTextSearch.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWLocalCurrencyModel () <DWCurrencyItemPriceProvider>

@property (readonly, copy, nonatomic) NSArray<id<DWCurrencyItem>> *allItems;
@property (nullable, copy, nonatomic) NSArray<id<DWCurrencyItem>> *filteredItems;
@property (nullable, nonatomic, copy) NSString *trimmedQuery;
@property (nonatomic, assign, getter=isSearching) BOOL searching;
@property (nonatomic, assign) NSUInteger selectedIndex;

@property (nonatomic, strong) NSNumberFormatter *numberFormatter;
@property (readonly, copy, nonatomic) NSDictionary<NSString *, NSString *> *flagByCode;

@end

@implementation DWLocalCurrencyModel

@synthesize flagByCode = _flagByCode;

- (instancetype)initWithCurrencyCode:(nullable NSString *)currencyCode {
    self = [super init];
    if (self) {
        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        numberFormatter.maximumFractionDigits = 2;
        numberFormatter.minimumFractionDigits = 2;
        _numberFormatter = numberFormatter;

        NSString *selectedCurrencyCode = currencyCode ?: DWApp.localCurrencyCode;
        NSArray<DSCurrencyPriceObject *> *prices = [CurrencyExchangerObjcWrapper prices];

        NSMutableArray<DWCurrencyObject *> *allItems = [NSMutableArray array];
        for (size_t i = 0; i < prices.count; i++) {
            DSCurrencyPriceObject *priceObject = prices[i];

            DWCurrencyObject *object =
                [[DWCurrencyObject alloc] initWithPriceObject:priceObject
                                                     flagName:self.flagByCode[priceObject.code]
                                                     provider:self];
            [allItems addObject:object];

            if (selectedCurrencyCode == priceObject.code)
                _selectedIndex = i;
        }
        _allItems = allItems;
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

- (void)selectItem:(id<DWCurrencyItem>)item shouldChangeGlobalSettings:(BOOL)shouldChangeGlobalSettings {
    if (shouldChangeGlobalSettings) {
        DWApp.localCurrencyCode = item.code;
    }

    NSArray<DSCurrencyPriceObject *> *prices = [CurrencyExchangerObjcWrapper prices];

    for (size_t i = 0; i < prices.count; i++) {
        DSCurrencyPriceObject *priceObject = prices[i];
        if ([priceObject.code isEqualToString:item.code]) {
            self.selectedIndex = i;
            return;
        }
    }
}

- (void)filterItemsWithSearchQuery:(NSString *)query {
    self.searching = query.length > 0;

    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
    NSString *trimmedQuery = [query stringByTrimmingCharactersInSet:whitespaces];
    self.trimmedQuery = trimmedQuery;

    id<DWCurrencyItem> item = nil;
    NSArray<NSString *> *searchKeyPaths = @[ DW_KEYPATH(item, code), DW_KEYPATH(item, name) ];
    NSPredicate *predicate = [NSPredicate dw_searchPredicateForTrimmedQuery:trimmedQuery
                                                             searchKeyPaths:searchKeyPaths];
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

- (NSDictionary<NSString *, NSString *> *)flagByCode {
    if (_flagByCode != nil) {
        return _flagByCode;
    }

    _flagByCode = @{
        @"AED" : @"united arab emirates",
        @"AFN" : @"afghanistan",
        @"ALL" : @"albania",
        @"AMD" : @"armenia",
        @"ANG" : @"sint maarten",
        @"AOA" : @"angola",
        @"ARS" : @"argentina",
        @"AUD" : @"australia",
        @"AWG" : @"aruba",
        @"AZN" : @"azerbaijan",
        @"BAM" : @"bosnia and herzegovina",
        @"BBD" : @"barbados",
        @"BDT" : @"bangladesh",
        @"BGN" : @"bulgaria",
        @"BHD" : @"bahrain",
        @"BIF" : @"burundi",
        @"BMD" : @"bermuda",
        @"BND" : @"brunei",
        @"BOB" : @"bolivia",
        @"BRL" : @"brazil",
        @"BSD" : @"bahamas",
        @"BTN" : @"bhutan",
        @"BWP" : @"botswana",
        @"BYN" : @"belarus",
        @"BZD" : @"belize",
        @"CAD" : @"canada",
        @"CDF" : @"democratic republic of congo",
        @"CHF" : @"switzerland",
        @"CLF" : @"chile",
        @"CLP" : @"chile",
        @"CNY" : @"china",
        @"COP" : @"colombia",
        @"CRC" : @"costa rica",
        @"CUP" : @"cuba",
        @"CVE" : @"cape verde",
        @"CZK" : @"czech republic",
        @"DJF" : @"djibouti",
        @"DKK" : @"denmark",
        @"DOP" : @"dominican republic",
        @"DZD" : @"Algeria",
        @"EGP" : @"egypt",
        @"ETB" : @"ethiopia",
        @"EUR" : @"european union",
        @"FJD" : @"fiji",
        @"FKP" : @"falkland islands",
        @"GBP" : @"united kingdom",
        @"GEL" : @"georgia",
        @"GHS" : @"ghana",
        @"GIP" : @"gibraltar",
        @"GMD" : @"gambia",
        @"GNF" : @"guinea",
        @"GTQ" : @"guatemala",
        @"GYD" : @"guyana",
        @"HKD" : @"hong kong",
        @"HNL" : @"honduras",
        @"HRK" : @"croatia",
        @"HTG" : @"haiti",
        @"HUF" : @"hungary",
        @"IDR" : @"indonesia",
        @"ILS" : @"israel",
        @"INR" : @"india",
        @"IQD" : @"iraq",
        @"IRR" : @"iran",
        @"ISK" : @"iceland",
        @"JEP" : @"jersey",
        @"JMD" : @"jamaica",
        @"JOD" : @"jordan",
        @"JPY" : @"japan",
        @"KES" : @"kenya",
        @"KGS" : @"kyrgyzstan",
        @"KHR" : @"cambodia",
        @"KMF" : @"comoros",
        @"KPW" : @"north korea",
        @"KRW" : @"south korea",
        @"KWD" : @"kuwait",
        @"KYD" : @"cayman islands",
        @"KZT" : @"kazakhstan",
        @"LAK" : @"laos",
        @"LBP" : @"lebanon",
        @"LKR" : @"sri lanka",
        @"LRD" : @"liberia",
        @"LSL" : @"lesotho",
        @"LYD" : @"libya",
        @"MAD" : @"morocco",
        @"MDL" : @"moldova",
        @"MGA" : @"madagascar",
        @"MKD" : @"republic of macedonia",
        @"MMK" : @"myanmar",
        @"MNT" : @"mongolia",
        @"MOP" : @"macao",
        @"MRU" : @"mauritania",
        @"MUR" : @"mauritius",
        @"MVR" : @"maldives",
        @"MWK" : @"malawi",
        @"MXN" : @"mexico",
        @"MYR" : @"malaysia",
        @"MZN" : @"mozambique",
        @"NAD" : @"namibia",
        @"NGN" : @"nigeria",
        @"NIO" : @"nicaragua",
        @"NOK" : @"norway",
        @"NPR" : @"nepal",
        @"NZD" : @"new zealand",
        @"OMR" : @"oman",
        @"PAB" : @"panama",
        @"PEN" : @"peru",
        @"PGK" : @"papua new guinea",
        @"PHP" : @"philippines",
        @"PKR" : @"pakistan",
        @"PLN" : @"poland",
        @"PYG" : @"paraguay",
        @"QAR" : @"qatar",
        @"RON" : @"romania",
        @"RSD" : @"serbia",
        @"RUB" : @"russia",
        @"RWF" : @"rwanda",
        @"SAR" : @"saudi arabia",
        @"SBD" : @"solomon islands",
        @"SCR" : @"seychelles",
        @"SDG" : @"sudan",
        @"SEK" : @"sweden",
        @"SGD" : @"singapore",
        @"SHP" : @"united kingdom",
        @"SLL" : @"sierra leone",
        @"SOS" : @"somalia",
        @"SRD" : @"suriname",
        @"STN" : @"sao tome and prince",
        @"SVC" : @"el salvador",
        @"SYP" : @"syria",
        @"SZL" : @"swaziland",
        @"THB" : @"thailand",
        @"TJS" : @"tajikistan",
        @"TMT" : @"turkmenistan",
        @"TND" : @"tunisia",
        @"TOP" : @"tonga",
        @"TRY" : @"turkey",
        @"TTD" : @"trinidad and tobago",
        @"TWD" : @"taiwan",
        @"TZS" : @"tanzania",
        @"UAH" : @"ukraine",
        @"UGX" : @"uganda",
        @"USD" : @"united states",
        @"UYU" : @"uruguay",
        @"UZS" : @"uzbekistan",
        @"VES" : @"venezuela",
        @"VND" : @"vietnam",
        @"VUV" : @"vanuatu",
        @"WST" : @"samoa",
        @"XAF" : @"central african cfa franc",
        @"XCD" : @"anguilla",
        @"XOF" : @"benin",
        @"XPF" : @"french polynesia",
        @"YER" : @"yemen",
        @"ZAR" : @"south africa",
        @"ZMW" : @"zambia",
        @"ZWL" : @"zimbabwe",
    };

    return _flagByCode;
}

@end

NS_ASSUME_NONNULL_END
