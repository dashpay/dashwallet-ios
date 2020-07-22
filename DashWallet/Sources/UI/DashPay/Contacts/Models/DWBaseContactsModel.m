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

#import "DWBaseContactsModel+DWProtected.h"

#import "DWContactsDataSourceObject.h"
#import "DWContactsSearchDataSourceObject.h"
#import "DWDPContactsItemsFactory.h"
#import "DWDashPayContactsActions.h"
#import "DWDashPayContactsUpdater.h"
#import "DWEnvironment.h"

@implementation DWBaseContactsModel

@synthesize sortMode;

- (instancetype)init {
    self = [super init];
    if (self) {
        _itemsFactory = [[DWDPContactsItemsFactory alloc] init];
    }
    return self;
}

- (BOOL)hasBlockchainIdentity {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    return myBlockchainIdentity != nil;
}

- (id<DWContactsDataSource>)dataSource {
    return [self isSearching] ? self.searchDataSource : self.allDataSource;
}

- (void)rebuildFRCDataSources {
    // to be overriden
    // create FRC-backed datasources here
}

- (BOOL)shouldFetchData {
    return YES;
}

- (void)start {
    if ([self shouldFetchData]) {
        [[DWDashPayContactsUpdater sharedInstance] fetch];
    }

    if (!self.requestsDataSource) {
        [self rebuildFRCDataSources];
    }

    [self.requestsDataSource start];
    [self.contactsDataSource start];

    [self updateForced:YES];
}

- (void)stop {
    [self.requestsDataSource stop];
    [self.contactsDataSource stop];
}

- (void)acceptContactRequest:(id<DWDPBasicUserItem>)item {
    [DWDashPayContactsActions acceptContactRequest:item completion:nil];
}

- (void)declineContactRequest:(id<DWDPBasicUserItem>)item {
    [DWDashPayContactsActions declineContactRequest:item completion:nil];
}

- (void)searchWithQuery:(NSString *)searchQuery {
    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
    NSString *trimmedQuery = [searchQuery stringByTrimmingCharactersInSet:whitespaces] ?: @"";
    if ([self.trimmedQuery isEqualToString:trimmedQuery]) {
        return;
    }

    self.trimmedQuery = trimmedQuery;

    [self updateForced:NO];
}

#pragma mark - DWFetchedResultsDataSourceDelegate

- (void)fetchedResultsDataSourceDidUpdate:(DWFetchedResultsDataSource *)fetchedResultsDataSource {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [self updateForced:YES];
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [self updateForced:YES];
}

#pragma mark - Private

- (void)updateForced:(BOOL)forced {
    NSFetchedResultsController *requestsFRC = self.requestsDataSource.fetchedResultsController;
    requestsFRC.delegate = self;
    NSFetchedResultsController *contactsFRC = self.contactsDataSource.fetchedResultsController;
    contactsFRC.delegate = self;

    if (forced) {
        self.allDataSource = [[DWContactsDataSourceObject alloc] initWithRequestsFRC:requestsFRC
                                                                         contactsFRC:contactsFRC
                                                                        itemsFactory:self.itemsFactory
                                                                            sortMode:self.sortMode];
    }

    if (self.isSearching) {
        self.searchDataSource = [[DWContactsSearchDataSourceObject alloc] initWithContactRequestsFRC:requestsFRC
                                                                                         contactsFRC:contactsFRC
                                                                                        itemsFactory:self.itemsFactory
                                                                                        trimmedQuery:self.trimmedQuery];
    }
    else {
        self.searchDataSource = nil;
    }

    NSParameterAssert(self.delegate);
    [self.delegate contactsModelDidUpdate:self];
}

- (BOOL)isSearching {
    return self.trimmedQuery.length > 0;
}

@end
