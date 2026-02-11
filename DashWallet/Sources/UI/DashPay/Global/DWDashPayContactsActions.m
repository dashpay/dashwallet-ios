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

#if __has_include("dashpay-Swift.h")
#import "dashpay-Swift.h"
#elif __has_include("dashwallet-Swift.h")
#import "dashwallet-Swift.h"
#endif


@implementation DWDashPayContactsActions

+ (void)acceptContactRequest:(id<DWDPBasicUserItem>)item
                     context:(UIViewController *)context
                  completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    NSAssert([item conformsToProtocol:@protocol(DWDPNewIncomingRequestItem)], @"Incompatible item");

    __block id<DWDPNewIncomingRequestItem> newRequestItem = (id<DWDPNewIncomingRequestItem>)item;
    newRequestItem.requestState = DWDPNewIncomingRequestItemState_Processing;

    // Use PlatformService to accept the contact request
    PlatformService *platform = [DWEnvironment sharedInstance].platformService;
    NSData *senderIdentityId = nil;

    // Try to get identity ID from the blockchain identity
    if ([item conformsToProtocol:@protocol(DWDPBlockchainIdentityBackedItem)]) {
        id<DWDPBlockchainIdentityBackedItem> backedItem = (id<DWDPBlockchainIdentityBackedItem>)item;
        if (backedItem.blockchainIdentity) {
            senderIdentityId = uint256_data(backedItem.blockchainIdentity.uniqueID);
        }
    }

    if (!senderIdentityId) {
        // Fallback: use username as identifier
        senderIdentityId = [item.username dataUsingEncoding:NSUTF8StringEncoding];
    }

    [platform acceptContactRequestWithSenderId:senderIdentityId
                                    completion:^(BOOL success, NSError *error) {
                                        newRequestItem.requestState = success ? DWDPNewIncomingRequestItemState_Accepted : DWDPNewIncomingRequestItemState_Failed;

                                        if (!success) {
                                            DWNetworkErrorViewController *controller = [[DWNetworkErrorViewController alloc] initWithType:DWErrorDescriptionType_AcceptContactRequest];
                                            [context presentViewController:controller animated:YES completion:nil];
                                        }

                                        // Force reload contact list
                                        [[DWDashPayContactsUpdater sharedInstance] fetchWithCompletion:^(BOOL contactsSuccess, NSArray<NSError *> *_Nonnull contactsErrors) {
                                            if (completion) {
                                                NSArray<NSError *> *errors = error ? @[ error ] : @[];
                                                completion(success, errors);
                                            }
                                        }];

                                        DSLog(@"DWDP: accept contact request %@: %@", success ? @"Succeeded" : @"Failed", error);
                                    }];
}

+ (void)declineContactRequest:(id<DWDPBasicUserItem>)item
                      context:(UIViewController *)context
                   completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    // TODO: Implement decline via PlatformService when SDK supports it
    NSAssert([item conformsToProtocol:@protocol(DWDPNewIncomingRequestItem)], @"Incompatible item");

    id<DWDPNewIncomingRequestItem> newRequestItem = (id<DWDPNewIncomingRequestItem>)item;
    newRequestItem.requestState = DWDPNewIncomingRequestItemState_Processing;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        newRequestItem.requestState = DWDPNewIncomingRequestItemState_Failed;
    });
}

@end
