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

NS_ASSUME_NONNULL_BEGIN

@class UIImage;
@class DSPaymentRequest;

@interface DWReceiveModel : NSObject

@property (nullable, readonly, nonatomic, strong) UIImage *qrCodeImage;
@property (nullable, readonly, nonatomic, copy) NSString *paymentAddress;
@property (readonly, nonatomic, assign) CGSize qrCodeSize;
@property (readonly, nonatomic, assign) uint64_t amount;

- (NSString *)paymentAddressOrRequestToShare;

- (void)copyAddressToPasteboard;
- (void)copyQRImageToPasteboard;

- (nullable NSString *)requestAmountReceivedInfoIfReceived;

- (instancetype)initWithAmount:(uint64_t)amount;

@end

NS_ASSUME_NONNULL_END
