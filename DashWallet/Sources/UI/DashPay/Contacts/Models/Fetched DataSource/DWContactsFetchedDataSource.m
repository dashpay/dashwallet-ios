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

#import "DWContactsFetchedDataSource.h"

#import "DWEnvironment.h"

@implementation DWContactsFetchedDataSource

- (instancetype)initWithIdentity:(DSIdentity *)identity
                       inContext:(NSManagedObjectContext *)context {
    self = [super initWithContext:context];
    if (self) {
        _identity = identity;
    }
    return self;
}

- (NSString *)entityName {
    return NSStringFromClass(DSDashpayUserEntity.class);
}

- (NSPredicate *)predicate {
    return [NSPredicate
        predicateWithFormat:
            @"ANY friends == %@",
            [self.identity matchingDashpayUserInContext:self.context]];
}

- (NSArray<NSSortDescriptor *> *)sortDescriptors {
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"associatedBlockchainIdentity.dashpayUsername.stringValue" ascending:YES];
    return @[ sortDescriptor ];
}

@end
