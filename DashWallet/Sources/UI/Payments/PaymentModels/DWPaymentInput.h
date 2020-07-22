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

#import <Foundation/Foundation.h>

#import "DWDPBasicUserItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DSPaymentRequest;
@class DSPaymentProtocolRequest;

typedef NS_ENUM(NSUInteger, DWPaymentInputSource) {
    DWPaymentInputSource_Pasteboard,
    DWPaymentInputSource_ScanQR,
    DWPaymentInputSource_NFC,
    DWPaymentInputSource_URL,
    DWPaymentInputSource_BlockchainUser,
};

@interface DWPaymentInput : NSObject

@property (readonly, nonatomic, assign) DWPaymentInputSource source;
@property (nullable, readonly, nonatomic, strong) DSPaymentRequest *request;
@property (nullable, readonly, nonatomic, strong) DSPaymentProtocolRequest *protocolRequest;
@property (nullable, readonly, nonatomic, strong) id<DWDPBasicUserItem> userItem;
@property (nonatomic, assign) BOOL canChangeAmount;

@property (nullable, readonly, nonatomic) NSString *userDetails;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
