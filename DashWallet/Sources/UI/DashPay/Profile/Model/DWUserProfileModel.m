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

#import "DWDashPayContactsActions.h"
#import "DWDashPayContactsUpdater.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWProfileTxsFetchedDataSource.h"
#import "DWUserProfileDataSourceObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileModel () <DWFetchedResultsDataSourceDelegate, NSFetchedResultsControllerDelegate>

@property (nonatomic, assign) DWUserProfileModelState state;
@property (nullable, nonatomic, strong) DWProfileTxsFetchedDataSource *txsFetchedDataSource;
@property (nonatomic, strong) id<DWUserProfileDataSource> dataSource;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> txDataProvider;

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

- (void)setRequestState:(DWUserProfileModelState)requestState {
    _requestState = requestState;

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

- (void)sendContactRequest:(void (^)(BOOL success))completion {
    self.requestState = DWUserProfileModelState_Loading;

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
                                                            strongSelf.requestState = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;

                                                            if (completion) {
                                                                completion(success);
                                                            }
                                                        }];
}

- (void)acceptContactRequest {
    self.requestState = DWUserProfileModelState_Loading;

    __weak typeof(self) weakSelf = self;
    [DWDashPayContactsActions acceptContactRequest:self.item
                                           context:self.context
                                        completion:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
                                            __strong typeof(weakSelf) strongSelf = weakSelf;
                                            if (!strongSelf) {
                                                return;
                                            }

                                            [strongSelf updateDataSource];
                                            strongSelf.requestState = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;
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
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSBlockchainIdentity *blockchainIdentity = self.item.blockchainIdentity;
    return [myBlockchainIdentity friendshipStatusForRelationshipWithBlockchainIdentity:blockchainIdentity];
}

- (void)updateDataSource {
    NSManagedObjectContext *context = [NSManagedObjectContext viewContext];

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    if (myBlockchainIdentity == nil) {
        return;
    }

    DSBlockchainIdentity *friendBlockchainIdentity = self.item.blockchainIdentity;
    NSAssert(myBlockchainIdentity.matchingDashpayUserInViewContext, @"Invalid DSBlockchainIdentity: myBlockchainIdentity");
    DSDashpayUserEntity *me = [myBlockchainIdentity matchingDashpayUserInContext:context];
    DSDashpayUserEntity *friend = nil;
    if (friendBlockchainIdentity.matchingDashpayUserInViewContext) {
        friend = [friendBlockchainIdentity matchingDashpayUserInContext:context];
    }

    DSFriendRequestEntity *meToFriend = nil;
    if (friend != nil) {
        meToFriend = [[me.outgoingRequests filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"destinationContact == %@", friend]] anyObject];
    }

    DSFriendRequestEntity *friendToMe = nil;
    if (friend != nil) {
        friendToMe = [[me.incomingRequests filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"sourceContact == %@", friend]] anyObject];
    }

    BOOL shouldShowContactRequests = YES;
    if (self.displayMode == DWHomeTxDisplayMode_Sent) {
        meToFriend = nil;
        shouldShowContactRequests = NO;
    }
    else if (self.displayMode == DWHomeTxDisplayMode_Received) {
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
