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

#import "DWPaymentOutput+Private.h"

#import "NSAttributedString+DWDashAmountDisplay.h"
#import "UIColor+DWStyle.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

static CGSize const DashSymbolInRowSize = {11.0, 8.0};

#define LOCK @"\xF0\x9F\x94\x92" // unicode lock symbol U+1F512 (utf-8)

static NSString *sanitizeString(NSString *s) {
    NSMutableString *sane = [NSMutableString stringWithString:(s) ? s : @""];
    CFStringTransform((CFMutableStringRef)sane, NULL, kCFStringTransformToUnicodeName, NO);
    return sane;
}

@implementation DWPaymentOutput

- (instancetype)initWithTx:(DSTransaction *)tx
           protocolRequest:(DSPaymentProtocolRequest *)protocolRequest
                    amount:(uint64_t)amount
                       fee:(uint64_t)fee
                   address:(NSString *)address
                      name:(NSString *_Nullable)name
                      memo:(NSString *_Nullable)memo
                  isSecure:(BOOL)isSecure
             localCurrency:(NSString *_Nullable)localCurrency {
    self = [super init];
    if (self) {
        _tx = tx;
        _protocolRequest = protocolRequest;
        _amount = amount;
        _fee = fee;
        _address = address;
        _name = name;
        _memo = memo;
        _isSecure = isSecure;
        _localCurrency = localCurrency;
    }
    return self;
}

- (uint64_t)amountToDisplay {
    return self.amount - self.fee;
}

- (nullable NSString *)generalInfoString {
    BOOL hasInfo = NO;
    NSString *info = @"";
    if (self.name.length > 0) {
        if (self.isSecure) {
            info = LOCK @" ";
        }

        info = [info stringByAppendingString:sanitizeString(self.name)];
        hasInfo = YES;
    }

    if (self.memo.length > 0) {
        info = [info stringByAppendingFormat:@"\n%@", sanitizeString(self.memo)];
        hasInfo = YES;
    }

    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    if (self.localCurrency && ![self.localCurrency isEqualToString:priceManager.localCurrencyCode]) {
        NSString *requestedAmount = [[DSPriceManager sharedInstance] fiatCurrencyString:self.localCurrency forDashAmount:self.amount];
        info = [info stringByAppendingString:@"\n"];
        info = [info stringByAppendingFormat:NSLocalizedString(@"Local requested amount: %@", nil), requestedAmount];
        hasInfo = YES;
    }

    return hasInfo ? info : nil;
}

- (nullable NSAttributedString *)networkFeeAttributedString {
    if (self.fee > 0) {
        return [NSAttributedString dashAttributedStringForAmount:self.fee
                                                           color:[UIColor dw_secondaryTextColor]
                                                      symbolSize:DashSymbolInRowSize];
    }
    else {
        return nil;
    }
}

- (NSAttributedString *)totalAttributedString {
    return [NSAttributedString dashAttributedStringForAmount:self.amount
                                                       color:[UIColor dw_secondaryTextColor]
                                                  symbolSize:DashSymbolInRowSize];
}

@end

NS_ASSUME_NONNULL_END
