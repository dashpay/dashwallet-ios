//
//  Created by Sam Westrich
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

@interface DWMasternodeRegistrationModel : NSObject

@property (nonatomic, strong) NSData *ownerPublicKeyData;
@property (nonatomic, strong) NSData *operatorPublicKeyData;
@property (nonatomic, strong) NSData *votingPublicKeyData;

@property (nonatomic, assign) uint32_t ownerPublicKeyIndex;
@property (nonatomic, assign) uint32_t operatorPublicKeyIndex;
@property (nonatomic, assign) uint32_t votingPublicKeyIndex;

@property (nonatomic, assign) NSString *ipAddress;
@property (nonatomic, assign) uint16_t port;

@property (nonatomic, strong) NSData *collateralTransactionHashData;
@property (nonatomic, assign) uint16_t collateralIndex;

@property (nonatomic, strong) NSString *payoutAddress;

- (instancetype)initForWallet:(DSWallet *)wallet NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
