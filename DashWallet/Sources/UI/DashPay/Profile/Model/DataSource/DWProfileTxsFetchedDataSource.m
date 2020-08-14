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

#import "DWProfileTxsFetchedDataSource.h"

#import "DWEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWProfileTxsFetchedDataSource ()

@property (nullable, readonly, strong, nonatomic) DSFriendRequestEntity *meToFriend;
@property (nullable, readonly, strong, nonatomic) DSFriendRequestEntity *friendToMe;

@end

NS_ASSUME_NONNULL_END

@implementation DWProfileTxsFetchedDataSource

- (instancetype)initWithMeToFriendRequest:(DSFriendRequestEntity *)meToFriend
                        friendToMeRequest:(DSFriendRequestEntity *)friendToMe
                                inContext:(NSManagedObjectContext *)context {
    NSAssert(meToFriend || friendToMe, @"Either of requests should exist"); // otherwise FRC would return all DSTxOutputEntity due to empty predicate
    self = [super initWithContext:context];
    if (self) {
        _meToFriend = meToFriend;
        _friendToMe = friendToMe;
    }
    return self;
}

- (NSString *)entityName {
    return NSStringFromClass(DSTxOutputEntity.class);
}

- (NSPredicate *)predicate {
    NSPredicate *meToFriendPredicate = nil;
    NSPredicate *friendToMePredicate = nil;
    if (self.meToFriend != nil) {
        meToFriendPredicate = [NSPredicate predicateWithFormat:@"localAddress.derivationPath.friendRequest == %@", self.meToFriend];
    }
    if (self.friendToMe != nil) {
        friendToMePredicate = [NSPredicate predicateWithFormat:@"localAddress.derivationPath.friendRequest == %@", self.friendToMe];
    }

    NSPredicate *predicate = nil;
    if (meToFriendPredicate != nil && friendToMePredicate != nil) {
        predicate = [NSCompoundPredicate orPredicateWithSubpredicates:@[ meToFriendPredicate, friendToMePredicate ]];
    }
    else if (meToFriendPredicate != nil) {
        predicate = meToFriendPredicate;
    }
    else if (friendToMePredicate != nil) {
        predicate = friendToMePredicate;
    }
    NSParameterAssert(predicate);
    return predicate;
}

- (NSArray<NSSortDescriptor *> *)sortDescriptors {
    NSSortDescriptor *sortDescriptor1 = [[NSSortDescriptor alloc]
        initWithKey:@"transaction.transactionHash.blockHeight"
          ascending:NO];
    NSSortDescriptor *sortDescriptor2 = [[NSSortDescriptor alloc]
        initWithKey:@"transaction.transactionHash.timestamp"
          ascending:NO];
    return @[ sortDescriptor1, sortDescriptor2 ];
}

@end
