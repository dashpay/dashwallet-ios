//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWTextFieldFormCellModel.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWTextFieldFormValidationResult

- (instancetype)initWithInfo:(NSString *)info {
    self = [super init];
    if (self) {
        _info = info;
    }
    return self;
}

- (instancetype)initWithError:(NSString *)info {
    self = [super init];
    if (self) {
        _info = info;
        _errored = YES;
    }
    return self;
}


@end

@implementation DWTextFieldFormCellModel

- (instancetype)initWithTitle:(nullable NSString *)title placeholder:(nullable NSString *)placeholder {
    self = [super initWithTitle:title];
    if (self) {
        _placeholder = [placeholder copy];
    }
    return self;
}

- (instancetype)initWithTitle:(nullable NSString *)title {
    return [self initWithTitle:title placeholder:nil];
}

- (BOOL)validateReplacementString:(NSString *)string text:(nullable NSString *)text {
    return YES;
}

- (DWTextFieldFormValidationResult *)postValidate {
    return [[DWTextFieldFormValidationResult alloc] initWithInfo:@""];
}

@end

NS_ASSUME_NONNULL_END
