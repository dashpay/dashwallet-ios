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

#import "DWEnvironment.h"
#import "dashwallet-Swift.h"

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

@synthesize invitation = _invitation;
@synthesize tag = _tag;

- (instancetype)initWithInvitation:(DSInvitation *)invitation index:(NSUInteger)index {
    self = [super init];
    if (self) {
        _invitation = invitation;
        _index = index;
    }
    return self;
}

- (NSString *)tag {
    return _invitation.tag;
}

- (BOOL)isRegistered {
    return self.invitation.identity.isRegistered;
}

- (NSString *)title {
    NSString *name = _invitation.name;
    NSString *tag = [self.tag isEqualToString:@""] ? nil : self.tag;

    return (tag ? tag : (name ? name : [NSString stringWithFormat:NSLocalizedString(@"Invitation %ld", @"Invitation #3"), self.index]));
}

- (NSString *)subtitle {
    DSTransaction *transaction = self.invitation.identity.registrationAssetLockTransaction;
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
                                                 selector:@selector(identityDidUpdateNotification)
                                                     name:DSIdentityDidUpdateNotification
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
    NSArray<DSInvitation *> *invitations = [wallet.invitations.allValues
        sortedArrayUsingDescriptors:descriptors];
    NSUInteger index = invitations.count;
    NSMutableArray<DWInvitationHistoryItemImpl *> *mutableItems = [NSMutableArray arrayWithCapacity:invitations.count];
    for (DSInvitation *invitation in invitations) {
        BOOL shouldInclude = NO;
        switch (self.filter) {
            case DWInvitationHistoryFilter_All:
                shouldInclude = YES;
                break;
            case DWInvitationHistoryFilter_Pending: {
                DIdentityRegistrationStatus *status = invitation.identity.registrationStatus;
                shouldInclude = dash_spv_platform_identity_model_IdentityRegistrationStatus_is_unknown(status) || dash_spv_platform_identity_model_IdentityRegistrationStatus_is_not_registered(status);
                break;
            }
            case DWInvitationHistoryFilter_Claimed: {
                DIdentityRegistrationStatus *status = invitation.identity.registrationStatus;
                shouldInclude = dash_spv_platform_identity_model_IdentityRegistrationStatus_is_registering(status) || dash_spv_platform_identity_model_IdentityRegistrationStatus_is_registered(status);
                shouldInclude = dash_spv_platform_identity_model_IdentityRegistrationStatus_is_unknown(status) || dash_spv_platform_identity_model_IdentityRegistrationStatus_is_not_registered(status);
                break;
            }
        }

        if (shouldInclude) {
            DWInvitationHistoryItemImpl *item =
                [[DWInvitationHistoryItemImpl alloc] initWithInvitation:invitation
                                                                  index:index];
            [mutableItems addObject:item];

            index -= 1;
        }
    }
    self.items = mutableItems;

    [self.delegate invitationHistoryModelDidUpdate:self];
}

- (void)identityDidUpdateNotification {
    [self reload];
}

@end
