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

#import "DWPaymentOutput+DWView.h"

#import <DashSync/DashSync.h>
#import <UIKit/UIKit.h>

#import "DWTitleDetailCellModel.h"
#import "NSAttributedString+DWBuilder.h"

NS_ASSUME_NONNULL_BEGIN

#define LOCK @"\xF0\x9F\x94\x92" // unicode lock symbol U+1F512 (utf-8)

static NSString *sanitizeString(NSString *s) {
    NSMutableString *sane = [NSMutableString stringWithString:(s) ? s : @""];
    CFStringTransform((CFMutableStringRef)sane, NULL, kCFStringTransformToUnicodeName, NO);
    return sane;
}

@implementation DWPaymentOutput (DWView)

- (uint64_t)amountToDisplay {
    return self.amount - self.fee;
}

- (nullable id<DWTitleDetailItem>)generalInfo {
    NSString *detail = [self generalInfoString];
    if (detail == nil) {
        return nil;
    }

    DWTitleDetailCellModel *info =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_Default
                                                title:nil
                                          plainDetail:detail];

    return info;
}

- (id<DWTitleDetailItem>)addressWithFont:(UIFont *)font {
    NSString *title = NSLocalizedString(@"Pay to", nil);

    NSString *address = self.address;
    NSAttributedString *detail = [NSAttributedString dw_dashAddressAttributedString:self.address withFont:font];
    DWTitleDetailCellModel *model =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_TruncatedSingleLine
                                                title:title
                                     attributedDetail:detail];
    return model;
}

- (nullable id<DWTitleDetailItem>)feeWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {
    const uint64_t feeValue = self.fee;
    if (feeValue == 0) {
        return nil;
    }

    NSAttributedString *feeString = [NSAttributedString dw_dashAttributedStringForAmount:feeValue
                                                                               tintColor:tintColor
                                                                                    font:font];

    DWTitleDetailCellModel *fee =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_Default
                                                title:NSLocalizedString(@"Network fee", nil)
                                     attributedDetail:feeString];

    return fee;
}

- (id<DWTitleDetailItem>)totalWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {
    NSAttributedString *detail = [NSAttributedString dw_dashAttributedStringForAmount:self.amount
                                                                            tintColor:tintColor
                                                                                 font:font];
    DWTitleDetailCellModel *total =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_Default
                                                title:NSLocalizedString(@"Total", nil)
                                     attributedDetail:detail];
    return total;
}

- (BOOL)copyAddressToPasteboard {
    NSString *address = self.address;
    NSParameterAssert(address);
    if (!address) {
        return NO;
    }

    [UIPasteboard generalPasteboard].string = address;

    return YES;
}

#pragma mark - Private

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

@end

NS_ASSUME_NONNULL_END
