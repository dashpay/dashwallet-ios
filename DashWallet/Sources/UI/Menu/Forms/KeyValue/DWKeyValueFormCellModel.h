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

@interface DWKeyValueFormCellModel : DWBaseFormCellModel

@property (readonly, nonatomic) NSString *placeholderText;
@property (copy, nonatomic) NSString *valueText;
@property (copy, nonatomic) NSAttributedString *actionText;
@property (nullable, copy, nonatomic) void (^didChangeValueBlock)(DWKeyValueFormCellModel *cellModel);
@property (nullable, copy, nonatomic) void (^actionBlock)(void);

- (instancetype)initWithTitle:(nullable NSString *)title valueText:(NSString *)valueText NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithTitle:(nullable NSString *)title valueText:(NSString *)valueText placeholderText:(NSString *)placeholderText actionText:(NSAttributedString *)actionText;

@end

NS_ASSUME_NONNULL_END
