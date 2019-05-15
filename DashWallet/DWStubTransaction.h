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

#if SNAPSHOT

NS_ASSUME_NONNULL_BEGIN

@class DSShapeshiftEntity;

@interface DWStubTransaction : NSObject

@property (readonly, nonatomic, assign) UInt256 txHash;
@property (nonatomic, assign) uint32_t blockHeight;

@property (nonatomic, assign) BOOL instantSendReceived;

@property (nonatomic, assign) uint64_t received;
@property (nonatomic, assign) uint64_t sent;
@property (nonatomic, assign) uint64_t balance;
@property (nonatomic, assign) uint32_t confirms;

@property (nonatomic, assign) NSTimeInterval timestamp;

@property (nonatomic, assign) BOOL transactionIsValid;
@property (nonatomic, assign) BOOL transactionIsPending;
@property (nonatomic, assign) BOOL transactionIsVerified;
@property (nonatomic, assign) BOOL transactionOutputsAreLocked;
@property (nonatomic, assign) BOOL processAsAuthenticated;

// always nil
@property (nullable, readonly, nonatomic, strong) DSShapeshiftEntity * associatedShapeshift;

+ (NSArray *)stubTxs;

@end

NS_ASSUME_NONNULL_END

#endif /* SNAPSHOT */
