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
#import <KVO-MVVM/KVONSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWSignPayloadModel : KVONSObject

@property (nonatomic, strong) NSString *collateralAddress;
@property (nonatomic, strong) NSString *payloadCollateralString;
@property (nonatomic, strong) NSString *unverifiedSignatureString;
@property (nonatomic, strong) NSString *instructionStringForCopying;
@property (nonatomic, strong) NSString *instructionStringForSigning;
@property (nonatomic, strong) NSString *instructionStringForPasting;
@property (nonatomic, strong) NSData *signature;

- (instancetype)initForCollateralAddress:(NSString *)collateralAddress withPayloadCollateralString:(NSString *)payloadCollateralString NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)verifySignature;

@end

NS_ASSUME_NONNULL_END
