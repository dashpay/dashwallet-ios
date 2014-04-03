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
#import "ZNWalletManager.h"
#import "ZNWallet.h"
#import "ZNPeerManager.h"
#import "ZNTransaction.h"
#import "ZNStoryboardSegue.h"
#import <QuartzCore/QuartzCore.h>

#define TRANSACTION_CELL_HEIGHT 75

@interface ZNSettingsViewController ()

@property (nonatomic, strong) NSArray *transactions;
@property (nonatomic, strong) id balanceObserver, txStatusObserver;
@property (nonatomic, strong) UIImageView *wallpaper;
@property (nonatomic, assign) CGPoint wallpaperStart;

@end

@implementation ZNSettingsViewController

//TODO: need settings for denomination (BTC, mBTC or uBTC), local currency, and exchange rate source
//TODO: only show most recent 10-20 transactions and have a separate page for the rest with section headers for each day
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:ZNWalletBalanceChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            ZNWallet *w = [[ZNWalletManager sharedInstance] wallet];

            if (! w) return;
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)",
                                         [[ZNWalletManager sharedInstance] stringForAmount:w.balance],
                                         [[ZNWalletManager sharedInstance] localCurrencyStringForAmount:w.balance]];

            self.transactions = [NSArray arrayWithArray:w.recentTransactions];
            
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
             withRowAnimation:UITableViewRowAnimationAutomatic];
        }];

    self.txStatusObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:ZNPeerManagerTxStatusNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            ZNWallet *w = [[ZNWalletManager sharedInstance] wallet];

            if (! w) return;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
             withRowAnimation:UITableViewRowAnimationAutomatic];
        }];

    ZNWallet *w = [[ZNWalletManager sharedInstance] wallet];

    self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)",
                                 [[ZNWalletManager sharedInstance] stringForAmount:w.balance],
                                 [[ZNWalletManager sharedInstance] localCurrencyStringForAmount:w.balance]];
    
    self.wallpaper = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"wallpaper-default.png"]];
    self.wallpaperStart = self.wallpaper.center;
    
    [self.navigationController.view insertSubview:self.wallpaper atIndex:0];
    
    self.navigationController.delegate = self;
}

- (void)dealloc
{
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.transactions = [NSArray arrayWithArray:[[[ZNWalletManager sharedInstance] wallet] recentTransactions]];
}

- (void)setBackgroundForCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)path
{
    if (! cell.backgroundView) {
        UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.frame.size.width, 0.5)];
        
        v.tag = 100;
        cell.backgroundView = [[UIView alloc] initWithFrame:cell.frame];
        cell.backgroundView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.67];
        v.backgroundColor = self.tableView.separatorColor;
        [cell.backgroundView addSubview:v];
        v = [[UIView alloc] initWithFrame:CGRectMake(0, cell.frame.size.height - 0.5, cell.frame.size.width, 0.5)];
        v.tag = 101;
        v.backgroundColor = self.tableView.separatorColor;
        [cell.backgroundView addSubview:v];
    }
    
    [cell viewWithTag:100].frame = CGRectMake(path.row == 0 ? 0 : 15, 0, cell.frame.size.width, 0.5);
    [cell viewWithTag:101].hidden = (path.row + 1 < [self tableView:self.tableView numberOfRowsInSection:path.section]);
}

#pragma mark - IBAction

- (IBAction)done:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0: return self.transactions.count ? self.transactions.count : 1;
        case 1: return 2;
        case 2: return 1;
        case 3: return 1;
        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)section);
    }

    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *disclosureIdent = @"ZNDisclosureCell", *transactionIdent = @"ZNTransactionCell",
                    *actionIdent = @"ZNActionCell", *restoreIdent = @"ZNRestoreCell";
    UITableViewCell *cell = nil;
    __block UILabel *textLabel, *detailTextLabel, *unconfirmedLabel, *sentLabel, *noTxLabel, *localCurrencyLabel;
    
    switch (indexPath.section) {
        case 0:
            cell = [tableView dequeueReusableCellWithIdentifier:transactionIdent];
            [self setBackgroundForCell:cell atIndexPath:indexPath];
            
            textLabel = (id)[cell viewWithTag:1];
            detailTextLabel = (id)[cell viewWithTag:2];
            unconfirmedLabel = (id)[cell viewWithTag:3];
            noTxLabel = (id)[cell viewWithTag:4];
            localCurrencyLabel = (id)[cell viewWithTag:5];
            sentLabel = (id)[cell viewWithTag:6];

            if (self.transactions.count == 0) {
                noTxLabel.hidden = NO;
                textLabel.text = nil;
                localCurrencyLabel.text = nil;
                detailTextLabel.text = nil;
                unconfirmedLabel.hidden = YES;
                sentLabel.hidden = YES;
            }
            else {
                ZNWalletManager *m = [ZNWalletManager sharedInstance];
                ZNTransaction *tx = self.transactions[indexPath.row];
                uint64_t received = [m.wallet amountReceivedFromTransaction:tx],
                         sent = [m.wallet amountSentByTransaction:tx];
                NSUInteger confirms = (tx.blockHeight != TX_UNCONFIRMED) ?
                                      ([[ZNPeerManager sharedInstance] lastBlockHeight] - tx.blockHeight) + 1 : 0;
                NSString *address = [m.wallet addressForTransaction:tx];

                noTxLabel.hidden = YES;
                sentLabel.hidden = YES;
                unconfirmedLabel.hidden = NO;
                unconfirmedLabel.layer.cornerRadius = 3.0;
                unconfirmedLabel.backgroundColor = [UIColor lightGrayColor];
                sentLabel.layer.cornerRadius = 3.0;
                sentLabel.layer.borderWidth = 0.5;

                if (confirms == 0 && ! [m.wallet transactionIsValid:tx]) {
                    unconfirmedLabel.text = @"INVALID";
                    unconfirmedLabel.backgroundColor = [UIColor redColor];
                }
                else if (confirms == 0 && ! [[ZNPeerManager sharedInstance] transactionIsVerified:tx.txHash]) {
                    unconfirmedLabel.text = @"unverified";
                }
                else if (confirms < 6) {
                    unconfirmedLabel.text =
                        [NSString stringWithFormat:@"%d confirmation%@", (int)confirms, (confirms == 1) ? @"" : @"s"];
                }
                else {
                    unconfirmedLabel.hidden = YES;
                    sentLabel.hidden = NO;
                }

                if (! address || (sent > 0 && [m.wallet containsAddress:address])) {
                    textLabel.text = [m stringForAmount:sent];
                    localCurrencyLabel.text =
                        [NSString stringWithFormat:@"(%@)", [m localCurrencyStringForAmount:sent]];
                    detailTextLabel.text = @"within wallet";
                    sentLabel.text = @"moved";
                }
                else if (sent > 0) {
                    textLabel.text = [m stringForAmount:received - sent];
                    detailTextLabel.text = [@"to: " stringByAppendingString:address];
                    localCurrencyLabel.text =
                        [NSString stringWithFormat:@"(%@)", [m localCurrencyStringForAmount:received - sent]];
                    sentLabel.text = @"sent";
                    sentLabel.textColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.67];
                }
                else {
                    textLabel.text = [m stringForAmount:received];
                    detailTextLabel.text = [@"to: " stringByAppendingString:address];
                    localCurrencyLabel.text =
                        [NSString stringWithFormat:@"(%@)", [m localCurrencyStringForAmount:received]];
                    sentLabel.text = @"received";
                    sentLabel.textColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                }

                if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_6_1) {
                    CGRect f = unconfirmedLabel.frame;

                    f.size.width = [unconfirmedLabel.text
                                    sizeWithAttributes:@{NSFontAttributeName:unconfirmedLabel.font}].width + 10;
                    unconfirmedLabel.frame = f;
                    f.size.width = [sentLabel.text sizeWithAttributes:@{NSFontAttributeName:sentLabel.font}].width + 10;
                    sentLabel.frame = f;
                }
                sentLabel.layer.borderColor = sentLabel.textColor.CGColor;
                
                if (! detailTextLabel.text) detailTextLabel.text = @"can't decode payment address";
            }
            break;
            
        case 1:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            [self setBackgroundForCell:cell atIndexPath:indexPath];

            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"about";
                    break;

                case 1:
                    cell.textLabel.text = @"backup phrase";
                    break;
                    
                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__,
                             (int)indexPath.row);
            }
            break;
            
        case 2:
            cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
            [self setBackgroundForCell:cell atIndexPath:indexPath];
            cell.textLabel.text = @"rescan blockchain";
            break;

        case 3:
            cell = [tableView dequeueReusableCellWithIdentifier:restoreIdent];
            [self setBackgroundForCell:cell atIndexPath:indexPath];
            break;

        default:
            NSAssert(FALSE, @"%s:%d %s: unkown indexPath.section %d", __FILE__, __LINE__,  __func__,
                     (int)indexPath.section);
    }
    
    return cell;
}

//- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
//{
//    switch (section) {
//        case 0: return nil;//@"recent transactions";
//        case 1: return nil;//@"settings";
//        case 2: return nil;//@"caution";
//        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, section);
//    }
//    
//    return nil;
//}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0:
            return TRANSACTION_CELL_HEIGHT;

        case 1:
            return 44;
            
        case 2:
            return 44;

        case 3:
            return 44;

        default:
            NSAssert(FALSE, @"%s:%d %s: unkown indexPath.section %d", __FILE__, __LINE__,  __func__,
                     (int)indexPath.section);
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
            return 22;

        case 3:
            h = tableView.frame.size.height - self.navigationController.navigationBar.frame.size.height - 20.0 - 44.0;

            for (int s = 0; s < section; s++) {
                h -= [self tableView:tableView heightForHeaderInSection:s];

                for (int r = 0; r < [self tableView:tableView numberOfRowsInSection:s]; r++) {
                    h -= [self tableView:tableView heightForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s]];
                }
            }

            return h > 22 ? h : 22;
        
        default:
            NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)section);
    }

    return 22;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10, v.frame.size.height - 22.0,
                                                           self.view.frame.size.width - 20, 22.0)];
    
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
    //TODO: include an option to generate a new wallet and sweep old balance if backup may have been compromized
    static NSString *warning = @"DO NOT let anyone see your backup phrase or they can spend your bitcoins.";
    UIViewController *c = nil;
    UILabel *l = nil;

    switch (indexPath.section) {
        case 0:
            //TODO: show transaction details
            break;
            
        case 1:
            switch (indexPath.row) {
                case 0:
                    c = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNAboutViewController"];
                    l = (id)[c.view viewWithTag:411];
#if BITCOIN_TESTNET
                    l.text = [l.text stringByReplacingOccurrencesOfString:@"%ver%" withString:@"%ver% (testnet)"];
#endif
                    l.text = [l.text stringByReplacingOccurrencesOfString:@"%ver%"
                              withString:NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]];
                    [ZNStoryboardSegue segueFrom:self to:c completion:nil];
                    break;
                    
                case 1:
                    [[[UIAlertView alloc] initWithTitle:@"WARNING" message:warning delegate:self
                      cancelButtonTitle:@"cancel" otherButtonTitles:@"show", nil] show];
                    break;
                    
                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__,
                             (int)indexPath.row);
            }
            break;

        case 2:
            [[ZNPeerManager sharedInstance] rescan];
            [self done:nil];
            break;

        case 3: // start/restore is handled in storyboard
            break;

        default:
            NSAssert(FALSE, @"%s:%d %s: unkown indexPath.section %d", __FILE__, __LINE__,  __func__,
                     (int)indexPath.section);
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
    
    [UIView animateWithDuration:SEGUE_DURATION animations:^{
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
    
    [ZNStoryboardSegue segueFrom:self
     to:[self.storyboard instantiateViewControllerWithIdentifier:@"ZNSeedViewController"] completion:nil];
}

@end
