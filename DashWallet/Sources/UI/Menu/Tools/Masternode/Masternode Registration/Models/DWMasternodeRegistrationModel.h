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

@property (nonatomic, strong) DSECDSAKey *ownerKey;
@property (nonatomic, strong) DSBLSKey *operatorKey;
@property (nonatomic, strong) DSECDSAKey *votingKey;

@property (nonatomic, assign) uint32_t ownerKeyIndex;
@property (nonatomic, assign) uint32_t operatorKeyIndex;
@property (nonatomic, assign) uint32_t votingKeyIndex;

@property (nonatomic, assign) UInt128 ipAddress;
@property (nonatomic, assign) uint16_t port;

@property (nonatomic, assign) DSUTXO collateral;

@property (nonatomic, readonly) DSTransaction *collateralTransaction;
@property (nonatomic, readonly) DSProviderRegistrationTransaction *providerRegistrationTransaction;

@property (nonatomic, strong) NSString *payoutAddress;

- (instancetype)initForAccount:(DSAccount *)account NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)registerMasternode:(id)sender requestsPayloadSigning:(void (^_Nullable)(void))payloadSigningRequest completion:(void (^_Nullable)(NSError *error))completion;

- (void)signTransactionInputs:(DSProviderRegistrationTransaction *)providerRegistrationTransaction completion:(void (^_Nullable)(NSError *error))completion;

- (void)lookupIndexesForCollateralHash:(UInt256)collateralHash completion:(void (^_Nullable)(DSTransaction *transaction, NSIndexSet *indexSet, NSError *error))completion;

- (void)setIpAddressFromString:(NSString *)ipAddressString;

- (void)findCollateralTransactionWithCompletion:(void (^_Nullable)(NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
