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
    return [self initWithTx:tx
                    protocolRequest:protocolRequest
                             amount:amount
                                fee:fee
                            address:address
                               name:name
                               memo:memo
                           isSecure:isSecure
                      localCurrency:localCurrency
                           userItem:userItem
               preparedStandardSend:nil
        broadcastAuthorizationState:DWPaymentOutputBroadcastAuthorizationStateNeedsAuthentication];
}

- (instancetype)initWithTx:(DSTransaction *)tx
                protocolRequest:(DSPaymentProtocolRequest *)protocolRequest
                         amount:(uint64_t)amount
                            fee:(uint64_t)fee
                        address:(NSString *)address
                           name:(NSString *_Nullable)name
                           memo:(NSString *_Nullable)memo
                       isSecure:(BOOL)isSecure
                  localCurrency:(NSString *_Nullable)localCurrency
                       userItem:(id<DWDPBasicUserItem>)userItem
           preparedStandardSend:(DWPreparedStandardSend *_Nullable)preparedStandardSend
    broadcastAuthorizationState:(DWPaymentOutputBroadcastAuthorizationState)broadcastAuthorizationState {
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
                   bip70Confirmation:(id)bip70Confirmation
                            userItem:(nullable id<DWDPBasicUserItem>)userItem {
    self = [super init];
    if (self) {
        _amount = amount;
        _fee = fee;
        _address = address;
        _name = merchantName;
        _memo = memo;
        _isSecure = isSecure;
        _userItem = userItem;
        _isMerchantRequest = YES;
        _bip70Confirmation = bip70Confirmation;
        // The tx is built later (inside confirmAndSend); auth is required at the Send tap.
        _broadcastAuthorizationState = DWPaymentOutputBroadcastAuthorizationStateNeedsAuthentication;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
