//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWInvitationHistoryModel.h"

#import "DWDateFormatter.h"
#import "DWEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Item Header

@interface DWInvitationHistoryItemImpl : NSObject <DWInvitationHistoryItem>

@property (readonly, nonatomic, assign) NSUInteger index;

@end

#pragma mark - Model Header

@interface DWInvitationHistoryModel ()

@property (nonatomic, copy) NSArray<id<DWInvitationHistoryItem>> *items;

@end

NS_ASSUME_NONNULL_END

#pragma mark - Item Impl

@implementation DWInvitationHistoryItemImpl

@synthesize blockchainInvitation = _blockchainInvitation;

- (instancetype)initWithInvitation:(DSBlockchainInvitation *)invitation index:(NSUInteger)index {
    self = [super init];
    if (self) {
        _blockchainInvitation = invitation;
        _index = index;
    }
    return self;
}

- (BOOL)isRegistered {
    return self.blockchainInvitation.identity.isRegistered;
}

- (NSString *)title {
    return self.blockchainInvitation.identity.currentDashpayUsername
               ? self.blockchainInvitation.identity.currentDashpayUsername
               : [NSString stringWithFormat:NSLocalizedString(@"Invitation %ld", @"Invitation #3"), self.index];
}

- (NSString *)subtitle {
    DSTransaction *transaction = self.blockchainInvitation.identity.registrationCreditFundingTransaction;
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    NSTimeInterval now = [chain timestampForBlockHeight:TX_UNCONFIRMED];
    NSTimeInterval txTime = (transaction.timestamp > 1) ? transaction.timestamp : now;
    NSDate *txDate = [NSDate dateWithTimeIntervalSince1970:txTime];
    return [[DWDateFormatter sharedInstance] shortStringFromDate:txDate];
}

@end

#pragma mark - Model Impl

@implementation DWInvitationHistoryModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = @[];
        _filter = DWInvitationHistoryFilter_All;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(blockchainIdentityDidUpdateNotification)
                                                     name:DSBlockchainIdentityDidUpdateNotification
                                                   object:nil];

        [self reload];
    }
    return self;
}

- (void)setFilter:(DWInvitationHistoryFilter)filter {
    _filter = filter;

    [self reload];
}

- (void)reload {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    NSArray<NSSortDescriptor *> *descriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"identity.registrationCreditFundingTransaction.blockHeight"
                                      ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"identity.registrationCreditFundingTransaction.timestamp"
                                      ascending:NO],
    ];
    NSArray<DSBlockchainInvitation *> *invitations = [wallet.blockchainInvitations.allValues
        sortedArrayUsingDescriptors:descriptors];
    NSUInteger index = 1;
    NSMutableArray<DWInvitationHistoryItemImpl *> *mutableItems = [NSMutableArray arrayWithCapacity:invitations.count];
    for (DSBlockchainInvitation *invitation in invitations) {
        BOOL shouldInclude = NO;
        switch (self.filter) {
            case DWInvitationHistoryFilter_All:
                shouldInclude = YES;
                break;
            case DWInvitationHistoryFilter_Pending:
                shouldInclude = invitation.identity.registrationStatus == DSBlockchainIdentityRegistrationStatus_Unknown ||
                                invitation.identity.registrationStatus == DSBlockchainIdentityRegistrationStatus_NotRegistered;
                break;
            case DWInvitationHistoryFilter_Claimed:
                shouldInclude = invitation.identity.registrationStatus == DSBlockchainIdentityRegistrationStatus_Registering ||
                                invitation.identity.registrationStatus == DSBlockchainIdentityRegistrationStatus_Registered;
                break;
        }

        if (shouldInclude) {
            DWInvitationHistoryItemImpl *item =
                [[DWInvitationHistoryItemImpl alloc] initWithInvitation:invitation
                                                                  index:index];
            [mutableItems addObject:item];

            index += 1;
        }
    }
    self.items = mutableItems;

    [self.delegate invitationHistoryModelDidUpdate:self];
}

- (void)blockchainIdentityDidUpdateNotification {
    [self reload];
}

@end
