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

#import "DWContactsDataSourceObject.h"

#import "DWContactItem.h"
#import "DWIncomingContactItem.h"
#import "DWUIKit.h"
#import "DWUserDetailsCell.h"
#import "DWUserDetailsContactCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsDataSourceObject () <NSFetchedResultsControllerDelegate>

@property (nullable, nonatomic, weak) UITableView *tableView;
@property (nullable, nonatomic, weak) id<DWUserDetailsCellDelegate> userDetailsDelegate;
@property (nullable, nonatomic, weak) id<UITableViewDataSource> emptyDataSource;

@property (readonly, nonatomic, assign, getter=isEmpty) BOOL empty;
@property (nonatomic, assign) BOOL batchReloading;
@property (nullable, nonatomic, strong) NSFetchedResultsController<DSFriendRequestEntity *> *incomingFRC;
@property (nullable, nonatomic, strong) NSFetchedResultsController<DSDashpayUserEntity *> *contactsFRC;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsDataSourceObject

- (void)beginReloading {
    self.batchReloading = YES;
}

- (void)endReloading {
    self.batchReloading = NO;
    [self.tableView reloadData];
    [self checkIfEmpty];
}

- (void)reloadIncomingContactRequests:(NSFetchedResultsController<DSFriendRequestEntity *> *)frc {
    self.incomingFRC = frc;
    self.incomingFRC.delegate = self;

    if (!self.batchReloading) {
        [self.tableView reloadData];
        [self checkIfEmpty];
    }
}

- (void)reloadContacts:(NSFetchedResultsController<DSDashpayUserEntity *> *)frc {
    self.contactsFRC = frc;
    self.contactsFRC.delegate = self;

    if (!self.batchReloading) {
        [self.tableView reloadData];
        [self checkIfEmpty];
    }
}

#pragma mark - DWContactsDataSource

- (void)setupWithTableView:(UITableView *)tableView
       userDetailsDelegate:(id<DWUserDetailsCellDelegate>)userDetailsDelegate
           emptyDataSource:(id<UITableViewDataSource>)emptyDataSource {
    self.tableView = tableView;
    self.userDetailsDelegate = userDetailsDelegate;
    self.emptyDataSource = emptyDataSource;
}

- (BOOL)isEmpty {
    if (self.incomingFRC == nil && self.contactsFRC == nil) {
        return YES;
    }

    const NSInteger count = self.incomingFRC.sections.firstObject.numberOfObjects +
                            self.contactsFRC.sections.firstObject.numberOfObjects;
    return count == 0;
}

- (id<DWUserDetails>)userDetailsAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        DSFriendRequestEntity *entity = [self.incomingFRC objectAtIndexPath:indexPath];
        DWIncomingContactItem *item = [[DWIncomingContactItem alloc] initWithFriendRequestEntity:entity];
        return item;
    }
    else {
        NSIndexPath *transformedIndexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:0];
        DSDashpayUserEntity *entity = [self.contactsFRC objectAtIndexPath:transformedIndexPath];
        DWContactItem *item = [[DWContactItem alloc] initWithDashpayUserEntity:entity];
        return item;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.incomingFRC.sections.firstObject.numberOfObjects;
    }
    else {
        return self.contactsFRC.sections.firstObject.numberOfObjects;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWUserDetailsCell *cell = nil;
    if (indexPath.section == 0) {
        NSString *cellId = DWUserDetailsCell.dw_reuseIdentifier;
        cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                               forIndexPath:indexPath];
        cell.delegate = self.userDetailsDelegate;
    }
    else {
        NSString *cellId = DWUserDetailsContactCell.dw_reuseIdentifier;
        cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                               forIndexPath:indexPath];
    }

    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");
    [self.tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller
    didChangeObject:(id)anObject
        atIndexPath:(nullable NSIndexPath *)indexPath
      forChangeType:(NSFetchedResultsChangeType)type
       newIndexPath:(nullable NSIndexPath *)newIndexPath {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    UITableView *tableView = self.tableView;

    switch (type) {
        case NSFetchedResultsChangeInsert: {
            NSIndexPath *transformedNewIndexPath = [self transformIndexPath:newIndexPath controller:controller];
            [tableView insertRowsAtIndexPaths:@[ transformedNewIndexPath ]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
        }
        case NSFetchedResultsChangeDelete: {
            NSIndexPath *transformedIndexPath = [self transformIndexPath:indexPath controller:controller];
            [tableView deleteRowsAtIndexPaths:@[ transformedIndexPath ]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
        }
        case NSFetchedResultsChangeMove: {
            NSIndexPath *transformedIndexPath = [self transformIndexPath:indexPath controller:controller];
            NSIndexPath *transformedNewIndexPath = [self transformIndexPath:newIndexPath controller:controller];
            [tableView moveRowAtIndexPath:transformedIndexPath
                              toIndexPath:transformedNewIndexPath];
            break;
        }
        case NSFetchedResultsChangeUpdate: {
            NSIndexPath *transformedIndexPath = [self transformIndexPath:indexPath controller:controller];
            [self configureCell:[tableView cellForRowAtIndexPath:transformedIndexPath]
                    atIndexPath:indexPath];
            break;
        }
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [self.tableView endUpdates];

    [self checkIfEmpty];
}

#pragma mark - Private

- (NSIndexPath *)transformIndexPath:(NSIndexPath *)indexPath controller:(NSFetchedResultsController *)controller {
    if (controller == self.incomingFRC) {
        return indexPath;
    }
    else {
        return [NSIndexPath indexPathForRow:indexPath.row inSection:1];
    }
}

- (void)configureCell:(DWUserDetailsCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    id<DWUserDetails> userDetails = [self userDetailsAtIndexPath:indexPath];
    cell.userDetails = userDetails;
}

- (void)checkIfEmpty {
    id<UITableViewDataSource> oldDataSource = self.tableView.dataSource;
    if (self.isEmpty) {
        self.tableView.dataSource = self.emptyDataSource;
    }
    else {
        self.tableView.dataSource = self;
    }

    if (oldDataSource != self.tableView.dataSource) {
        [self.tableView reloadData];
    }
}

@end
