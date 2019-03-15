//
//  DWProviderUpdateRegistrarTransactionsViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 3/3/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWProviderUpdateRegistrarTransactionsViewController.h"
#import "DWProviderUpdateRegistrarTableViewCell.h"

@interface DWProviderUpdateRegistrarTransactionsViewController ()

@end

@implementation DWProviderUpdateRegistrarTransactionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.localMasternode.providerUpdateRegistrarTransactions.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * reuseIdentifier = @"RegistrarTransactionCellIdentifier";
    DWProviderUpdateRegistrarTableViewCell *cell = (DWProviderUpdateRegistrarTableViewCell*)[tableView dequeueReusableCellWithIdentifier:reuseIdentifier forIndexPath:indexPath];
    
    DSProviderUpdateRegistrarTransaction * transaction = [self.localMasternode.providerUpdateRegistrarTransactions objectAtIndex:indexPath.row];
    
    cell.blockHeightLabel.text = [NSString stringWithFormat:@"%d",transaction.blockHeight];
    cell.operatorKeyLabel.text = [NSData dataWithUInt384:transaction.operatorKey].hexString;
    cell.payToAddressLabel.text = [NSString addressWithScriptPubKey:transaction.scriptPayout onChain:transaction.chain];
    
    return cell;
}


/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
