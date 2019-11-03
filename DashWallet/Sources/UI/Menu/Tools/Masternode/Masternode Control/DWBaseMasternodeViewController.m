//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWBaseMasternodeViewController.h"

#import "DWEnvironment.h"
#import "DWMasternodeTableViewCell.h"
#import <arpa/inet.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const DWBaseMasternodeViewControllerCellId = @"MasternodeTableViewCellIdentifier";

@interface DWBaseMasternodeViewController ()

@property (nullable, copy, nonatomic) NSString *searchString;

@end

@implementation DWBaseMasternodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.chain = [DWEnvironment sharedInstance].currentChain;

    self.tableView.rowHeight = 93.0;

    UINib *nib = [UINib nibWithNibName:@"DWMasternodeTableViewCell" bundle:nil];
    NSParameterAssert(nib);
    [self.tableView registerNib:nib forCellReuseIdentifier:DWBaseMasternodeViewControllerCellId];
}

- (void)updateSearchString:(NSString *)searchString {
    self.searchString = searchString;
    _fetchedResultsController = nil;
    [self.tableView reloadData];
}

#pragma mark - FRC

- (NSManagedObjectContext *)managedObjectContext {
    return [NSManagedObject context];
}

- (NSPredicate *)searchPredicate {
    // Get all shapeshifts that have been received by shapeshift.io or all shapeshifts that have no deposits but where we can verify a transaction has been pushed on the blockchain
    if (self.searchString && ![self.searchString isEqualToString:@""]) {
        if ([self.searchString isEqualToString:@"0"] || [self.searchString longLongValue]) {
            NSArray *ipArray = [self.searchString componentsSeparatedByString:@"."];
            NSMutableArray *partPredicates = [NSMutableArray array];
            NSPredicate *chainPredicate = [NSPredicate predicateWithFormat:@"chain == %@", self.chain.chainEntity];
            [partPredicates addObject:chainPredicate];
            for (int i = 0; i < MIN(ipArray.count, 4); i++) {
                if ([ipArray[i] isEqualToString:@""])
                    break;
                NSPredicate *currentPartPredicate = [NSPredicate predicateWithFormat:@"(((address >> %@) & 255) == %@)", @(24 - i * 8), @([ipArray[i] integerValue])];
                [partPredicates addObject:currentPartPredicate];
            }

            return [NSCompoundPredicate andPredicateWithSubpredicates:partPredicates];
        }
        else {
            return [NSPredicate predicateWithFormat:@"chain == %@", self.chain.chainEntity];
        }
    }
    else {
        return [NSPredicate predicateWithFormat:@"chain == %@", self.chain.chainEntity];
    }
}

- (NSFetchedResultsController *)fetchedResultsController {
    if (_fetchedResultsController)
        return _fetchedResultsController;
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    // Edit the entity name as appropriate.
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"DSSimplifiedMasternodeEntryEntity" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];

    // Set the batch size to a suitable number.
    [fetchRequest setFetchBatchSize:20];

    // Edit the sort key as appropriate.
    NSSortDescriptor *claimSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"localMasternode" ascending:NO];
    NSSortDescriptor *addressSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"address" ascending:YES];
    NSSortDescriptor *portSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"port" ascending:YES];
    NSArray *sortDescriptors = @[ claimSortDescriptor, addressSortDescriptor, portSortDescriptor ];

    [fetchRequest setSortDescriptors:sortDescriptors];

    NSPredicate *filterPredicate = [self searchPredicate];
    [fetchRequest setPredicate:filterPredicate];

    // Edit the section name key path and cache name if appropriate.
    // nil for section name key path means "no sections".
    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:self.managedObjectContext sectionNameKeyPath:@"localMasternode" cacheName:nil];
    _fetchedResultsController = aFetchedResultsController;
    NSError *error = nil;
    if (![aFetchedResultsController performFetch:&error]) {
        // Replace this implementation with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }

    return aFetchedResultsController;
}


#pragma mark - TableView

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self.fetchedResultsController sections].count == 1 || section) {
        return NSLocalizedString(@"Masternodes", nil);
    }
    else {
        return NSLocalizedString(@"My Masternodes", nil);
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [[self.fetchedResultsController sections] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id<NSFetchedResultsSectionInfo> sectionInfo = [[self.fetchedResultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWMasternodeTableViewCell *cell = (DWMasternodeTableViewCell *)[tableView dequeueReusableCellWithIdentifier:DWBaseMasternodeViewControllerCellId forIndexPath:indexPath];

    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

- (void)configureCell:(DWMasternodeTableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    DSSimplifiedMasternodeEntryEntity *simplifiedMasternodeEntryEntity = [self.fetchedResultsController objectAtIndexPath:indexPath];
    char s[INET6_ADDRSTRLEN];
    uint32_t ipAddress = CFSwapInt32BigToHost(simplifiedMasternodeEntryEntity.address);
    cell.masternodeLocationLabel.text = [NSString stringWithFormat:@"%s:%d", inet_ntop(AF_INET, &ipAddress, s, sizeof(s)), simplifiedMasternodeEntryEntity.port];
    cell.outputLabel.text = [NSString stringWithFormat:@"%@", simplifiedMasternodeEntryEntity.providerRegistrationTransactionHash];
}

@end

NS_ASSUME_NONNULL_END
