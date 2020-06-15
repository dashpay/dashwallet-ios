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

#import "DWNotificationsProvider.h"

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWNotificationsData.h"
#import "DWNotificationsFetchedDataSource.h"

#import "DWDPIgnoredRequestNotificationObject.h"
#import "DWDPIncomingRequestNotificationObject.h"
#import "DWDPOutgoingRequestNotificationObject.h"


NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWNotificationsProviderDidUpdateNotification = @"org.dash.wallet.dp.notifications-did-update";

@interface DWNotificationsProvider () <DWFetchedResultsDataSourceDelegate, NSFetchedResultsControllerDelegate>

@property (nonatomic, strong) DWFetchedResultsDataSource *fetchedDataSource;
@property (nonatomic, copy) DWNotificationsData *data;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsProvider

+ (instancetype)sharedInstance {
    static DWNotificationsProvider *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _data = [[DWNotificationsData alloc] init];
    }
    return self;
}

- (void)setupIfNeeded {
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    if (!blockchainIdentity) {
        return;
    }

    NSManagedObjectContext *context = [NSManagedObjectContext viewContext];

    _fetchedDataSource = [[DWNotificationsFetchedDataSource alloc] initWithContext:context];
    _fetchedDataSource.shouldSubscribeToNotifications = YES;
    _fetchedDataSource.delegate = self;
    [_fetchedDataSource start];
    _fetchedDataSource.fetchedResultsController.delegate = self;

    [self reload];
}

#pragma mark - Private

- (void)reload {
    NSArray<DSFriendRequestEntity *> *fetchedObjects = self.fetchedDataSource.fetchedResultsController.fetchedObjects;

    NSMutableDictionary<NSManagedObjectID *, NSMutableSet<NSManagedObjectID *> *> *connections =
        [NSMutableDictionary dictionary];
    for (DSFriendRequestEntity *request in fetchedObjects) {
        NSManagedObjectID *sourceID = request.sourceContact.objectID;
        NSMutableSet<NSManagedObjectID *> *sourceConnections = connections[sourceID];
        if (sourceConnections == nil) {
            sourceConnections = [NSMutableSet set];
            connections[sourceID] = sourceConnections;
        }
        [sourceConnections addObject:request.destinationContact.objectID];
    }

    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    NSManagedObjectID *userID = blockchainIdentity.matchingDashpayUser.objectID;

    const NSTimeInterval mostRecentTimestamp = [[DWGlobalOptions sharedInstance].mostRecentViewedNotificationDate
                                                    timeIntervalSince1970];
    NSMutableArray<id<DWDPBasicItem>> *newItems = [NSMutableArray array];
    NSMutableArray<id<DWDPBasicItem>> *oldItems = [NSMutableArray array];

    for (DSFriendRequestEntity *request in fetchedObjects) {
        NSManagedObjectID *sourceID = request.sourceContact.objectID;
        NSSet<NSManagedObjectID *> *destinationConnections = connections[request.destinationContact.objectID];
        const BOOL hasInvertedConnection = [destinationConnections containsObject:sourceID];
        const BOOL isNew = request.timestamp > mostRecentTimestamp;
        NSMutableArray<id<DWDPBasicItem>> *items = isNew ? newItems : oldItems;

        NSString *from = request.sourceContact.username;
        NSString *to = request.destinationContact.username;

        if ([sourceID isEqual:userID]) { // outoging
            // if it's a friendship (order of incoming / outgoing does not matter)
            if (hasInvertedConnection) {
                DSBlockchainIdentity *blockchainIdentity = [request.destinationContact.associatedBlockchainIdentity blockchainIdentity];
                DWDPOutgoingRequestNotificationObject *object = [[DWDPOutgoingRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                                                                        blockchainIdentity:blockchainIdentity];
                [items addObject:object];
            }

            // outgoing requests with no response (pending) are not shown in notifications
        }
        else { // incoming
            DSBlockchainIdentity *blockchainIdentity = [request.sourceContact.associatedBlockchainIdentity blockchainIdentity];
            if (hasInvertedConnection) {
                DWDPIgnoredRequestNotificationObject *object = [[DWDPIgnoredRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                                                                      blockchainIdentity:blockchainIdentity];
                [items addObject:object];
            }
            else {
                DWDPIncomingRequestNotificationObject *object = [[DWDPIncomingRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                                                                        blockchainIdentity:blockchainIdentity];
                [items addObject:object];
            }
        }
    }

    self.data = [[DWNotificationsData alloc] initWithUnreadItems:newItems oldItems:oldItems];

    [[NSNotificationCenter defaultCenter] postNotificationName:DWNotificationsProviderDidUpdateNotification
                                                        object:self];
}

#pragma mark - DWFetchedResultsDataSourceDelegate

- (void)fetchedResultsDataSourceDidUpdate:(DWFetchedResultsDataSource *)fetchedResultsDataSource {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    // internal FRC might be niled out
    self.fetchedDataSource.fetchedResultsController.delegate = self;

    [self reload];
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");
    DSDLog(@"DWDP: Notification provider's FRC did update");

    [self reload];
}

@end
