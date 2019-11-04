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

#import "DWPublicKeyGenerationCellModel.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWPublicKeyGenerationCellModel

- (instancetype)initWithTitle:(nullable NSString *)title publicKeyData:(NSData *)publicKeyData withIndex:(uint32_t)keyIndex {
    self = [super initWithTitle:title];
    if (self) {
        _publicKeyData = publicKeyData;
        _keyIndex = keyIndex;
    }
    return self;
}

- (instancetype)initWithTitle:(nullable NSString *)title {
    return [self initWithTitle:title publicKeyData:[NSData data] withIndex:UINT32_MAX];
}

@end

NS_ASSUME_NONNULL_END
