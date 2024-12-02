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
    return ([DWGlobalOptions sharedInstance].confirmationAcceptContactRequestIsOn && [self friendshipStatusInternal] == DSBlockchainIdentityFriendshipStatus_Incoming);
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

- (DSBlockchainIdentityFriendshipStatus)friendshipStatus {
    if (self.state == DWUserProfileModelState_None || self.state == DWUserProfileModelState_Loading) {
        return DSBlockchainIdentityFriendshipStatus_Unknown;
    }

    return [self friendshipStatusInternal];
}

- (BOOL)shouldShowActions {
    if (self.state != DWUserProfileModelState_Done) {
        return NO;
    }

    const DSBlockchainIdentityFriendshipStatus status = self.friendshipStatus;
    return (status == DSBlockchainIdentityFriendshipStatus_Incoming ||
            status == DSBlockchainIdentityFriendshipStatus_None ||
            status == DSBlockchainIdentityFriendshipStatus_Outgoing);
}

- (BOOL)shouldShowSendRequestAction {
    NSParameterAssert(self.state == DWUserProfileModelState_Done);

    const DSBlockchainIdentityFriendshipStatus status = self.friendshipStatus;
    return (status == DSBlockchainIdentityFriendshipStatus_None ||
            status == DSBlockchainIdentityFriendshipStatus_Outgoing);
}

- (BOOL)shouldShowAcceptDeclineRequestAction {
    NSParameterAssert(self.state == DWUserProfileModelState_Done);

    const DSBlockchainIdentityFriendshipStatus status = self.friendshipStatus;
    return status == DSBlockchainIdentityFriendshipStatus_Incoming;
}

- (void)sendContactRequest:(void (^)(BOOL success))completion {
    if (MOCK_DASHPAY) {
        self.sendRequestState = DWUserProfileModelState_Loading;

        NSManagedObjectContext *context = [NSManagedObjectContext viewContext];
        DSDashpayUserEntity *contact = [DSDashpayUserEntity managedObjectInBlockedContext:context];
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        contact.chain = [wallet.chain chainEntityInContext:context];
        DSBlockchainIdentity *identity = [wallet createBlockchainIdentityForUsername:_item.username];
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
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    __weak typeof(self) weakSelf = self;
    [myBlockchainIdentity sendNewFriendRequestToBlockchainIdentity:self.item.blockchainIdentity
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

- (DSBlockchainIdentityFriendshipStatus)friendshipStatusInternal {
    if (MOCK_DASHPAY) {
        if (uint256_is_zero(self.item.blockchainIdentity.uniqueID)) {
            // From search
            return DSBlockchainIdentityFriendshipStatus_None;
        }
        else {
            // From mocked contacts
            return DSBlockchainIdentityFriendshipStatus_Friends;
        }
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSBlockchainIdentity *blockchainIdentity = self.item.blockchainIdentity;
    return [myBlockchainIdentity friendshipStatusForRelationshipWithBlockchainIdentity:blockchainIdentity];
}

- (void)updateDataSource {
    NSManagedObjectContext *context = [NSManagedObjectContext viewContext];

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSBlockchainIdentity *friendBlockchainIdentity = self.item.blockchainIdentity;
    DSDashpayUserEntity *friend = nil;
    DSFriendRequestEntity *meToFriend = nil;
    DSFriendRequestEntity *friendToMe = nil;

    if (MOCK_DASHPAY) {
        meToFriend = self.item.friendRequestToPay;
        friendBlockchainIdentity = [[DWEnvironment sharedInstance].currentWallet createBlockchainIdentityForUsername:self.item.username];
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

        if (username != nil) {
            myBlockchainIdentity = [[DWEnvironment sharedInstance].currentWallet createBlockchainIdentityForUsername:username];
        }
    }
    else {
        if (myBlockchainIdentity == nil) {
            return;
        }

        NSAssert(myBlockchainIdentity.matchingDashpayUserInViewContext, @"Invalid DSBlockchainIdentity: myBlockchainIdentity");
        DSDashpayUserEntity *me = [myBlockchainIdentity matchingDashpayUserInContext:context];

        if (friendBlockchainIdentity.matchingDashpayUserInViewContext) {
            friend = [friendBlockchainIdentity matchingDashpayUserInContext:context];
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
                                                  friendBlockchainIdentity:friendBlockchainIdentity
                                                      myBlockchainIdentity:myBlockchainIdentity];

    [self.delegate userProfileModelDidUpdate:self];
}

@end
