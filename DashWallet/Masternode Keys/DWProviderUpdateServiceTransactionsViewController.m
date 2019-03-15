//
//  DWProviderUpdateServiceTransactionsViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 3/3/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWProviderUpdateServiceTransactionsViewController.h"
#import "DSLocalMasternode.h"
#import "DWProviderUpdateServiceTableViewCell.h"
#import "DSProviderUpdateServiceTransaction.h"
#import "NSData+Bitcoin.h"
#import "NSString+Dash.h"
#include <arpa/inet.h>

@interface DWProviderUpdateServiceTransactionsViewController ()

@end

@implementation DWProviderUpdateServiceTransactionsViewController

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
    return self.localMasternode.providerUpdateServiceTransactions.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * reuseIdentifier = @"ServiceTransactionCellIdentifier";
    DWProviderUpdateServiceTableViewCell *cell = (DWProviderUpdateServiceTableViewCell*)[tableView dequeueReusableCellWithIdentifier:reuseIdentifier forIndexPath:indexPath];
    
    DSProviderUpdateServiceTransaction * transaction = [self.localMasternode.providerUpdateServiceTransactions objectAtIndex:indexPath.row];
    
    cell.blockHeightLabel.text = [NSString stringWithFormat:@"%d",transaction.blockHeight];
    cell.operatorRewardPayoutAddressLabel.text = (transaction.scriptPayout.length?[NSString addressWithScriptPubKey:transaction.scriptPayout onChain:transaction.chain]:@"");
    char s[INET6_ADDRSTRLEN];
    uint32_t ipAddress = transaction.ipAddress.u32[3];
    cell.locationLabel.text = [NSString stringWithFormat:@"%s:%d",inet_ntop(AF_INET, &ipAddress, s, sizeof(s)),self.localMasternode.port];
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
