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

#import "DWUpholdSuccessTransferModel.h"

#import "DWUpholdTransactionObject.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const UPHOLD_TRANSACTION_URL_FORMAT = @"https://sandbox.uphold.com/reserve/transactions/%@";

@interface DWUpholdSuccessTransferModel ()

@property (strong, nonatomic) DWUpholdTransactionObject *transaction;

@end

@implementation DWUpholdSuccessTransferModel

- (instancetype)initWithTransaction:(DWUpholdTransactionObject *)transaction {
    self = [super init];
    if (self) {
        _transaction = transaction;
    }
    return self;
}

- (NSString *)transactionText {
    return [NSString stringWithFormat:@"%@: %@",
                                      NSLocalizedString(@"Transaction id", nil),
                                      self.transaction.identifier];
}

- (NSURL *)transactionURL {
    NSString *urlString = [NSString stringWithFormat:UPHOLD_TRANSACTION_URL_FORMAT, self.transaction.identifier];
    NSURL *url = [NSURL URLWithString:urlString];
    NSParameterAssert(url);

    return url;
}

@end

NS_ASSUME_NONNULL_END
