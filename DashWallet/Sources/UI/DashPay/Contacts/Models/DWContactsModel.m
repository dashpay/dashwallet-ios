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
#import "DWEnvironment.h"
#import "DWIncomingFetchedDataSource.h"

@implementation DWContactsModel

@synthesize aggregateDataSource = _aggregateDataSource;
@synthesize firstSectionDataSource = _firstSectionDataSource;
@synthesize secondSectionDataSource = _secondSectionDataSource;

- (instancetype)init {
    self = [super init];
    if (self) {
        _aggregateDataSource = [[DWContactsDataSourceObject alloc] init];
        [self rebuildDataSources];
    }
    return self;
}

- (void)rebuildDataSources {
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    if (!blockchainIdentity) {
        return;
    }

    NSManagedObjectContext *context = [NSManagedObject mainContext];

    _firstSectionDataSource = [[DWIncomingFetchedDataSource alloc] initWithContext:context blockchainIdentity:blockchainIdentity];
    _firstSectionDataSource.shouldSubscribeToNotifications = YES;
    _firstSectionDataSource.delegate = self;

    _secondSectionDataSource = [[DWContactsFetchedDataSource alloc] initWithContext:context blockchainIdentity:blockchainIdentity];
    _secondSectionDataSource.shouldSubscribeToNotifications = YES;
    _secondSectionDataSource.delegate = self;
}

@end
