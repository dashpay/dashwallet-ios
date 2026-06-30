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
#import "DWTitleDetailItem.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *sanitizeString(NSString *s) {
    NSMutableString *sane = [NSMutableString stringWithString:(s) ? s : @""];
    CFStringTransform((CFMutableStringRef)sane, NULL, kCFStringTransformToUnicodeName, NO);
    return sane;
}


@implementation DWPaymentOutput (DWView)

//- (id<DWTitleDetailItem> _Nullable)addressWith:(UIFont * _Nonnull)font tintColor:(UIColor * _Nonnull)tintColor {
//    return [self totalWith:font tintColor:tintColor];
//}
//
//- (id<DWTitleDetailItem> _Nullable)feeWith:(UIFont * _Nonnull)font tintColor:(UIColor * _Nonnull)tintColor {
//    return [self totalWith:font tintColor:tintColor];
//}
//
//- (id<DWTitleDetailItem> _Nonnull)totalWith:(UIFont * _Nonnull)font tintColor:(UIColor * _Nonnull)tintColor {
//    return [self totalWith:font tintColor:tintColor];
//}

- (BOOL)hasCommonName {
    return self.name != nil;
}

- (uint64_t)amountToDisplay {
    if (self.isMerchantRequest) {
        // BIP70 is fee-on-top: the merchant receives the full `amount` and the fee is charged on
        // top. Subtracting it would understate the headline (and underflow when amount < fee).
        return self.amount;
    }
    return self.amount - self.fee;
}

- (nullable id<DWTitleDetailItem>)nameInfo {
    NSString *name = [self nameString];
    if (name == nil) {
        return nil;
    }

    DWTitleDetailCellModel *model =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_Default
                                  plainCenteredDetail:name];

    return model;
}

- (nullable id<DWTitleDetailItem>)generalInfo {
    NSString *detail = [self generalInfoString];
    if (detail == nil) {
        return nil;
    }

    DWTitleDetailCellModel *model =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_Default
                               plainLeftAlignedDetail:detail];

    return model;
}

- (nullable id<DWTitleDetailItem>)addressWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {
    if (self.isMerchantRequest || self.protocolRequest.commonName) {
        // don't show "send to" for BIP70 payment requests
        return nil;
    }
    else {
        NSString *title = NSLocalizedString(@"Send to", nil);
        if (self.userItem) {
            DWTitleDetailCellModel *model = [[DWTitleDetailCellModel alloc] initWithTitle:title
                                                                                 userItem:self.userItem
                                                                             copyableData:self.address];
            return model;
        }
        else {
            NSString *address = self.address;
            NSAttributedString *detail = [NSAttributedString dw_dashAddressAttributedString:address withFont:font];
            DWTitleDetailCellModel *model =
                [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_TruncatedSingleLine
                                                        title:title
                                             attributedDetail:detail
                                                 copyableData:address];
            return model;
        }
    }
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
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_Default
                                                title:NSLocalizedString(@"Network fee", nil)
                                     attributedDetail:feeString];

    return fee;
}

- (id<DWTitleDetailItem>)totalWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {
    // For a fee-on-top BIP70 merchant request the true wallet debit is amount + fee; other paths
    // already carry the all-in amount, so leave them unchanged.
    const uint64_t totalValue = self.isMerchantRequest ? (self.amount + self.fee) : self.amount;
    NSAttributedString *detail = [NSAttributedString dw_dashAttributedStringForAmount:totalValue
                                                                            tintColor:tintColor
                                                                                 font:font];
    DWTitleDetailCellModel *total =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_Default
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

- (nullable NSString *)nameString {
    if (self.name.length > 0) {
        NSString *sanitizedName = sanitizeString(self.name);
        if (self.isSecure) {
            return [NSString stringWithFormat:@"🔒 %@", sanitizedName];
        }
        else {
            return sanitizedName;
        }
    }

    return nil;
}

- (nullable NSString *)generalInfoString {
    BOOL hasInfo = NO;
    NSString *info = @"";
    if (self.memo.length > 0) {
        info = sanitizeString(self.memo);
        hasInfo = YES;
    }

    if (self.localCurrency && ![self.localCurrency isEqualToString:DWApp.localCurrencyCode]) {
        NSString *requestedAmount = [CurrencyExchangerObjcWrapper fiatCurrencyString:self.localCurrency forDashAmount:self.amount];
        if (info.length > 0) {
            info = [info stringByAppendingString:@"\n"];
        }
        info = [info stringByAppendingFormat:NSLocalizedString(@"Local requested amount: %@", nil), requestedAmount];
        hasInfo = YES;
    }

    return hasInfo ? info : nil;
}

#if DASHPAY
- (BOOL)isAcceptContactRequestCheckboxVisible {
    if (self.userItem.blockchainIdentity == nil) {
        return NO;
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSBlockchainIdentity *blockchainIdentity = self.userItem.blockchainIdentity;
    return [myBlockchainIdentity friendshipStatusForRelationshipWithBlockchainIdentity:blockchainIdentity] == DSBlockchainIdentityFriendshipStatus_Incoming;
}

- (BOOL)isAcceptContactRequestCheckboxOn {
    return [DWGlobalOptions sharedInstance].confirmationAcceptContactRequestIsOn;
}

- (void)setIsAcceptContactRequestCheckboxOn:(BOOL)value {
    [DWGlobalOptions sharedInstance].confirmationAcceptContactRequestIsOn = value;
}
#endif

@end

NS_ASSUME_NONNULL_END
