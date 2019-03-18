//
//  DWMasternodeViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 6/10/18.
//  Copyright © 2018 Dash Core Group. All rights reserved.
//

#import "DWMasternodeViewController.h"
#import "DWMasternodeTableViewCell.h"
#import <DashSync/DashSync.h>
#import <arpa/inet.h>
#import "DWRegisterMasternodeViewController.h"
#import "DWMasternodeDetailViewController.h"
#import "DWEnvironment.h"

@interface DWMasternodeViewController ()
@property (nonatomic,strong) NSFetchedResultsController * fetchedResultsController;
@property (nonatomic,strong) NSString * searchString;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *registerButton;
@property (nonatomic,strong) DSChain * chain;

@end

@implementation DWMasternodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.chain = [DWEnvironment sharedInstance].currentChain;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Automation KVO

-(NSManagedObjectContext*)managedObjectContext {
    return [NSManagedObject context];
}

-(NSPredicate*)searchPredicate {
    // Get all shapeshifts that have been received by shapeshift.io or all shapeshifts that have no deposits but where we can verify a transaction has been pushed on the blockchain
    if (self.searchString && ![self.searchString isEqualToString:@""]) {
        if ([self.searchString isEqualToString:@"0"] || [self.searchString longLongValue]) {
            NSArray * ipArray = [self.searchString componentsSeparatedByString:@"."];
            NSMutableArray *partPredicates = [NSMutableArray array];
            NSPredicate * chainPredicate = [NSPredicate predicateWithFormat:@"chain == %@",self.chain.chainEntity];
            [partPredicates addObject:chainPredicate];
            for (int i = 0; i< MIN(ipArray.count,4); i++) {
                if ([ipArray[i] isEqualToString:@""]) break;
                NSPredicate *currentPartPredicate = [NSPredicate predicateWithFormat:@"(((address >> %@) & 255) == %@)", @(24-i*8),@([ipArray[i] integerValue])];
                [partPredicates addObject:currentPartPredicate];
            }
            
            return [NSCompoundPredicate andPredicateWithSubpredicates:partPredicates];
        } else {
            return [NSPredicate predicateWithFormat:@"chain == %@",self.chain.chainEntity];
        }
        
    } else {
        return [NSPredicate predicateWithFormat:@"chain == %@",self.chain.chainEntity];
    }
    
}

- (NSFetchedResultsController *)fetchedResultsController
{
    if (_fetchedResultsController) return _fetchedResultsController;
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
    NSArray *sortDescriptors = @[claimSortDescriptor,addressSortDescriptor,portSortDescriptor];
    
    [fetchRequest setSortDescriptors:sortDescriptors];
    
    NSPredicate *filterPredicate = [self searchPredicate];
    [fetchRequest setPredicate:filterPredicate];
    
    // Edit the section name key path and cache name if appropriate.
    // nil for section name key path means "no sections".
    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:self.managedObjectContext sectionNameKeyPath:@"localMasternode" cacheName:nil];
    _fetchedResultsController = aFetchedResultsController;
    aFetchedResultsController.delegate = self;
    NSError *error = nil;
    if (![aFetchedResultsController performFetch:&error]) {
        // Replace this implementation with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    
    return aFetchedResultsController;
}

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    
}


- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {
    
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)changeType
      newIndexPath:(NSIndexPath *)newIndexPath {
    
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    
    
}

#pragma mark - Table view data source

-(NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self.fetchedResultsController sections].count == 1 || section) {
        return NSLocalizedString(@"Masternodes",nil);
    } else {
        return NSLocalizedString(@"My Masternodes",nil);
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    
    return [[self.fetchedResultsController sections] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id<NSFetchedResultsSectionInfo> sectionInfo = [[self.fetchedResultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

-(void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.registerButton setEnabled:FALSE];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWMasternodeTableViewCell *cell = (DWMasternodeTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"MasternodeTableViewCellIdentifier" forIndexPath:indexPath];
    
    // Configure the cell...
    [self configureCell:cell atIndexPath:indexPath];
    return cell;
}


-(void)configureCell:(DWMasternodeTableViewCell*)cell atIndexPath:(NSIndexPath *)indexPath {
    DSSimplifiedMasternodeEntryEntity *simplifiedMasternodeEntryEntity = [self.fetchedResultsController objectAtIndexPath:indexPath];
    char s[INET6_ADDRSTRLEN];
    uint32_t ipAddress = CFSwapInt32BigToHost(simplifiedMasternodeEntryEntity.address);
    cell.masternodeLocationLabel.text = [NSString stringWithFormat:@"%s:%d",inet_ntop(AF_INET, &ipAddress, s, sizeof(s)),simplifiedMasternodeEntryEntity.port];
    cell.outputLabel.text = [NSString stringWithFormat:@"%@",simplifiedMasternodeEntryEntity.providerRegistrationTransactionHash];
}

-(void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    self.searchString = @"0";
    _fetchedResultsController = nil;
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    self.searchString = searchBar.text;
    _fetchedResultsController = nil;
    [self.tableView reloadData];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"MasternodeDetailSegue"]) {
        NSIndexPath * indexPath = self.tableView.indexPathForSelectedRow;
        DSSimplifiedMasternodeEntryEntity *simplifiedMasternodeEntryEntity = [self.fetchedResultsController objectAtIndexPath:indexPath];
        DWMasternodeDetailViewController * masternodeDetailViewController = (DWMasternodeDetailViewController*)segue.destinationViewController;
        masternodeDetailViewController.simplifiedMasternodeEntry = simplifiedMasternodeEntryEntity.simplifiedMasternodeEntry;
        masternodeDetailViewController.localMasternode = simplifiedMasternodeEntryEntity.localMasternode?[simplifiedMasternodeEntryEntity.localMasternode loadLocalMasternode]:nil;
    } else if ([segue.identifier isEqualToString:@"RegisterMasternodeSegue"]) {
        UINavigationController * navigationController = (UINavigationController*)segue.destinationViewController;
        DWRegisterMasternodeViewController * registerMasternodeViewController = (DWRegisterMasternodeViewController*)navigationController.topViewController;
        registerMasternodeViewController.chain = self.chain;
    }
}
@end
