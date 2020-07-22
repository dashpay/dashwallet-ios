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

NS_ASSUME_NONNULL_BEGIN

@implementation DWPaymentOutput

- (instancetype)initWithTx:(DSTransaction *)tx
           protocolRequest:(DSPaymentProtocolRequest *)protocolRequest
                    amount:(uint64_t)amount
                       fee:(uint64_t)fee
                   address:(NSString *)address
                      name:(NSString *_Nullable)name
                      memo:(NSString *_Nullable)memo
                  isSecure:(BOOL)isSecure
             localCurrency:(NSString *_Nullable)localCurrency
                  userItem:(id<DWDPBasicUserItem>)userItem {
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
        _userItem = userItem;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
