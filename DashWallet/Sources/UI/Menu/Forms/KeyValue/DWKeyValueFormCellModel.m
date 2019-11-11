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

#import "DWKeyValueFormCellModel.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWKeyValueFormCellModel

- (instancetype)initWithTitle:(nullable NSString *)title valueText:(NSString *)valueText placeholderText:(NSString *)placeholderText actionText:(nonnull NSAttributedString *)actionText {
    self = [self initWithTitle:title valueText:valueText];
    if (self) {
        _placeholderText = placeholderText;
        _actionText = actionText;
    }
    return self;
}

- (instancetype)initWithTitle:(nullable NSString *)title valueText:(NSString *)valueText {
    self = [super initWithTitle:title];
    if (self) {
        _valueText = valueText;
    }
    return self;
}

- (instancetype)initWithTitle:(nullable NSString *)title {
    return [self initWithTitle:title valueText:@""];
}

@end

NS_ASSUME_NONNULL_END
