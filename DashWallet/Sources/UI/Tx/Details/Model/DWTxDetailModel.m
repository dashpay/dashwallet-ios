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

#import "DWTxDetailModel.h"

#import <DashSync/DashSync.h>

#import "DWDPUserObject.h"
#import "DWEnvironment.h"
#import "DWTitleDetailCellModel.h"
#import "DWTransactionListDataSource+DWProtected.h"
#import "NSAttributedString+DWBuilder.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTxDetailModel ()

@property (nonatomic, copy) NSString *transactionId;

@property (readonly, nullable, nonatomic, weak) id<DWTransactionListDataProviderProtocol> dataProvider;
@property (readonly, nonatomic, strong) id<DWTransactionListDataItem> dataItem;

@end

@implementation DWTxDetailModel

- (instancetype)initWithTransaction:(DSTransaction *)transaction
                       dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super init];
    if (self) {
        _transaction = transaction;
        _dataProvider = dataProvider;
        _dataItem = [dataProvider transactionDataForTransaction:transaction];
    }
    return self;
}

- (NSString *)transactionId {
    if (_transactionId == nil) {
        NSData *txIdData = [NSData dataWithBytes:self.transaction.txHash.u8 length:sizeof(UInt256)].reverse;
        _transactionId = [NSString hexWithData:txIdData];
    }

    return _transactionId;
}

- (DSTransactionDirection)direction {
    return self.dataItem.direction;
}

- (NSString *)dashAmountString {
    return [self.dataProvider dashAmountStringFrom:self.dataItem];
}

- (NSAttributedString *)dashAmountStringWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {

    NSNumberFormatter *dashFormat = [NSNumberFormatter new];
    dashFormat.locale = [NSLocale localeWithLocaleIdentifier:@"ru_RU"];
    dashFormat.lenient = YES;
    dashFormat.numberStyle = NSNumberFormatterCurrencyStyle;
    dashFormat.generatesDecimalNumbers = YES;
    NSRange positiveFormatRange = [dashFormat.positiveFormat rangeOfString:@"#"];
    if (positiveFormatRange.location != NSNotFound) {
        dashFormat.negativeFormat = [dashFormat.positiveFormat
            stringByReplacingCharactersInRange:positiveFormatRange
                                    withString:@"-#"];
    }
    dashFormat.currencyCode = @"DASH";
    dashFormat.currencySymbol = DASH;

    dashFormat.maximumFractionDigits = 8;
    dashFormat.minimumFractionDigits = 0; // iOS 8 bug, minimumFractionDigits now has to be set after currencySymbol
    dashFormat.maximum = @(MAX_MONEY / (int64_t)pow(10.0, dashFormat.maximumFractionDigits));


    const uint64_t dashAmount = self.dataItem.dashAmount;

    // NSNumberFormatter *numberFormatter = [DSPriceManager sharedInstance].dashFormat;

    NSNumber *number = [(id)[NSDecimalNumber numberWithLongLong:dashAmount]
        decimalNumberByMultiplyingByPowerOf10:-dashFormat.maximumFractionDigits];
    NSString *formattedNumber = [dashFormat stringFromNumber:number];
    NSString *symbol = self.dataItem.directionSymbol;
    NSString *amount = [symbol stringByAppendingString:formattedNumber];

    return [NSAttributedString dw_dashAttributedStringForFormattedAmount:amount tintColor:tintColor font:font];
}

- (NSAttributedString *)dashAmountStringWithFont:(UIFont *)font {
    return [self.dataProvider dashAmountStringFrom:self.dataItem font:font];
}

- (NSString *)fiatAmountString {
    return self.dataItem.fiatAmount;
}

- (NSUInteger)inputAddressesCount {
    if ([self shouldDisplayInputAddresses]) {
        if ([self hasSourceUser]) {
            return 1;
        }
        else {
            return self.dataItem.inputSendAddresses.count;
        }
    }
    else {
        return 0;
    }
}

- (NSUInteger)outputAddressesCount {
    if ([self shouldDisplayOutputAddresses]) {
        if ([self hasDestinationUser]) {
            return 1;
        }
        else {
            return self.dataItem.outputReceiveAddresses.count;
        }
    }
    else {
        return 0;
    }
}

- (NSUInteger)specialInfoCount {
    return self.dataItem.specialInfoAddresses.count;
}

- (BOOL)hasFee {
    if (self.direction == DSTransactionDirection_Received) {
        return NO;
    }

    const uint64_t feeValue = self.transaction.feeUsed;
    if (feeValue == 0) {
        return NO;
    }

    return YES;
}

- (BOOL)hasDate {
    return YES;
}

- (NSArray<id<DWTitleDetailItem>> *)inputAddressesWithFont:(UIFont *)font {
    if (![self shouldDisplayInputAddresses]) {
        return @[];
    }

    NSString *title;
    switch (self.dataItem.direction) {
        case DSTransactionDirection_Sent:
            title = NSLocalizedString(@"Sent from", nil);
            break;
        case DSTransactionDirection_Received:
            title = NSLocalizedString(@"Received from", nil);
            break;
        case DSTransactionDirection_Moved:
            title = NSLocalizedString(@"Moved from", nil);
            break;
        case DSTransactionDirection_NotAccountFunds:
            title = NSLocalizedString(@"Registered from", nil);
            break;
    }

    if ([self hasSourceUser]) {
        return [self sourceUsersWithTitle:title font:font];
    }
    else {
        return [self plainInputAddressesWithTitle:title font:font];
    }
}

- (NSArray<id<DWTitleDetailItem>> *)outputAddressesWithFont:(UIFont *)font {
    if (![self shouldDisplayOutputAddresses]) {
        return @[];
    }

    NSString *title;
    switch (self.dataItem.direction) {
        case DSTransactionDirection_Sent:
            title = NSLocalizedString(@"Sent to", nil);
            break;
        case DSTransactionDirection_Received:
            title = NSLocalizedString(@"Received at", nil);
            break;
        case DSTransactionDirection_Moved:
            title = NSLocalizedString(@"Internally moved to", nil);
            break;
        case DSTransactionDirection_NotAccountFunds:
            title = @""; // this should not be possible
            break;
    }

    if ([self hasDestinationUser]) {
        return [self destinationUsersWithTitle:title font:font];
    }
    else {
        return [self plainOutputAddressesWithTitle:title font:font];
    }
}

- (NSArray<id<DWTitleDetailItem>> *)specialInfoWithFont:(UIFont *)font {
    NSMutableArray<id<DWTitleDetailItem>> *models = [NSMutableArray array];


    NSDictionary<NSString *, NSNumber *> *addresses = self.dataItem.specialInfoAddresses;
    for (NSString *address in addresses) {
        NSAttributedString *detail = [NSAttributedString dw_dashAddressAttributedString:address
                                                                               withFont:font];
        NSInteger type = [addresses[address] integerValue];
        NSString *title;
        switch (type) {
            case 0:
                title = NSLocalizedString(@"Owner Address", nil);
                break;
            case 1:
                title = NSLocalizedString(@"Provider Address", nil);
                break;
            case 2:
                title = NSLocalizedString(@"Voting Address", nil);
                break;
            default:
                title = @"";
                break;
        }
        DWTitleDetailCellModel *model =
            [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_TruncatedSingleLine
                                                    title:title
                                         attributedDetail:detail
                                             copyableData:address];
        [models addObject:model];
    }

    return [models copy];
}

- (nullable id<DWTitleDetailItem>)feeWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {
    if (![self hasFee]) {
        return nil;
    }

    const uint64_t feeValue = self.transaction.feeUsed;
    NSString *title = NSLocalizedString(@"Network fee", nil);
    NSAttributedString *detail = [NSAttributedString dw_dashAttributedStringForAmount:feeValue
                                                                            tintColor:tintColor
                                                                                 font:font];

    DWTitleDetailCellModel *model = [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_Default
                                                                            title:title
                                                                 attributedDetail:detail];
    return model;
}

- (id<DWTitleDetailItem>)date {
    NSString *title = NSLocalizedString(@"Date", nil);
    NSString *detail = [self.dataProvider longDateStringForTransaction:self.transaction];
    DWTitleDetailCellModel *model = [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_Default
                                                                            title:title
                                                                      plainDetail:detail];
    return model;
}

- (nullable NSURL *)explorerURL {
    if ([[DWEnvironment sharedInstance].currentChain isTestnet]) {
        NSString *urlString = [NSString stringWithFormat:@"https://testnet-insight.dashevo.org/insight/tx/%@",
                                                         self.transactionId];
        return [NSURL URLWithString:urlString];
    }
    else if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
        NSString *urlString = [NSString stringWithFormat:@"https://insight.dashevo.org/insight/tx/%@",
                                                         self.transactionId];
        return [NSURL URLWithString:urlString];
    }
    return nil;
}

- (BOOL)copyTransactionIdToPasteboard {
    NSString *transactionId = self.transactionId;
    NSParameterAssert(transactionId);
    if (!transactionId) {
        return NO;
    }

    [UIPasteboard generalPasteboard].string = transactionId;

    return YES;
}

#pragma mark - Private

- (NSArray<id<DWTitleDetailItem>> *)plainInputAddressesWithTitle:(NSString *)title font:(UIFont *)font {
    NSMutableArray<id<DWTitleDetailItem>> *models = [NSMutableArray array];
    NSSet<NSString *> *addresses = [NSSet setWithArray:self.dataItem.inputSendAddresses];
    NSString *firstAddress = addresses.anyObject;
    for (NSString *address in addresses) {
        NSAttributedString *detail = [NSAttributedString dw_dashAddressAttributedString:address
                                                                               withFont:font
                                                                            showingLogo:NO];
        const BOOL hasTitle = address == firstAddress;
        DWTitleDetailCellModel *model =
            [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_TruncatedSingleLine
                                                    title:hasTitle ? title : @""
                                         attributedDetail:detail
                                             copyableData:address];
        [models addObject:model];
    }
    return [models copy];
}

- (NSArray *)plainOutputAddressesWithTitle:(NSString *)title font:(UIFont *)font {
    NSMutableArray<id<DWTitleDetailItem>> *models = [NSMutableArray array];
    NSArray<NSString *> *addresses = self.dataItem.outputReceiveAddresses;
    NSString *firstAddress = addresses.firstObject;
    for (NSString *address in addresses) {
        NSAttributedString *detail = [NSAttributedString dw_dashAddressAttributedString:address
                                                                               withFont:font
                                                                            showingLogo:NO];
        const BOOL hasTitle = address == firstAddress;
        DWTitleDetailCellModel *model =
            [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItemStyle_TruncatedSingleLine
                                                    title:hasTitle ? title : @""
                                         attributedDetail:detail
                                             copyableData:address];
        [models addObject:model];
    }
    return [models copy];
}

- (NSArray<id<DWTitleDetailItem>> *)sourceUsersWithTitle:(NSString *)title font:(UIFont *)font {
    DSBlockchainIdentity *blockchainIdentity = self.transaction.sourceBlockchainIdentities.anyObject;
    if (blockchainIdentity) {
        DWDPUserObject *user = [[DWDPUserObject alloc] initWithBlockchainIdentity:blockchainIdentity];
        DWTitleDetailCellModel *model = [[DWTitleDetailCellModel alloc] initWithTitle:title userItem:user copyableData:nil];
        return @[ model ];
    }
    else {
        return @[];
    }
}

- (NSArray<id<DWTitleDetailItem>> *)destinationUsersWithTitle:(NSString *)title font:(UIFont *)font {
    DSBlockchainIdentity *blockchainIdentity = self.transaction.destinationBlockchainIdentities.anyObject;
    if (blockchainIdentity) {
        DWDPUserObject *user = [[DWDPUserObject alloc] initWithBlockchainIdentity:blockchainIdentity];
        DWTitleDetailCellModel *model = [[DWTitleDetailCellModel alloc] initWithTitle:title userItem:user copyableData:nil];
        return @[ model ];
    }
    else {
        return @[];
    }
}

- (BOOL)hasSourceUser {
    return self.transaction.sourceBlockchainIdentities.count > 0;
}

- (BOOL)hasDestinationUser {
    return self.transaction.destinationBlockchainIdentities.count > 0;
}

- (BOOL)shouldDisplayInputAddresses {
    if ([self hasSourceUser]) {
        // Don't show item "Sent from <my username>"
        if (self.dataItem.direction == DSTransactionDirection_Sent) {
            return NO;
        }
        else {
            return YES;
        }
    }
    return [self.transaction isKindOfClass:[DSCoinbaseTransaction class]] || self.dataItem.direction != DSTransactionDirection_Received;
}

- (BOOL)shouldDisplayOutputAddresses {
    if (self.dataItem.direction == DSTransactionDirection_Received && [self hasDestinationUser]) {
        return NO;
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
