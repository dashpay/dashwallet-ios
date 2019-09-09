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

- (BOOL)isSent {
    return self.dataItem.isSent;
}

- (NSAttributedString *)dashAmountStringWithFont:(UIFont *)font {
    return [self.dataProvider dashAmountStringFrom:self.dataItem font:font];
}

- (NSString *)fiatAmountString {
    return self.dataItem.fiatAmount;
}

- (id<DWTitleDetailItem>)addressWithFont:(UIFont *)font {
    NSString *title = self.dataItem.isSent
                          ? NSLocalizedString(@"Sent to", nil)
                          : NSLocalizedString(@"Received from", nil);

    NSAttributedString *detail = [NSAttributedString dw_dashAddressAttributedString:self.dataItem.address
                                                                           withFont:font];
    DWTitleDetailCellModel *model =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_TruncatedSingleLine
                                                title:title
                                     attributedDetail:detail];
    return model;
}

- (nullable id<DWTitleDetailItem>)feeWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {
    const uint64_t feeValue = self.transaction.feeUsed;
    if (feeValue == 0) {
        return nil;
    }

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
    NSString *detail = [self.dataProvider dateForTransaction:self.transaction];
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

@end

NS_ASSUME_NONNULL_END
