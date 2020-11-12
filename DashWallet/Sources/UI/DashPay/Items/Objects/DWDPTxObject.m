//
//  Created by Andrew Podkovyrin
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

#import "DWDPTxObject.h"

#import "DWTransactionListDataProviderProtocol.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWDPItem.h"

#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWDPTxObject ()

@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;
@property (readonly, nonatomic, strong) id<DWTransactionListDataItem> dataItem;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPTxObject

@synthesize displayName = _displayName;
@synthesize subtitle = _subtitle;
@synthesize username = _username;
@synthesize transaction = _transaction;
@synthesize blockchainIdentity = _blockchainIdentity;

- (instancetype)initWithTransaction:(DSTransaction *)tx
                       dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider
                 blockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self = [super init];
    if (self) {
        _transaction = tx;
        _dataProvider = dataProvider;
        _blockchainIdentity = blockchainIdentity;
        _username = blockchainIdentity.currentDashpayUsername;
        // TODO: DP provide Display Name
        _subtitle = [dataProvider shortDateStringForTransaction:tx];
        _dataItem = [dataProvider transactionDataForTransaction:tx];
    }
    return self;
}

- (NSAttributedString *)title {
    NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName : [UIFont dw_itemTitleFont]};
    return [[NSAttributedString alloc] initWithString:self.dataItem.directionText attributes:attributes];
}

- (NSAttributedString *)amountString {
    UIFont *titleFont = [UIFont dw_itemTitleFont];
    UIFont *subtitleFont = [UIFont dw_itemSubtitleFont];

    NSAttributedString *dashAmountString = [self.dataProvider dashAmountStringFrom:self.dataItem font:titleFont];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.maximumLineHeight = 4.0;
    NSAttributedString *spacingString = [[NSAttributedString alloc] initWithString:@"\n\n"
                                                                        attributes:@{NSParagraphStyleAttributeName : style}];

    NSAttributedString *fiatString = [[NSAttributedString alloc] initWithString:self.dataItem.fiatAmount
                                                                     attributes:@{
                                                                         NSFontAttributeName : subtitleFont,
                                                                         NSForegroundColorAttributeName : [UIColor dw_tertiaryTextColor],
                                                                     }];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];
    [result appendAttributedString:dashAmountString];
    [result appendAttributedString:spacingString];
    [result appendAttributedString:fiatString];
    [result endEditing];
    return [result copy];
}

@end
