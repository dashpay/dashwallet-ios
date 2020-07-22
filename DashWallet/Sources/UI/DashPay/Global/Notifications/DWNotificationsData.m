//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWNotificationsData.h"

@implementation DWNotificationsData

- (instancetype)initWithUnreadItems:(NSArray<id<DWDPBasicUserItem, DWDPNotificationItem>> *)unreadItems
                           oldItems:(NSArray<id<DWDPBasicUserItem, DWDPNotificationItem>> *)oldItems {
    NSParameterAssert(unreadItems);
    NSParameterAssert(oldItems);
    self = [super init];
    if (self) {
        _unreadItems = [unreadItems copy];
        _oldItems = [oldItems copy];
        _isEmpty = _unreadItems.count == 0 && _oldItems.count == 0;
    }
    return self;
}

- (instancetype)init {
    return [self initWithUnreadItems:@[] oldItems:@[]];
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    return [[self.class alloc] initWithUnreadItems:self.unreadItems oldItems:self.oldItems];
}

@end
