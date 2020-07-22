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

#import "DWDashPayContactsUpdater.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWNotificationsData.h"
#import "DWNotificationsFetchedDataSource.h"

#import "DWDPAcceptedRequestNotificationObject.h"
#import "DWDPEstablishedContactNotificationObject.h"
#import "DWDPNewIncomingRequestNotificationObject.h"
#import "DWDPOutgoingRequestNotificationObject.h"

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWNotificationsProviderWillUpdateNotification = @"org.dash.wallet.dp.notifications-will-update";
NSNotificationName const DWNotificationsProviderDidUpdateNotification = @"org.dash.wallet.dp.notifications-did-update";

@interface DWNotificationsProvider () <DWFetchedResultsDataSourceDelegate, NSFetchedResultsControllerDelegate>

@property (nonatomic, strong) DWFetchedResultsDataSource *fetchedDataSource;
@property (nonatomic, copy) DWNotificationsData *data;

@property (nonatomic, assign, getter=isIgnoringOutboundEvents) BOOL ignoringOutboundEvents;
/// Contains objectIDs of DSFriendRequestEntity.sourceContact which were accepted during ignoring outbound events
@property (nonatomic, strong) NSMutableSet<NSManagedObjectID *> *acceptedRequestContactIDs;

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

        _acceptedRequestContactIDs = [NSMutableSet set];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didUpdateContacts)
                                                     name:DWDashPayContactsDidUpdateNotification
                                                   object:nil];

        // Defer initial reset of notifications because it would lead to a deadlock
        // (since DWNotificationsProvider is a singleton and reset would produce a notification)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reset];
        });
    }
    return self;
}

- (void)beginIgnoringOutboundEvents {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    self.ignoringOutboundEvents = YES;
}

- (void)endIgnoringOutboundEvents {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    self.ignoringOutboundEvents = NO;

    self.acceptedRequestContactIDs = [NSMutableSet set];

    [self reset];
}

- (void)requestWasAcceptedFromContactID:(NSManagedObjectID *)objectID {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    if (!self.isIgnoringOutboundEvents) {
        return;
    }

    NSParameterAssert(objectID);
    if (!objectID) {
        return;
    }

    [self.acceptedRequestContactIDs addObject:objectID];
}

#pragma mark - Private

- (void)reset {
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    if (!blockchainIdentity) {
        return;
    }

    NSManagedObjectContext *context = [NSManagedObjectContext viewContext];

    _fetchedDataSource = [[DWNotificationsFetchedDataSource alloc] initWithBlockchainIdentity:blockchainIdentity inContext:context];
    _fetchedDataSource.shouldSubscribeToNotifications = YES;
    _fetchedDataSource.delegate = self;
    [_fetchedDataSource start];
    _fetchedDataSource.fetchedResultsController.delegate = self;

    [self reload];
}

- (void)setData:(DWNotificationsData *)data {
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter postNotificationName:DWNotificationsProviderWillUpdateNotification object:self];
    _data = data;
    [notificationCenter postNotificationName:DWNotificationsProviderDidUpdateNotification object:self];
}

- (void)reload {
    // fetched objects come in a reversed order (from old to new)
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

    DWGlobalOptions *options = [DWGlobalOptions sharedInstance];
    const NSTimeInterval mostRecentViewedTimestamp = [options.mostRecentViewedNotificationDate timeIntervalSince1970];

    NSMutableArray<id<DWDPBasicUserItem, DWDPNotificationItem>> *newItems = [NSMutableArray array];
    NSMutableArray<id<DWDPBasicUserItem, DWDPNotificationItem>> *oldItems = [NSMutableArray array];

    NSMutableSet<NSManagedObjectID *> *processed = [NSMutableSet set];

    for (DSFriendRequestEntity *request in fetchedObjects) {
        NSManagedObjectID *sourceID = request.sourceContact.objectID;
        NSManagedObjectID *destinationID = request.destinationContact.objectID;
        NSSet<NSManagedObjectID *> *destinationConnections = connections[destinationID];
        const BOOL isFriendship = [destinationConnections containsObject:sourceID];
        const BOOL isNew = request.timestamp > mostRecentViewedTimestamp;
        NSMutableArray<id<DWDPBasicUserItem, DWDPNotificationItem>> *items = isNew ? newItems : oldItems;

        if ([sourceID isEqual:userID]) { // outoging
            const BOOL isInitiatedByMe = ![processed containsObject:destinationID];
            [processed addObject:destinationID];

            if (self.isIgnoringOutboundEvents && !isInitiatedByMe && [self.acceptedRequestContactIDs containsObject:destinationID]) {
                // Mark it as viewed since it was accepted while ignoring outbound events and don't add to the list.
                // `mostRecentViewedTimestamp` var remains the same because we need to filter other requests
                options.mostRecentViewedNotificationDate = [NSDate dateWithTimeIntervalSince1970:request.timestamp];

                continue;
            }

            if (isFriendship) {
                DSBlockchainIdentity *blockchainIdentity = [request.destinationContact.associatedBlockchainIdentity blockchainIdentity];
                DWDPOutgoingRequestNotificationObject *object =
                    [[DWDPOutgoingRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                            blockchainIdentity:blockchainIdentity
                                                                               isInitiatedByMe:isInitiatedByMe];
                // all outgoing events should be in the Earlier section
                [oldItems addObject:object];
            }

            // outgoing requests with no response (pending) are not shown in notifications
        }
        else { // incoming
            const BOOL isInitiatedByThem = ![processed containsObject:sourceID];
            [processed addObject:sourceID];

            DSBlockchainIdentity *blockchainIdentity = [request.sourceContact.associatedBlockchainIdentity blockchainIdentity];
            if (isFriendship) {
                if (self.isIgnoringOutboundEvents && isInitiatedByThem && [self.acceptedRequestContactIDs containsObject:sourceID]) {
                    DWDPEstablishedContactNotificationObject *object =
                        [[DWDPEstablishedContactNotificationObject alloc] initWithFriendRequestEntity:request
                                                                                   blockchainIdentity:blockchainIdentity];
                    [items addObject:object];
                }
                else {
                    DWDPAcceptedRequestNotificationObject *object =
                        [[DWDPAcceptedRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                                blockchainIdentity:blockchainIdentity
                                                                                 isInitiatedByThem:isInitiatedByThem];
                    [items addObject:object];
                }
            }
            else {
                DWDPNewIncomingRequestNotificationObject *object =
                    [[DWDPNewIncomingRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                               blockchainIdentity:blockchainIdentity];
                [items addObject:object];
            }
        }
    }

    self.data = [[DWNotificationsData alloc] initWithUnreadItems:[newItems reverseObjectEnumerator].allObjects
                                                        oldItems:[oldItems reverseObjectEnumerator].allObjects];
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

#pragma mark - Notifications

- (void)didUpdateContacts {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [self reset];
}

@end
