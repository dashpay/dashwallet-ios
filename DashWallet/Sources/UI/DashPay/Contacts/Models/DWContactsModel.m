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

#import "DWContactsModel.h"

#import "DWBaseContactsModel+DWProtected.h"
#import "DWContactsDataSourceObject.h"
#import "DWContactsFetchedDataSource.h"
#import "DWDashPayConstants.h"
#import "DWEnvironment.h"
#import "DWIncomingFetchedDataSource.h"
#import "DWRequestsModel.h"

@implementation DWContactsModel

@synthesize requestsDataSource = _requestsDataSource;
@synthesize contactsDataSource = _contactsDataSource;

- (instancetype)init {
    self = [super init];
    if (self) {
        _globalSearchModel = [[DWUserSearchModel alloc] init];
        [self rebuildFRCDataSources];
    }
    return self;
}

- (BOOL)canOpenIdentity:(DSIdentity *)identity {
    if (MOCK_DASHPAY) {
        return YES;
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *myIdentity = wallet.defaultIdentity;
    return !uint256_eq(myIdentity.uniqueID, identity.uniqueID);
}

- (DWRequestsModel *)contactRequestsModel {
    return [[DWRequestsModel alloc] initWithRequestsDataSource:self.requestsDataSource];
}

- (void)rebuildFRCDataSources {
    DSIdentity *identity = [DWEnvironment sharedInstance].currentWallet.defaultIdentity;

    if (!identity && !MOCK_DASHPAY) {
        return;
    }

    NSManagedObjectContext *context = [NSManagedObjectContext viewContext];

    _requestsDataSource = [[DWIncomingFetchedDataSource alloc] initWithIdentity:identity inContext:context];
    _requestsDataSource.shouldSubscribeToNotifications = YES;
    _requestsDataSource.delegate = self;

    _contactsDataSource = [[DWContactsFetchedDataSource alloc] initWithIdentity:identity inContext:context];
    _contactsDataSource.shouldSubscribeToNotifications = YES;
    _contactsDataSource.delegate = self;
}

@end
