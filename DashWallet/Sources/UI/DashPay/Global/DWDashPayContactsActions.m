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

#import "DWDashPayContactsActions.h"

#import "DWDPBlockchainIdentityBackedItem.h"
#import "DWDPFriendRequestBackedItem.h"
#import "DWDPNewIncomingRequestItem.h"
#import "DWDashPayContactsUpdater.h"
#import "DWEnvironment.h"
#import "DWNetworkErrorViewController.h"
#import "DWNotificationsProvider.h"


@implementation DWDashPayContactsActions

+ (void)acceptContactRequest:(id<DWDPBasicUserItem>)item
                     context:(UIViewController *)context
                  completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    NSAssert([item conformsToProtocol:@protocol(DWDPNewIncomingRequestItem)], @"Incompatible item");

    const BOOL isBlockchainIdentityBacked = [item conformsToProtocol:@protocol(DWDPBlockchainIdentityBackedItem)];
    const BOOL isFriendRequestBacked = [item conformsToProtocol:@protocol(DWDPFriendRequestBackedItem)];
    NSAssert(isBlockchainIdentityBacked || isFriendRequestBacked, @"Invalid item to accept contact request");

    id<DWDPNewIncomingRequestItem> newRequestItem = (id<DWDPNewIncomingRequestItem>)item;
    newRequestItem.requestState = DWDPNewIncomingRequestItemState_Processing;

    void (^resultCompletion)(BOOL success, NSArray<NSError *> *errors) = ^(BOOL success, NSArray<NSError *> *errors) {
        newRequestItem.requestState = success ? DWDPNewIncomingRequestItemState_Accepted : DWDPNewIncomingRequestItemState_Failed;

        if (!success) {
            DWNetworkErrorViewController *controller = [[DWNetworkErrorViewController alloc] initWithType:DWErrorDescriptionType_AcceptContactRequest];
            [context presentViewController:controller animated:YES completion:nil];
        }

        // TODO: DP temp workaround to update and force reload contact list
        // This will trigger DWNotificationsProvider to reset
        [[DWDashPayContactsUpdater sharedInstance] fetchWithCompletion:^(BOOL contactsSuccess, NSArray<NSError *> *_Nonnull contactsErrors) {
            if (completion) {
                completion(success, errors);
            }
        }];

        DSLog(@"DWDP: accept contact request %@: %@", success ? @"Succeeded" : @"Failed", errors);
    };

    // Accepting request from a DSFriendRequestEntity doesn't require searching for associated blockchain identity.
    // Since all DWDPBasicUserItem has associated BI, check if it's a DSFriendRequestEntity first.
    if (isFriendRequestBacked && [(id<DWDPFriendRequestBackedItem>)item friendRequestEntity] != nil) {
        id<DWDPFriendRequestBackedItem> backedItem = (id<DWDPFriendRequestBackedItem>)item;
        [self acceptContactRequestFromFriendRequest:backedItem.friendRequestEntity completion:resultCompletion];
    }
    else if (isBlockchainIdentityBacked && [(id<DWDPBlockchainIdentityBackedItem>)item blockchainIdentity] != nil) {
        id<DWDPBlockchainIdentityBackedItem> backedItem = (id<DWDPBlockchainIdentityBackedItem>)item;
        [self acceptContactRequestFromBlockchainIdentity:backedItem.blockchainIdentity completion:resultCompletion];
    }
}

+ (void)declineContactRequest:(id<DWDPBasicUserItem>)item
                      context:(UIViewController *)context
                   completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    // TODO: DP dummy method

    NSAssert([item conformsToProtocol:@protocol(DWDPNewIncomingRequestItem)], @"Incompatible item");

    id<DWDPNewIncomingRequestItem> newRequestItem = (id<DWDPNewIncomingRequestItem>)item;
    newRequestItem.requestState = DWDPNewIncomingRequestItemState_Processing;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        newRequestItem.requestState = DWDPNewIncomingRequestItemState_Failed;
    });
}

#pragma mark - Private

+ (void)acceptContactRequestFromBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity
                                        completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    [myBlockchainIdentity acceptFriendRequestFromBlockchainIdentity:blockchainIdentity completion:completion];
}

+ (void)acceptContactRequestFromFriendRequest:(DSFriendRequestEntity *)friendRequest
                                   completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    [myBlockchainIdentity acceptFriendRequest:friendRequest completion:completion];
}

@end
