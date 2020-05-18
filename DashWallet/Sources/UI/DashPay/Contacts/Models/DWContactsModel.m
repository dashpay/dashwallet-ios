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

#import "DWContactsModel.h"

#import "DWContactObject.h"
#import "DWContactsDataSourceObject.h"
#import "DWEnvironment.h"
#import "DWFetchedResultsDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsModel () <DWFetchedResultsDataSourceDelegate>

@property (nonatomic, strong) DWFetchedResultsDataSource *incomingDataSource;
@property (nonatomic, strong) DWFetchedResultsDataSource *contactsDataSource;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsModel

- (instancetype)init {
    self = [super init];
    if (self) {
        [self rebuildDataSources];
    }
    return self;
}

- (void)rebuildDataSources {
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    if (!blockchainIdentity) {
        return;
    }

    NSManagedObjectContext *context = [NSManagedObject context];

    _incomingDataSource = [[DWFetchedResultsDataSource alloc]
                       initWithContext:context
                            entityName:NSStringFromClass(DSFriendRequestEntity.class)
        shouldSubscribeToNotifications:YES];
    _incomingDataSource.delegate = self;
    _incomingDataSource.predicate = [NSPredicate
        predicateWithFormat:
            @"destinationContact == %@ && (SUBQUERY(destinationContact.outgoingRequests, $friendRequest, $friendRequest.destinationContact == SELF.sourceContact).@count == 0)",
            [blockchainIdentity matchingDashpayUserInContext:context]];
    _incomingDataSource.invertedPredicate = [NSPredicate
        predicateWithFormat:
            @"sourceContact == %@ && (SUBQUERY(sourceContact.incomingRequests, $friendRequest, $friendRequest.sourceContact == SELF.destinationContact).@count > 0)",
            [blockchainIdentity matchingDashpayUserInContext:context]];
    NSSortDescriptor *incomingSortDescriptor = [[NSSortDescriptor alloc]
        initWithKey:@"sourceContact.associatedBlockchainIdentity.dashpayUsername.stringValue"
          ascending:YES];
    _incomingDataSource.sortDescriptors = @[ incomingSortDescriptor ];

    _contactsDataSource = [[DWFetchedResultsDataSource alloc]
                       initWithContext:context
                            entityName:NSStringFromClass(DSDashpayUserEntity.class)
        shouldSubscribeToNotifications:YES];
    _contactsDataSource.delegate = self;
    _contactsDataSource.predicate = [NSPredicate
        predicateWithFormat:
            @"ANY friends == %@",
            [blockchainIdentity matchingDashpayUserInContext:context]];
    NSSortDescriptor *contactsSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"associatedBlockchainIdentity.dashpayUsername.stringValue" ascending:YES];
    _contactsDataSource.sortDescriptors = @[ contactsSortDescriptor ];
    _contactsDataSource.indexPathTransformation = ^NSIndexPath *_Nonnull(NSIndexPath *_Nonnull indexPath) {
        return [NSIndexPath indexPathForRow:indexPath.row inSection:1];
    };
}

- (void)start {
    [self.incomingDataSource start];
    [self.contactsDataSource start];
}

- (void)stop {
    [self.incomingDataSource stop];
    [self.contactsDataSource stop];
}

#pragma mark - DWFetchedResultsDataSourceDelegate

- (void)fetchedResultsDataSourceDidUpdate:(DWFetchedResultsDataSource *)fetchedResultsDataSource {
}

- (void)fetchedResultsDataSource:(DWFetchedResultsDataSource *)fetchedResultsDataSource
                   didDiffUpdate:(DWFetchedResultsDataSourceDiffUpdate *)diffUpdate {
}

@end
