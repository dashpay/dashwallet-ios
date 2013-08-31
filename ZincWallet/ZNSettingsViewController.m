//
//  ZNSettingsViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/11/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "ZNSettingsViewController.h"
#import "ZNSeedViewController.h"
#import "ZNWallet.h"
#import "ZNTransactionEntity.h"
#import "ZNTxInputEntity.h"
#import "ZNTxOutputEntity.h"
#import <QuartzCore/QuartzCore.h>

#define TRANSACTION_CELL_HEIGHT 75

@interface ZNSettingsViewController ()

@property (nonatomic, strong) NSArray *transactions;
@property (nonatomic, strong) id balanceObserver;
@property (nonatomic, strong) UIImageView *wallpaper;
@property (nonatomic, assign) CGPoint wallpaperStart;

@end

@implementation ZNSettingsViewController

//TODO: need settings for denomination (BTC, mBTC or uBTC), local currency, and exchange rate source
//TODO: only show most recent 10-20 transactions and have a separate page for the rest with section headers for each day

//XXXX BUG: breifly saw double transactions immediately after sending a payment (probably from websocket and tx publish)
// corrected itself on wallet sync

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;

    ZNWallet *w = [ZNWallet sharedInstance];
    
    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:walletBalanceNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:w.balance],
                                         [w localCurrencyStringForAmount:w.balance]];
            
            self.transactions = w.recentTransactions;
            
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
             withRowAnimation:UITableViewRowAnimationAutomatic];
        }];
    
    self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:w.balance],
                                 [w localCurrencyStringForAmount:w.balance]];
    
    if ([self.navigationController.navigationBar respondsToSelector:@selector(shadowImage)]) {
        [self.navigationController.navigationBar setShadowImage:[UIImage new]];
    }
    
    self.navigationController.navigationBar.backgroundColor =
        [UIColor colorWithPatternImage:[UIImage imageNamed:@"navbar-bg.png"]];
    
    self.wallpaper = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"wallpaper-default.png"]];
    self.wallpaperStart = self.wallpaper.center = CGPointMake(self.wallpaper.center.x, self.wallpaper.center.y + 20);
    
    [self.navigationController.view insertSubview:self.wallpaper atIndex:0];
    
    self.navigationController.delegate = self;
}

- (void)viewWillUnload
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.transactions = [[ZNWallet sharedInstance] recentTransactions];
}

#pragma mark - IBAction

- (IBAction)done:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    switch (section) {
        case 0: return self.transactions.count ? self.transactions.count : 1;
        case 1: return 2;
        case 2: return 1;
        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, section);
    }

    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *disclosureIdent = @"ZNDisclosureCell", *transactionIdent = @"ZNTransactionCell",
                    *actionIdent = @"ZNActionCell";
    UITableViewCell *cell = nil;
    __block UILabel *textLabel, *detailTextLabel, *unconfirmedLabel, *sentLabel, *noTxLabel, *localCurrencyLabel;
    
    // Configure the cell...
    switch (indexPath.section) {
        case 0:
            cell = [tableView dequeueReusableCellWithIdentifier:transactionIdent];
            
            textLabel = (id)[cell viewWithTag:1];
            detailTextLabel = (id)[cell viewWithTag:2];
            unconfirmedLabel = (id)[cell viewWithTag:3];
            noTxLabel = (id)[cell viewWithTag:4];
            localCurrencyLabel = (id)[cell viewWithTag:5];
            sentLabel = (id)[cell viewWithTag:6];

            if (! self.transactions.count) {
                noTxLabel.hidden = NO;
                textLabel.text = nil;
                localCurrencyLabel.text = nil;
                detailTextLabel.text = nil;
                unconfirmedLabel.hidden = YES;
                sentLabel.hidden = YES;
            }
            else {
                ZNWallet *w = [ZNWallet sharedInstance];
                ZNTransactionEntity *tx = self.transactions[indexPath.row];
                __block uint64_t received = 0, spent = 0;
                int height = -1;
                
                [tx.inputs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    ZNTxInputEntity *i = obj;

                    if (i.address && [w containsAddress:i.address]) spent += i.value;
                }];

                __block BOOL withinWallet = spent > 0 ? YES : NO;
                
                [tx.outputs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    ZNTxOutputEntity *o = obj;
                    
                    if (o.address && [w containsAddress:o.address]) {
                        received += o.value;
                        if (spent == 0) detailTextLabel.text = [@"to: " stringByAppendingString:o.address];
                    }
                    else if (spent > 0) {
                        if (o.address) detailTextLabel.text = [@"to: " stringByAppendingString:o.address];
                        withinWallet = NO;
                    }
                }];
                
                noTxLabel.hidden = YES;
                sentLabel.hidden = YES;
                unconfirmedLabel.hidden = NO;
                unconfirmedLabel.layer.cornerRadius = 3.0;
                sentLabel.layer.cornerRadius = 3.0;
                sentLabel.layer.borderWidth = 0.5;
                
                if (tx.blockHeight) height = w.lastBlockHeight - tx.blockHeight;
                
                if (height < 1) unconfirmedLabel.text = @"unconfirmed";
                else if (height <= 6) {
                    unconfirmedLabel.text =
                        [NSString stringWithFormat:@"%d confirmation%@", height, height > 1 ? @"s" : @""];
                }
                else {
                    unconfirmedLabel.hidden = YES;
                    sentLabel.hidden = NO;
                }

                if (withinWallet) {
                    textLabel.text = [w stringForAmount:spent];
                    localCurrencyLabel.text =
                        [NSString stringWithFormat:@"(%@)", [w localCurrencyStringForAmount:spent]];
                    detailTextLabel.text = @"within wallet";
                    sentLabel.text = @"moved";
                }
                else if (spent > 0) {
                    textLabel.text = [w stringForAmount:received - spent];
                    localCurrencyLabel.text =
                        [NSString stringWithFormat:@"(%@)", [w localCurrencyStringForAmount:received - spent]];
                    sentLabel.text = @"sent";
                    sentLabel.textColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.67];
                }
                else {
                    textLabel.text = [w stringForAmount:received];
                    localCurrencyLabel.text =
                       [NSString stringWithFormat:@"(%@)", [w localCurrencyStringForAmount:received]];
                    sentLabel.text = @"recieved";
                    sentLabel.textColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                }

                CGRect f = unconfirmedLabel.frame;
                
                f.size.width = [unconfirmedLabel.text sizeWithFont:unconfirmedLabel.font].width + 10;
                unconfirmedLabel.frame = f;
                f.size.width = [sentLabel.text sizeWithFont:sentLabel.font].width + 10;
                sentLabel.frame = f;
                sentLabel.layer.borderColor = sentLabel.textColor.CGColor;
                
                if (! detailTextLabel.text) detailTextLabel.text = @"can't decode payment address";
            }
            break;
            
        case 1:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            if (! cell.backgroundView) {
                UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, -1, cell.frame.size.width, 1)];
                
                cell.backgroundView = [[UIView alloc] initWithFrame:cell.frame];
                cell.backgroundView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.67];
                v.backgroundColor = tableView.separatorColor;
                [cell.backgroundView addSubview:v];
                v = [[UIView alloc] initWithFrame:CGRectMake(0, cell.frame.size.height - 1, cell.frame.size.width, 1)];
                v.backgroundColor = tableView.separatorColor;
                [cell.backgroundView addSubview:v];
            }
            
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"about";
                    break;

                case 1:
                    cell.textLabel.text = @"backup phrase";
                    break;
                    
                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__, indexPath.row);
            }
            break;
            
        case 2:
            cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
            if (! cell.backgroundView) {
                UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, -1.0, cell.frame.size.width, 1.0)];
                
                cell.backgroundView = [[UIView alloc] initWithFrame:cell.frame];
                cell.selectedBackgroundView = [[UIView alloc] initWithFrame:cell.frame];
                cell.backgroundView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.67];
                cell.selectedBackgroundView.backgroundColor =
                    [UIColor colorWithPatternImage:[UIImage imageNamed:@"redgradient.png"]];
                v.backgroundColor = tableView.separatorColor;
                [cell.backgroundView addSubview:v];
                cell.textLabel.textColor = [UIColor redColor];
                cell.textLabel.shadowColor = [UIColor clearColor];
            }

            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"restore or start a new wallet";
                    break;
                                        
                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__, indexPath.row);
            }
            break;
            
        default:
            NSAssert(FALSE, @"%s:%d %s: unkown indexPath.section %d", __FILE__, __LINE__,  __func__, indexPath.section);
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0: return nil;//@"recent transactions";
        case 1: return nil;//@"settings";
        case 2: return @"caution ⇣";
        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, section);
    }
    
    return nil;
}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0:
            return TRANSACTION_CELL_HEIGHT;

        case 1:
            switch (indexPath.row) {
                case 0:
                    return 44;

                case 1:
                    return 44;
                    
                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__, indexPath.row);
            }
            return 44;
            
        case 2:
            return 44;

        default:
            NSAssert(FALSE, @"%s:%d %s: unkown indexPath.section %d", __FILE__, __LINE__,  __func__, indexPath.section);
    }
    
    return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    CGFloat h = 0;
    
    switch (section) {
        case 0:
            return 22;
            
        case 1:
            return 22;
            
        case 2:
            h = tableView.frame.size.height - self.navigationController.navigationBar.frame.size.height;
            
            for (int s = 0; s < section; s++) {
                h -= [self tableView:tableView heightForHeaderInSection:s];

                for (int r = 0; r < [self tableView:tableView numberOfRowsInSection:s]; r++) {
                    h -= [self tableView:tableView heightForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s]];
                }
            }

            return h > 55 ? h : 55;
        
        default:
            NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, section);
    }

    return 22;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10, v.frame.size.height - 22.0,
                                                           self.view.frame.size.width - 20, 22.0)];;
    
    l.text = [self tableView:tableView titleForHeaderInSection:section];
    l.backgroundColor = [UIColor clearColor];
    l.font = [UIFont fontWithName:@"HelveticaNeue" size:15];
    l.textColor = [UIColor grayColor];
    l.shadowColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    l.shadowOffset = CGSizeMake(0.0, 1.0);
    v.backgroundColor = [UIColor clearColor];
    [v addSubview:l];
    
    return v;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Navigation logic may go here. Create and push another view controller.

    //XXX should have some option to generate a new wallet and sweep old balance if backup may be compromized

    switch (indexPath.section) {
        case 0:
            //XXX show transaction details
            break;
            
        case 1:
            switch (indexPath.row) {
                case 0:                    
                    [self.navigationController pushViewController:[self.storyboard
                     instantiateViewControllerWithIdentifier:@"ZNAboutViewController"] animated:YES];
                    break;
                    
                case 1:
                    [[[UIAlertView alloc] initWithTitle:@"WARNING" message:@"DO NOT let anyone see your backup phrase "
                      "or they can spend your bitcoins." delegate:self cancelButtonTitle:@"cancel"
                      otherButtonTitles:@"show", nil] show];
                    break;
                    
                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__, indexPath.row);
            }
            break;
            
        // section 2 is handled in storyboard
        case 2:
            break;
            
        default:
            NSAssert(FALSE, @"%s:%d %s: unkown indexPath.section %d", __FILE__, __LINE__,  __func__, indexPath.section);
    }
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController
didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
}

- (void)navigationController:(UINavigationController *)navigationController
willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (! animated) return;
    
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration*2 animations:^{
        if (viewController != self) {
            self.wallpaper.center = CGPointMake(self.wallpaperStart.x - self.view.frame.size.width*PARALAX_RATIO,
                                                self.wallpaperStart.y);
        }
        else self.wallpaper.center = self.wallpaperStart;
    }];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        return;
    }
    
    ZNSeedViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNSeedViewController"];

    [self.navigationController pushViewController:c animated:YES];
}

@end
