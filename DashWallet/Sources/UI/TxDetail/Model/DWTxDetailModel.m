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

- (NSAttributedString *)dashAmountStringWithFont:(UIFont *)font {
    return [self.dataProvider dashAmountStringFrom:self.dataItem font:font];
}

- (NSString *)fiatAmountString {
    return self.dataItem.fiatAmount;
}

- (NSUInteger)inputAddressesCount {
    if ([self shouldDisplayInputAddresses]) {
        return self.dataItem.inputSendAddresses.count;
    }
    else {
        return 0;
    }
}

- (NSUInteger)outputAddressesCount {
    return self.dataItem.outputReceiveAddresses.count;
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
    NSMutableArray<id<DWTitleDetailItem>> *models = [NSMutableArray array];
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

    if ([self shouldDisplayInputAddresses]) {
        NSSet<NSString *> *addresses = [NSSet setWithArray:self.dataItem.inputSendAddresses];
        NSString *firstAddress = addresses.anyObject;
        for (NSString *address in addresses) {
            NSAttributedString *detail = [NSAttributedString dw_dashAddressAttributedString:address
                                                                                   withFont:font];
            const BOOL hasTitle = address == firstAddress;
            DWTitleDetailCellModel *model =
                [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_TruncatedSingleLine
                                                        title:hasTitle ? title : @""
                                             attributedDetail:detail
                                                 copyableData:address];
            [models addObject:model];
        }
    }

    return [models copy];
}

- (NSArray<id<DWTitleDetailItem>> *)outputAddressesWithFont:(UIFont *)font {
    NSMutableArray<id<DWTitleDetailItem>> *models = [NSMutableArray array];
    NSString *title;
    switch (self.dataItem.direction) {
        case DSTransactionDirection_Sent:
            title = NSLocalizedString(@"Sent to", nil);
            break;
        case DSTransactionDirection_Received:
            title = NSLocalizedString(@"Received at", nil);
            break;
        case DSTransactionDirection_Moved:
            title = NSLocalizedString(@"Moved internally to", nil);
            break;
        case DSTransactionDirection_NotAccountFunds:
            title = @""; //this should not be possible
            break;
    }

    NSArray<NSString *> *addresses = self.dataItem.outputReceiveAddresses;
    NSString *firstAddress = addresses.firstObject;
    for (NSString *address in addresses) {
        NSAttributedString *detail = [NSAttributedString dw_dashAddressAttributedString:address
                                                                               withFont:font];
        const BOOL hasTitle = address == firstAddress;
        DWTitleDetailCellModel *model =
            [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_TruncatedSingleLine
                                                    title:hasTitle ? title : @""
                                         attributedDetail:detail
                                             copyableData:address];
        [models addObject:model];
    }

    return [models copy];
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
            [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_TruncatedSingleLine
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

    DWTitleDetailCellModel *model = [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_Default
                                                                            title:title
                                                                 attributedDetail:detail];
    return model;
}

- (id<DWTitleDetailItem>)date {
    NSString *title = NSLocalizedString(@"Date", nil);
    NSString *detail = [self.dataProvider longDateStringForTransaction:self.transaction];
    DWTitleDetailCellModel *model = [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_Default
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

- (BOOL)shouldDisplayInputAddresses {
    return [self.transaction isKindOfClass:[DSCoinbaseTransaction class]] || self.dataItem.direction != DSTransactionDirection_Received;
}

@end

NS_ASSUME_NONNULL_END
