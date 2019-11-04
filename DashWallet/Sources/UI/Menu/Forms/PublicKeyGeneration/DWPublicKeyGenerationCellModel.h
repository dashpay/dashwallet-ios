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

#import "DWBaseFormCellModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPublicKeyGenerationCellModel : DWBaseFormCellModel

@property (strong, nonatomic) NSData *publicKeyData;
@property (assign, nonatomic) uint32_t keyIndex;

@property (nullable, copy, nonatomic) void (^didChangeValueBlock)(DWPublicKeyGenerationCellModel *cellModel);

- (instancetype)initWithTitle:(nullable NSString *)title publicKeyData:(NSData *)publicKeyData withIndex:(uint32_t)keyIndex NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
