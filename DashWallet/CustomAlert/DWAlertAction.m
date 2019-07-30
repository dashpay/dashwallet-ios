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

#import "DWAlertAction+DWProtected.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWAlertAction

+ (instancetype)actionWithTitle:(nullable NSString *)title style:(DWAlertActionStyle)style handler:(void (^__nullable)(DWAlertAction *action))handler {
    return [[self alloc] initWithTitle:title style:style handler:handler];
}

- (instancetype)initWithTitle:(nullable NSString *)title style:(DWAlertActionStyle)style handler:(void (^__nullable)(DWAlertAction *action))handler {
    self = [super init];
    if (self) {
        _title = [title copy];
        _style = style;
        _handler = [handler copy];
        _enabled = YES;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
