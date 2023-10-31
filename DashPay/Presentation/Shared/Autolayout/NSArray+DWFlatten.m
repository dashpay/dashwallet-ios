//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "NSArray+DWFlatten.h"

@implementation NSArray (DWFlatten)

- (NSArray *)dw_flatten {
    BOOL needsFlatten = ^{
        for (id object in self)
            if ([object respondsToSelector:@selector(dw_flatten)])
                return YES;
        return NO;
    }();

    if (!needsFlatten) {
        return self;
    }

    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:self.count];
    for (id object in self) {
        if ([object respondsToSelector:@selector(dw_flatten)]) {
            [arr addObjectsFromArray:[object dw_flatten]];
        }
        else {
            [arr addObject:object];
        }
    }

    return arr;
}

@end
