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

#import "DWUserProfileModel.h"

#import "DWDashPayConstants.h"
#import "DWDashPayContactsActions.h"
#import "DWDashPayContactsUpdater.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWProfileTxsFetchedDataSource.h"
#import "DWUserProfileDataSourceObject.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileModel () <DWFetchedResultsDataSourceDelegate, NSFetchedResultsControllerDelegate>

@property (nonatomic, assign) DWUserProfileModelState state;
@property (nullable, nonatomic, strong) DWProfileTxsFetchedDataSource *txsFetchedDataSource;
@property (nonatomic, strong) id<DWUserProfileDataSource> dataSource;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> txDataProvider;
@property (nonatomic, assign) DWHomeTxDisplayMode displayMode;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileModel

@synthesize displayMode = _displayMode;

- (instancetype)initWithItem:(id<DWDPBasicUserItem>)item
              txDataProvider:(id<DWTransactionListDataProviderProtocol>)txDataProvider {
    self = [super init];
    if (self) {
        _item = item;
        _txDataProvider = txDataProvider;
        _dataSource = [[DWUserProfileDataSourceObject alloc] init]; // empty data source

        // TODO: DP global notification is used temporary. Remove its usage once FRC delegate issue is resolved
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(transactionManagerTransactionStatusDidChangeNotification)
                                   name:DSTransactionManagerTransactionStatusDidChangeNotification
                                 object:nil];
    }
    return self;
}

- (BOOL)shouldAcceptIncomingAfterPayment {
    return ([DWGlobalOptions sharedInstance].confirmationAcceptContactRequestIsOn && [self friendshipStatusInternal] == DSIdentityFriendshipStatus_Incoming);
}

- (void)setDisplayMode:(DWHomeTxDisplayMode)displayMode {
    _displayMode = displayMode;

    [self updateDataSource];
}

- (void)skipUpdating {
    [self updateDataSource];


    if (self.shownAfterPayment && self.shouldAcceptIncomingAfterPayment) {
        [self acceptContactRequest];
    }
    else {
        self.state = DWUserProfileModelState_Done;
    }
}

- (void)setState:(DWUserProfileModelState)state {
    _state = state;

    [self.delegate userProfileModelDidUpdate:self];
}

- (void)setSendRequestState:(DWUserProfileModelState)sendRequestState {
    _sendRequestState = sendRequestState;

    [self.delegate userProfileModelDidUpdate:self];
}

- (void)setAcceptRequestState:(DWUserProfileModelState)acceptRequestState {
    _acceptRequestState = acceptRequestState;

    [self.delegate userProfileModelDidUpdate:self];
}

- (NSString *)username {
    return self.item.username;
}

- (void)update {
    self.state = DWUserProfileModelState_Loading;

    __weak typeof(self) weakSelf = self;
    [[DWDashPayContactsUpdater sharedInstance] fetchWithCompletion:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf updateDataSource];
        strongSelf.state = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;
    }];
}

- (DSIdentityFriendshipStatus)friendshipStatus {
    if (self.state == DWUserProfileModelState_None || self.state == DWUserProfileModelState_Loading) {
        return DSIdentityFriendshipStatus_Unknown;
    }

    return [self friendshipStatusInternal];
}

- (BOOL)shouldShowActions {
    if (self.state != DWUserProfileModelState_Done) {
        return NO;
    }

    const DSIdentityFriendshipStatus status = self.friendshipStatus;
    return (status == DSIdentityFriendshipStatus_Incoming ||
            status == DSIdentityFriendshipStatus_None ||
            status == DSIdentityFriendshipStatus_Outgoing);
}

- (BOOL)shouldShowSendRequestAction {
    NSParameterAssert(self.state == DWUserProfileModelState_Done);

    const DSIdentityFriendshipStatus status = self.friendshipStatus;
    return (status == DSIdentityFriendshipStatus_None ||
            status == DSIdentityFriendshipStatus_Outgoing);
}

- (BOOL)shouldShowAcceptDeclineRequestAction {
    NSParameterAssert(self.state == DWUserProfileModelState_Done);

    const DSIdentityFriendshipStatus status = self.friendshipStatus;
    return status == DSIdentityFriendshipStatus_Incoming;
}

- (void)sendContactRequest:(void (^)(BOOL success))completion {
    if (MOCK_DASHPAY) {
        self.sendRequestState = DWUserProfileModelState_Loading;

        NSManagedObjectContext *context = [NSManagedObjectContext viewContext];
        DSDashpayUserEntity *contact = [DSDashpayUserEntity managedObjectInBlockedContext:context];
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        contact.chain = [wallet.chain chainEntityInContext:context];
        DSIdentity *identity = [wallet createIdentityForUsername:_item.username];
        DSBlockchainIdentityUsernameEntity *username = [DSBlockchainIdentityUsernameEntity managedObjectInBlockedContext:context];
        username.stringValue = _item.username;
        DSBlockchainIdentityEntity *entity = [DSBlockchainIdentityEntity managedObjectInBlockedContext:context];
        entity.uniqueID = [_item.username dataUsingEncoding:NSUTF8StringEncoding];
        username.blockchainIdentity = entity;
        entity.dashpayUsername = username;
        contact.associatedBlockchainIdentity = entity;
        NSError *error = [contact applyTransientDashpayUser:identity.transientDashpayUser save:YES];

        completion(YES);
        return;
    }

    self.sendRequestState = DWUserProfileModelState_Loading;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *myIdentity = wallet.defaultIdentity;
    __weak typeof(self) weakSelf = self;
    [myIdentity sendNewFriendRequestToIdentity:self.item.identity
                                    completion:^(BOOL success, NSArray<NSError *> *_Nullable errors) {
                                        __strong typeof(weakSelf) strongSelf = weakSelf;
                                        if (!strongSelf) {
                                            return;
                                        }

                                        [strongSelf updateDataSource];
                                        strongSelf.sendRequestState = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;

                                        if (completion) {
                                            completion(success);
                                        }
                                    }];
}

- (void)acceptContactRequest {
    self.acceptRequestState = DWUserProfileModelState_Loading;

    __weak typeof(self) weakSelf = self;
    [DWDashPayContactsActions acceptContactRequest:self.item
                                           context:self.context
                                        completion:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
                                            __strong typeof(weakSelf) strongSelf = weakSelf;
                                            if (!strongSelf) {
                                                return;
                                            }

                                            [strongSelf updateDataSource];
                                            strongSelf.acceptRequestState = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;
                                        }];
}

#pragma mark - DWFetchedResultsDataSourceDelegate

- (void)fetchedResultsDataSourceDidUpdate:(DWFetchedResultsDataSource *)fetchedResultsDataSource {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    // TODO: DP fix me, not firing
    // global txs notifications was used instead to workaround this issue

    [self updateDataSource];
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    // TODO: DP fix me, not firing
    // global txs notifications was used instead to workaround this issue

    [self updateDataSource];
}

#pragma mark - Notifications

- (void)transactionManagerTransactionStatusDidChangeNotification {
    [self updateDataSource];
}

#pragma mark - Private

- (DSIdentityFriendshipStatus)friendshipStatusInternal {
    if (MOCK_DASHPAY) {
        if (uint256_is_zero(self.item.identity.uniqueID)) {
            // From search
            return DSIdentityFriendshipStatus_None;
        }
        else {
            // From mocked contacts
            return DSIdentityFriendshipStatus_Friends;
        }
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *myIdentity = wallet.defaultIdentity;
    DSIdentity *identity = self.item.identity;
    return [myIdentity friendshipStatusForRelationshipWithIdentity:identity];
}

- (void)updateDataSource {
    NSManagedObjectContext *context = [NSManagedObjectContext viewContext];

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *myIdentity = wallet.defaultIdentity;
    DSIdentity *friendIdentity = self.item.identity;
    DSDashpayUserEntity *friend = nil;
    DSFriendRequestEntity *meToFriend = nil;
    DSFriendRequestEntity *friendToMe = nil;

    if (MOCK_DASHPAY) {
        meToFriend = self.item.friendRequestToPay;
        friendIdentity = [[DWEnvironment sharedInstance].currentWallet createIdentityForUsername:self.item.username];
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

        if (username != nil) {
            myIdentity = [[DWEnvironment sharedInstance].currentWallet createIdentityForUsername:username];
        }
    }
    else {
        if (myIdentity == nil) {
            return;
        }

        NSAssert(myIdentity.matchingDashpayUserInViewContext, @"Invalid DSIdentity: myIdentity");
        DSDashpayUserEntity *me = [myIdentity matchingDashpayUserInContext:context];

        if (friendIdentity.matchingDashpayUserInViewContext) {
            friend = [friendIdentity matchingDashpayUserInContext:context];
        }


        if (friend != nil) {
            meToFriend = [[me.outgoingRequests filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"destinationContact == %@", friend]] anyObject];
        }

        if (friend != nil) {
            friendToMe = [[me.incomingRequests filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"sourceContact == %@", friend]] anyObject];
        }
    }

    BOOL shouldShowContactRequests = YES;
    if (self.displayMode == DWHomeTxDisplayModeSent) {
        meToFriend = nil;
        shouldShowContactRequests = NO;
    }
    else if (self.displayMode == DWHomeTxDisplayModeReceived) {
        friendToMe = nil;
        shouldShowContactRequests = NO;
    }

    if (meToFriend || friendToMe) {
        self.txsFetchedDataSource = [[DWProfileTxsFetchedDataSource alloc] initWithMeToFriendRequest:meToFriend
                                                                                   friendToMeRequest:friendToMe
                                                                                           inContext:context];
        self.txsFetchedDataSource.delegate = self;
        [self.txsFetchedDataSource start];
        self.txsFetchedDataSource.fetchedResultsController.delegate = self;
    }
    else {
        self.txsFetchedDataSource = nil;
    }

    self.dataSource = [[DWUserProfileDataSourceObject alloc] initWithTxFRC:self.txsFetchedDataSource.fetchedResultsController
                                                            txDataProvider:self.txDataProvider
                                                         friendToMeRequest:shouldShowContactRequests ? friendToMe : nil
                                                         meToFriendRequest:shouldShowContactRequests ? meToFriend : nil
                                                            friendIdentity:friendIdentity
                                                                myIdentity:myIdentity];

    [self.delegate userProfileModelDidUpdate:self];
}

@end
