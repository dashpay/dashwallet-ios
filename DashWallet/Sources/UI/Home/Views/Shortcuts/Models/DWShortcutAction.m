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

#import "DWShortcutAction.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWShortcutAction

+ (instancetype)action:(DWShortcutActionType)type {
    return [[self alloc] initWithType:type enabled:YES];
}

+ (instancetype)action:(DWShortcutActionType)type enabled:(BOOL)enabled {
    return [[self alloc] initWithType:type enabled:enabled];
}

- (instancetype)initWithType:(DWShortcutActionType)type enabled:(BOOL)enabled {
    self = [super init];
    if (self) {
        _type = type;
        _enabled = enabled;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
