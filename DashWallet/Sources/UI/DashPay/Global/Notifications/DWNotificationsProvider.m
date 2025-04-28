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
// if MOCK_DASHPAY
#import "DWDashPayConstants.h"

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWNotificationsProviderWillUpdateNotification = @"org.dash.wallet.dp.notifications-will-update";
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

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didUpdateContacts)
                                                     name:DWDashPayContactsDidUpdateNotification
                                                   object:nil];

        // Defer initial reset of notifications because it would lead to a deadlock
        // (since DWNotificationsProvider is a singleton and reset would produce a notification)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self forceUpdate];
        });
    }
    return self;
}

- (void)forceUpdate {
    DSIdentity *identity = [DWEnvironment sharedInstance].currentWallet.defaultIdentity;

    if (MOCK_DASHPAY) {
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

        if (username != nil) {
            identity = [[DWEnvironment sharedInstance].currentWallet createIdentityForUsername:username];
        }
    }

    if (!identity) {
        return;
    }

    NSManagedObjectContext *context = [NSManagedObjectContext viewContext];

    _fetchedDataSource = [[DWNotificationsFetchedDataSource alloc] initWithIdentity:identity inContext:context];
    _fetchedDataSource.shouldSubscribeToNotifications = YES;
    _fetchedDataSource.delegate = self;
    [_fetchedDataSource start];
    _fetchedDataSource.fetchedResultsController.delegate = self;

    [self reload];
}

#pragma mark - Private

- (void)setData:(DWNotificationsData *)data {
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter postNotificationName:DWNotificationsProviderWillUpdateNotification object:self];
    _data = data;
    [notificationCenter postNotificationName:DWNotificationsProviderDidUpdateNotification object:self];
}

- (void)reload {
    if (MOCK_DASHPAY) {
        NSMutableArray<id<DWDPBasicUserItem, DWDPNotificationItem>> *newItems = [NSMutableArray array];
        NSMutableArray<id<DWDPBasicUserItem, DWDPNotificationItem>> *oldItems = [NSMutableArray array];

        DSIdentity *identity = [[DWEnvironment sharedInstance].currentWallet createIdentityForUsername:@"tonnypaperoni"];
        DWDPNewIncomingRequestNotificationObject *incoming = [[DWDPNewIncomingRequestNotificationObject alloc] initWithIdentity:identity];
        [newItems addObject:incoming];

        identity = [[DWEnvironment sharedInstance].currentWallet createIdentityForUsername:@"jamesholden"];
        incoming = [[DWDPNewIncomingRequestNotificationObject alloc] initWithIdentity:identity];
        [oldItems addObject:incoming];

        identity = [[DWEnvironment sharedInstance].currentWallet createIdentityForUsername:@"johndoe"];
        DWDPOutgoingRequestNotificationObject *outgoing = [[DWDPOutgoingRequestNotificationObject alloc] initWithIdentity:identity];
        [oldItems addObject:outgoing];

        self.data = [[DWNotificationsData alloc] initWithUnreadItems:[newItems reverseObjectEnumerator].allObjects
                                                            oldItems:[oldItems reverseObjectEnumerator].allObjects];
        return;
    }


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

    DSIdentity *identity = [DWEnvironment sharedInstance].currentWallet.defaultIdentity;
    NSManagedObjectID *userID = identity.matchingDashpayUserInViewContext.objectID;

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

            if (isFriendship) {
                DSIdentity *identity = [request.destinationContact.associatedBlockchainIdentity identity];
                DWDPOutgoingRequestNotificationObject *object =
                    [[DWDPOutgoingRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                                      identity:identity
                                                                               isInitiatedByMe:isInitiatedByMe];
                // all outgoing events should be in the Earlier section
                [oldItems addObject:object];
            }

            // outgoing requests with no response (pending) are not shown in notifications
        }
        else { // incoming
            const BOOL isInitiatedByThem = ![processed containsObject:sourceID];
            [processed addObject:sourceID];

            DSIdentity *identity = [request.sourceContact.associatedBlockchainIdentity identity];
            if (isFriendship) {
                DWDPAcceptedRequestNotificationObject *object =
                    [[DWDPAcceptedRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                                      identity:identity
                                                                             isInitiatedByThem:isInitiatedByThem];
                // Don't add notifications about MY responses to the New section
                if (isInitiatedByThem) {
                    [oldItems addObject:object];
                }
                else {
                    [items addObject:object];
                }
            }
            else {
                DWDPNewIncomingRequestNotificationObject *object =
                    [[DWDPNewIncomingRequestNotificationObject alloc] initWithFriendRequestEntity:request
                                                                                         identity:identity];
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
    DSLog(@"DWDP: Notification provider's FRC did update");

    [self reload];
}

#pragma mark - Notifications

- (void)didUpdateContacts {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [self forceUpdate];
}

@end
