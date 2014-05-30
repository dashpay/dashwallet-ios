//
//  BRSettingsViewController.m
//  BreadWallet
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

#import "BRSettingsViewController.h"
#import "BRWalletManager.h"
#import "BRWallet.h"
#import "BRPeerManager.h"
#import "BRTransaction.h"
#import <QuartzCore/QuartzCore.h>

#define TRANSACTION_CELL_HEIGHT 75

@interface BRSettingsViewController ()

@property (nonatomic, strong) NSArray *transactions;
@property (nonatomic, strong) id balanceObserver, txStatusObserver;
@property (nonatomic, strong) UIImageView *wallpaper;

@end

@implementation BRSettingsViewController

//TODO: only show most recent 10-20 transactions and have a separate page for the rest with section headers for each day
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            BRWalletManager *m = [BRWalletManager sharedInstance];

            if (! m.wallet) return;
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                            [m localCurrencyStringForAmount:m.wallet.balance]];

            self.transactions = [NSArray arrayWithArray:m.wallet.recentTransactions];
            
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
             withRowAnimation:UITableViewRowAnimationAutomatic];
        }];

    self.txStatusObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            BRWalletManager *m = [BRWalletManager sharedInstance];

            if (! m.wallet) return;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
             withRowAnimation:UITableViewRowAnimationAutomatic]; //BUG: random malloc error in sim
        }];

    BRWalletManager *m = [BRWalletManager sharedInstance];

    self.wallpaper = [[UIImageView alloc] initWithFrame:self.navigationController.view.bounds];
    self.wallpaper.image = [UIImage imageNamed:@"wallpaper-default"];
    self.wallpaper.contentMode = UIViewContentModeLeft;
    [self.navigationController.view insertSubview:self.wallpaper atIndex:0];
    self.navigationController.delegate = self;
    self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                    [m localCurrencyStringForAmount:m.wallet.balance]];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.transactions = [NSArray arrayWithArray:[[[BRWalletManager sharedInstance] wallet] recentTransactions]];
}

//- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
//    [super prepareForSegue:segue sender:sender];
//
//    [segue.destinationViewController setTransitioningDelegate:self];
//    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
//}

- (void)dealloc
{
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
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
    static NSString *disclosureIdent = @"DisclosureCell", *transactionIdent = @"TransactionCell",
                    *actionIdent = @"ActionCell", *restoreIdent = @"RestoreCell";
    UITableViewCell *cell = nil;
    UILabel *textLabel, *detailTextLabel, *unconfirmedLabel, *sentLabel, *noTxLabel, *localCurrencyLabel;
    
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
                BRWalletManager *m = [BRWalletManager sharedInstance];
                BRTransaction *tx = self.transactions[indexPath.row];
                uint64_t received = [m.wallet amountReceivedFromTransaction:tx],
                         sent = [m.wallet amountSentByTransaction:tx];
                NSUInteger confirms = (tx.blockHeight != TX_UNCONFIRMED) ?
                                      ([[BRPeerManager sharedInstance] lastBlockHeight] - tx.blockHeight) + 1 : 0;
                NSString *address = [m.wallet addressForTransaction:tx];

                noTxLabel.hidden = YES;
                sentLabel.hidden = YES;
                unconfirmedLabel.hidden = NO;
                unconfirmedLabel.layer.cornerRadius = 3.0;
                unconfirmedLabel.backgroundColor = [UIColor lightGrayColor];
                sentLabel.layer.cornerRadius = 3.0;
                sentLabel.layer.borderWidth = 0.5;

                if (confirms == 0 && ! [m.wallet transactionIsValid:tx]) {
                    unconfirmedLabel.text = NSLocalizedString(@"INVALID  ", nil);
                    unconfirmedLabel.backgroundColor = [UIColor redColor];
                }
                else if (confirms == 0 && ! [[BRPeerManager sharedInstance] transactionIsVerified:tx.txHash]) {
                    unconfirmedLabel.text = NSLocalizedString(@"unverified  ", nil);
                }
                else if (confirms < 6) {
                    unconfirmedLabel.text = (confirms == 1) ? NSLocalizedString(@"1 confirmation ", nil) :
                        [NSString stringWithFormat:NSLocalizedString(@"%d confirmations ", nil), (int)confirms];
                }
                else {
                    unconfirmedLabel.hidden = YES;
                    sentLabel.hidden = NO;
                }

                if (! address || (sent > 0 && [m.wallet containsAddress:address])) {
                    textLabel.text = [m stringForAmount:sent];
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [m localCurrencyStringForAmount:sent]];
                    detailTextLabel.text = NSLocalizedString(@"within wallet", nil);
                    sentLabel.text = NSLocalizedString(@"moved  ", nil);
                }
                else if (sent > 0) {
                    textLabel.text = [m stringForAmount:received - sent];
                    detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"to: %@", nil), address];
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [m localCurrencyStringForAmount:received - sent]];
                    sentLabel.text = NSLocalizedString(@"sent  ", nil);
                    sentLabel.textColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.67];
                }
                else {
                    textLabel.text = [m stringForAmount:received];
                    detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"to: %@", nil), address];
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [m localCurrencyStringForAmount:received]];
                    sentLabel.text = NSLocalizedString(@"received  ", nil);
                    sentLabel.textColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                }

                sentLabel.layer.borderColor = sentLabel.textColor.CGColor;
                
                if (! detailTextLabel.text) {
                    detailTextLabel.text = NSLocalizedString(@"can't decode payment address", nil);
                }
            }
            break;
            
        case 1:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            [self setBackgroundForCell:cell atIndexPath:indexPath];

            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = NSLocalizedString(@"about", nil);
                    break;

                case 1:
                    cell.textLabel.text = NSLocalizedString(@"backup phrase", nil);
                    break;
                    
                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__,
                             (int)indexPath.row);
            }
            break;
            
        case 2:
            cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
            [self setBackgroundForCell:cell atIndexPath:indexPath];
            cell.textLabel.text = NSLocalizedString(@"rescan blockchain", nil);
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
//        case 0: return nil;//NSLocalizedString(@"recent transactions", nil);
//        case 1: return nil;//NSLocalizedString(@"settings", nil);
//        case 2: return nil;//NSLocalizedString(@"caution", nil);
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
    static NSString *warning = nil;
    UIViewController *c = nil;
    UILabel *l = nil;

    if (! warning) {
        warning = NSLocalizedString(@"DO NOT let anyone see your backup phrase or they can spend your bitcoins.", nil);
    }

    switch (indexPath.section) {
        case 0:
            //TODO: show transaction details
            break;
            
        case 1:
            switch (indexPath.row) {
                case 0:
                    c = [self.storyboard instantiateViewControllerWithIdentifier:@"AboutViewController"];
                    l = (id)[c.view viewWithTag:411];
#if BITCOIN_TESTNET
                    l.text = [l.text stringByReplacingOccurrencesOfString:@"%ver%" withString:@"%ver% (testnet)"];
#endif
                    l.text = [l.text stringByReplacingOccurrencesOfString:@"%ver%"
                              withString:NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]];

                    [self.navigationController pushViewController:c animated:YES];
                    break;
                    
                case 1:
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil) message:warning delegate:self
                      cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                      otherButtonTitles:NSLocalizedString(@"show", nil), nil] show];
                    break;
                    
                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__,
                             (int)indexPath.row);
            }
            break;

        case 2:
            [[BRPeerManager sharedInstance] rescan];
            [self done:nil];
            break;

        case 3: // start/restore is handled in storyboard
            break;

        default:
            NSAssert(FALSE, @"%s:%d %s: unkown indexPath.section %d", __FILE__, __LINE__,  __func__,
                     (int)indexPath.section);
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        return;
    }

    [self.navigationController
     pushViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"] animated:YES];
}

#pragma mark UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return 0.35;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    UIView *v = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];

    if (self.wallpaper.superview != v) [v insertSubview:self.wallpaper belowSubview:from.view];

    to.view.center = CGPointMake(v.frame.size.width*(to == self ? -1 : 3)/2, to.view.center.y);
    [v addSubview:to.view];

    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
     initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        to.view.center = from.view.center;
        from.view.center = CGPointMake(v.frame.size.width*(to == self ? 3 : -1)/2, from.view.center.y);
        self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 -
                                            v.frame.size.width*(to == self ? 0 : 1)*PARALAX_RATIO,
                                            self.wallpaper.center.y);
    } completion:^(BOOL finished) {
        if (to == self) [from.view removeFromSuperview];
        [transitionContext completeTransition:finished];
    }];
}

#pragma mark - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC
toViewController:(UIViewController *)toVC
{
    return self;
}

#pragma mark - UIViewControllerTransitioningDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
{
    return self;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    return self;
}

@end
