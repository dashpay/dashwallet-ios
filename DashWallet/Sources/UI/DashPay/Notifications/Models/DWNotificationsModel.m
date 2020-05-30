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

#import "DWNotificationsModel.h"

#import "DWDPContactRequestActions.h"
#import "DWDPNotificationItemsFactory.h"
#import "DWEnvironment.h"
#import "DWNotificationsContactFetchedDataSource.h"
#import "DWNotificationsDataSourceObject.h"
#import "DWNotificationsIgnoredFetchedDataSource.h"
#import "DWNotificationsIncomingFetchedDataSource.h"
#import "DWNotificationsSection.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsModel () <DWFetchedResultsDataSourceDelegate>

@property (readonly, nonatomic, strong) DWDPNotificationItemsFactory *itemsFactory;

@property (readonly, nonatomic, strong) DWNotificationsDataSourceObject *aggregateDataSource;

@property (nonatomic, strong) DWFetchedResultsDataSource *incomingDataSource;
@property (nonatomic, strong) DWFetchedResultsDataSource *ignoredDataSource;
@property (nonatomic, strong) DWFetchedResultsDataSource *contactsDataSource;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsModel

- (instancetype)init {
    self = [super init];
    if (self) {
        NSDateFormatter *dateFormatter = [NSDateFormatter new];
        _itemsFactory = [[DWDPNotificationItemsFactory alloc] initWithDateFormatter:dateFormatter];
        _aggregateDataSource = [[DWNotificationsDataSourceObject alloc] init];

        [self rebuildFetchedDataSources];
    }
    return self;
}

- (id<DWNotificationsDataSource>)dataSource {
    return self.aggregateDataSource;
}

- (void)rebuildFetchedDataSources {
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    if (!blockchainIdentity) {
        return;
    }

    NSManagedObjectContext *context = [NSManagedObject mainContext];

    _incomingDataSource = [[DWNotificationsIncomingFetchedDataSource alloc] initWithContext:context blockchainIdentity:blockchainIdentity];
    _incomingDataSource.shouldSubscribeToNotifications = YES;
    _incomingDataSource.delegate = self;

    _ignoredDataSource = [[DWNotificationsIgnoredFetchedDataSource alloc] initWithContext:context blockchainIdentity:blockchainIdentity];
    _ignoredDataSource.shouldSubscribeToNotifications = YES;
    _ignoredDataSource.delegate = self;

    _contactsDataSource = [[DWNotificationsContactFetchedDataSource alloc] initWithContext:context blockchainIdentity:blockchainIdentity];
    _contactsDataSource.shouldSubscribeToNotifications = YES;
    _contactsDataSource.delegate = self;
}

- (void)start {
    [self fetchData];

    [self activateFRCs];
}

- (void)stop {
    [self resetFRCs];
}

- (void)fetchData {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *mineBlockchainIdentity = wallet.defaultBlockchainIdentity;
    __weak typeof(self) weakSelf = self;
    [mineBlockchainIdentity fetchContactRequests:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        DSLogVerbose(@"DWDP: Fetch contact requests %@: %@", success ? @"Succeeded" : @"Failed", errors);

        // TODO: temp workaround to force reload contact list
        [strongSelf resetFRCs];
        [strongSelf activateFRCs];
    }];
}

- (void)acceptContactRequest:(id<DWDPBasicItem>)item {
    __weak typeof(self) weakSelf = self;
    [DWDPContactRequestActions
        acceptContactRequest:item
                  completion:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
                      __strong typeof(weakSelf) strongSelf = weakSelf;
                      if (!strongSelf) {
                          return;
                      }

                      DSLogVerbose(@"DWDP: accept contact request %@: %@", success ? @"Succeeded" : @"Failed", errors);

                      // TODO: temp workaround to update and force reload contact list
                      [strongSelf fetchData];
                  }];
}

#pragma mark - DWFetchedResultsDataSourceDelegate

- (void)fetchedResultsDataSourceDidUpdate:(DWFetchedResultsDataSource *)fetchedResultsDataSource {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [self updateDataSource];
    //    [self.delegate contactsModelDidUpdate:self];
}

#pragma mark - Private

- (void)updateDataSource {
    if (!self.incomingDataSource.fetchedResultsController) {
        [self.aggregateDataSource updateWithSections:@[]];

        return;
    }

    DWNotificationsSection *section = [[DWNotificationsSection alloc] initWithFactory:self.itemsFactory
                                                                          incomingFRC:self.incomingDataSource.fetchedResultsController
                                                                           ignoredFRC:self.ignoredDataSource.fetchedResultsController
                                                                          contactsFRC:self.contactsDataSource.fetchedResultsController];
    // TODO: impl new / earlier sections
    [self.aggregateDataSource updateWithSections:@[ section, section ]];
}

- (void)activateFRCs {
    if (!self.incomingDataSource) {
        [self rebuildFetchedDataSources];
    }

    [self.incomingDataSource start];
    [self.ignoredDataSource start];
    [self.contactsDataSource start];

    [self updateDataSource];

    //    [self.delegate contactsModelDidUpdate:self];
}

- (void)resetFRCs {
    [self.incomingDataSource stop];
    [self.ignoredDataSource stop];
    [self.contactsDataSource stop];
}

@end
