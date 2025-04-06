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

#import "DWNotificationsFetchedDataSource.h"

#import "DWEnvironment.h"

@implementation DWNotificationsFetchedDataSource

- (instancetype)initWithIdentity:(DSIdentity *)identity
                       inContext:(NSManagedObjectContext *)context {
    self = [super initWithContext:context];
    if (self) {
        _identity = identity;
    }
    return self;
}

- (NSString *)entityName {
    return NSStringFromClass(DSFriendRequestEntity.class);
}

- (NSPredicate *)predicate {
    DSDashpayUserEntity *dashPayUser = [self.identity matchingDashpayUserInContext:self.context];
    return [NSPredicate predicateWithFormat:@"destinationContact == %@ || sourceContact == %@", dashPayUser, dashPayUser];
}

- (NSArray<NSSortDescriptor *> *)sortDescriptors {
    // reversed order, from old to new
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:YES];
    return @[ sortDescriptor ];
}

@end
