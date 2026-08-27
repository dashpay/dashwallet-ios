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

- (instancetype)initWithAddress:(NSString *)address
                         amount:(uint64_t)amount
                            fee:(uint64_t)fee
                           name:(NSString *_Nullable)name
                           memo:(NSString *_Nullable)memo
                       isSecure:(BOOL)isSecure
                  localCurrency:(NSString *_Nullable)localCurrency
           preparedStandardSend:(DWPreparedStandardSend *_Nullable)preparedStandardSend
    broadcastAuthorizationState:(DWPaymentOutputBroadcastAuthorizationState)broadcastAuthorizationState {
    self = [super init];
    if (self) {
        _address = address;
        _amount = amount;
        _fee = fee;
        _name = name;
        _memo = memo;
        _isSecure = isSecure;
        _localCurrency = localCurrency;
        _preparedStandardSend = preparedStandardSend;
        _broadcastAuthorizationState = broadcastAuthorizationState;
    }
    return self;
}

- (instancetype)initWithMerchantName:(nullable NSString *)merchantName
                            isSecure:(BOOL)isSecure
                              amount:(uint64_t)amount
                                 fee:(uint64_t)fee
                             address:(NSString *)address
                                memo:(nullable NSString *)memo
                   bip70Confirmation:(id)bip70Confirmation {
    self = [super init];
    if (self) {
        _amount = amount;
        _fee = fee;
        _address = address;
        _name = merchantName;
        _memo = memo;
        _isSecure = isSecure;
        _isMerchantRequest = YES;
        _bip70Confirmation = bip70Confirmation;
        // The tx is built later (inside confirmAndSend); auth is required at the Send tap.
        _broadcastAuthorizationState = DWPaymentOutputBroadcastAuthorizationStateNeedsAuthentication;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
