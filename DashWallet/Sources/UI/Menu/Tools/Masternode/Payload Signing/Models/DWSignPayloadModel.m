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

#import "DWSignPayloadModel.h"

@implementation DWSignPayloadModel

- (instancetype)initForCollateralAddress:(NSString *)collateralAddress withPayloadCollateralString:(NSString *)payloadCollateralString {
    self = [super init];
    if (self) {
        _collateralAddress = collateralAddress;
        _payloadCollateralString = payloadCollateralString;
    }
    return self;
}

- (void)setSignatureFromString:(NSString *)signatureString {
    self.signature = [[NSData alloc] initWithBase64EncodedString:signatureString options:0];
}


- (BOOL)verifySignature:(id)sender {
    DSECDSAKey *key = [DSECDSAKey keyRecoveredFromCompactSig:self.signature andMessageDigest:[self.payloadCollateralString magicDigest]];
    NSString *address = [key addressForChain:[DWEnvironment sharedInstance].currentChain];
    return [address isEqualToString:self.collateralAddress];
}


@end
