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
#import "BRRootViewController.h"
#import "BRPINViewController.h"
#import "BRWalletManager.h"
#import "BRWallet.h"
#import "BRPeerManager.h"
#import "BRTransaction.h"
#import "BRCopyLabel.h"
#import "BRBubbleView.h"

#define TRANSACTION_CELL_HEIGHT 75

@interface BRSettingsViewController ()

@property (nonatomic, strong) NSArray *transactions;
@property (nonatomic, assign) BOOL moreTx;
@property (nonatomic, strong) NSMutableDictionary *txDates;
@property (nonatomic, strong) id balanceObserver, txStatusObserver;
@property (nonatomic, strong) UIImageView *wallpaper;
@property (nonatomic, strong) UITableViewController *selectorController;
@property (nonatomic, strong) NSArray *selectorOptions;
@property (nonatomic, strong) NSString *selectedOption;

@end

@implementation BRSettingsViewController

//TODO: XXXX only show most recent 5 tx and have a separate page for the rest with section headers for each day
- (void)viewDidLoad
{
    [super viewDidLoad];

    self.txDates = [NSMutableDictionary dictionary];
    self.wallpaper = [[UIImageView alloc] initWithFrame:self.navigationController.view.bounds];
    self.wallpaper.image = [UIImage imageNamed:@"wallpaper-default"];
    self.wallpaper.contentMode = UIViewContentModeLeft;
    [self.navigationController.view insertSubview:self.wallpaper atIndex:0];
    self.navigationController.delegate = self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
    
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSArray *a = m.wallet.recentTransactions;
    
    self.transactions = [a subarrayWithRange:NSMakeRange(0, a.count > 5 ? 5 : a.count)];
    self.moreTx = (a.count > 5) ? YES : NO;

    if (! self.balanceObserver) {
        self.balanceObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                BRTransaction *tx = self.transactions.firstObject;
                NSArray *a = m.wallet.recentTransactions;

                if (! m.wallet) return;

                if (self.moreTx) {
                    self.transactions = [a subarrayWithRange:NSMakeRange(0, a.count > 5 ? 5 : a.count)];
                    self.moreTx = (a.count > 5) ? YES : NO;
                }
                else self.transactions = [NSArray arrayWithArray:a];

                self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                             [m localCurrencyStringForAmount:m.wallet.balance]];

                [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                 withRowAnimation:(self.transactions.firstObject == tx) ? UITableViewRowAnimationNone :
                                   UITableViewRowAnimationAutomatic];
            }];
    }

    if (! self.txStatusObserver) {
        self.txStatusObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if (! m.wallet) return;
                [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                 withRowAnimation:UITableViewRowAnimationNone];
            }];
    }
}

//- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
//{
//    [super prepareForSegue:segue sender:sender];
//
//    [segue.destinationViewController setTransitioningDelegate:self];
//    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
//}

- (void)dealloc
{
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (void)setBackgroundForCell:(UITableViewCell *)cell tableView:(UITableView *)tableView indexPath:(NSIndexPath *)path
{
    if (! cell.backgroundView) {
        UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.frame.size.width, 0.5)];
        
        v.tag = 100;
        cell.backgroundView = [[UIView alloc] initWithFrame:cell.frame];
        cell.backgroundView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.67];
        v.backgroundColor = tableView.separatorColor;
        [cell.backgroundView addSubview:v];
        v = [[UIView alloc] initWithFrame:CGRectMake(0, cell.frame.size.height - 0.5, cell.frame.size.width, 0.5)];
        v.tag = 101;
        v.backgroundColor = tableView.separatorColor;
        [cell.backgroundView addSubview:v];
    }
    
    [cell viewWithTag:100].frame = CGRectMake(path.row == 0 ? 0 : 15, 0, cell.frame.size.width, 0.5);
    [cell viewWithTag:101].hidden = (path.row + 1 < [self tableView:tableView numberOfRowsInSection:path.section]);
}

- (NSString *)dateForTx:(BRTransaction *)tx
{
    static NSDateFormatter *f1 = nil, *f2 = nil, *f3 = nil;
    static NSTimeInterval w = 0.0, y = 0.0;
    NSString *date = self.txDates[tx.txHash];

    if (date) return date;

    if (! f1) {
        f1 = [NSDateFormatter new];
        f2 = [NSDateFormatter new];
        f3 = [NSDateFormatter new];
        w = [NSDate timeIntervalSinceReferenceDate] - 7*24*60*60;
        y = [NSDate timeIntervalSinceReferenceDate] - 365*24*60*60;

        f1.dateFormat = [[[NSDateFormatter dateFormatFromTemplate:@"Mdha" options:0 locale:[NSLocale currentLocale]]
                          stringByReplacingOccurrencesOfString:@", " withString:@" "]
                         stringByReplacingOccurrencesOfString:@" h" withString:@"@h"];
        f2.dateFormat = [[NSDateFormatter dateFormatFromTemplate:@"Md" options:0 locale:[NSLocale currentLocale]]
                         stringByReplacingOccurrencesOfString:@", " withString:@" "];
        f3.dateFormat = [[NSDateFormatter dateFormatFromTemplate:@"yyMd" options:0 locale:[NSLocale currentLocale]]
                          stringByReplacingOccurrencesOfString:@", " withString:@" "];
    }
    
    NSTimeInterval t = [[BRPeerManager sharedInstance] timestampForBlockHeight:tx.blockHeight];
    NSDateFormatter *f = (t > w) ? f1 : ((t > y) ? f2 : f3);

    date = [[[[f stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:t - 5*60]] lowercaseString]
             stringByReplacingOccurrencesOfString:@" am" withString:@"a"]
            stringByReplacingOccurrencesOfString:@" pm" withString:@"p"];
    self.txDates[tx.txHash] = date;
    return date;
}

#pragma mark - IBAction

- (IBAction)done:(id)sender
{
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    self.balanceObserver = nil;
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
    self.txStatusObserver = nil;

    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)scanQR:(id)sender
{
    //TODO: show scanner in settings rather than dismissing
    UINavigationController *nav = (id)self.navigationController.presentingViewController;

    nav.view.alpha = 0.0;

    [nav dismissViewControllerAnimated:NO completion:^{
        [(id)[nav.viewControllers.firstObject sendViewController] scanQR:nil];
        [UIView animateWithDuration:0.1 delay:1.5 options:0 animations:^{ nav.view.alpha = 1.0; } completion:nil];
    }];
}

- (IBAction)toggle:(id)sender
{
    UILabel *l = (id)[[sender superview] viewWithTag:2];

    [[NSUserDefaults standardUserDefaults] setBool:[sender isOn] forKey:SETTINGS_SKIP_FEE_KEY];

    l.hidden = NO;
    l.alpha = ([sender isOn]) ? 0.0 : 1.0;

    [UIView animateWithDuration:0.2 animations:^{
        l.alpha = ([sender isOn]) ? 1.0 : 0.0;
    } completion:^(BOOL finished) {
        l.alpha = 1.0;
        l.hidden = ([sender isOn]) ? NO : YES;
    }];
}

- (IBAction)about:(id)sender
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://breadwallet.com"]];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView == self.selectorController.tableView) return 1;
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == self.selectorController.tableView) return self.selectorOptions.count;

    switch (section) {
        case 0:
            if (self.transactions.count == 0) return 1;
            return (self.moreTx) ? self.transactions.count + 1 : self.transactions.count;

        case 1:
            return 2;

        case 2:
            return 3;

        case 3:
            return 2;

        case 4:
            return 1;
            
        default:
            NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)section);
    }

    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *transactionIdent = @"TransactionCell", *moreIdent = @"MoreCell", *actionIdent = @"ActionCell",
                    *toggleIdent = @"ToggleCell", *selectorIdent = @"SelectorCell", *restoreIdent = @"RestoreCell",
                    *disclosureIdent = @"DisclosureCell", *selectorOptionCell = @"SelectorOptionCell";
    UITableViewCell *cell = nil;
    UILabel *textLabel, *unconfirmedLabel, *sentLabel, *noTxLabel, *localCurrencyLabel, *toggleLabel;
    UISwitch *toggleSwitch;
    BRCopyLabel *detailTextLabel;
    BRWalletManager *m = [BRWalletManager sharedInstance];

    if (tableView == self.selectorController.tableView) {
        cell = [self.tableView dequeueReusableCellWithIdentifier:selectorOptionCell];
        [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
        cell.textLabel.text = self.selectorOptions[indexPath.row];

        if ([self.selectedOption isEqual:self.selectorOptions[indexPath.row]]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
        else cell.accessoryType = UITableViewCellAccessoryNone;

        return cell;
    }

    switch (indexPath.section) {
        case 0:
            if (indexPath.row > 0 && indexPath.row >= self.transactions.count) {
                cell = [tableView dequeueReusableCellWithIdentifier:moreIdent];
                [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
                return cell;
            }
        
            cell = [tableView dequeueReusableCellWithIdentifier:transactionIdent];
            [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
            
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
                BRTransaction *tx = self.transactions[indexPath.row];
                uint64_t received = [m.wallet amountReceivedFromTransaction:tx],
                         sent = [m.wallet amountSentByTransaction:tx];
                uint32_t height = [[BRPeerManager sharedInstance] lastBlockHeight],
                         confirms = (tx.blockHeight == TX_UNCONFIRMED) ? 0 : (height - tx.blockHeight) + 1;
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
                else if (confirms == 0 && [m.wallet transactionIsPending:tx atBlockHeight:height]) {
                    unconfirmedLabel.text = NSLocalizedString(@"pending  ", nil);
                    unconfirmedLabel.backgroundColor = [UIColor redColor];
                }
                else if (confirms == 0 && ! [[BRPeerManager sharedInstance] transactionIsVerified:tx.txHash]) {
                    unconfirmedLabel.text = NSLocalizedString(@"unverified  ", nil);
                }
                else if (confirms < 6) {
                    unconfirmedLabel.text = (confirms == 1) ? NSLocalizedString(@"1 confirmation  ", nil) :
                        [NSString stringWithFormat:NSLocalizedString(@"%d confirmations  ", nil), (int)confirms];
                }
                else {
                    unconfirmedLabel.hidden = YES;
                    sentLabel.hidden = NO;
                }

                if (! address && sent > 0) {
                    textLabel.text = [m stringForAmount:sent];
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [m localCurrencyStringForAmount:sent]];
                    detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ within wallet", nil),
                                            [self dateForTx:tx]];
                    detailTextLabel.copyableText = @"";
                    sentLabel.text = NSLocalizedString(@"moved  ", nil);
                }
                else if (sent > 0) {
                    textLabel.text = [m stringForAmount:received - sent];
                    detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ to:%@", nil),
                                            [self dateForTx:tx], address];
                    detailTextLabel.copyableText = address;
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [m localCurrencyStringForAmount:received - sent]];
                    sentLabel.text = NSLocalizedString(@"sent  ", nil);
                    sentLabel.textColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.67];
                }
                else {
                    textLabel.text = [m stringForAmount:received];
                    detailTextLabel.copyableText = (address) ? address : @"";
                    if (! address) address = [@" " stringByAppendingString:NSLocalizedString(@"unkown address", nil)];
                    detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ from:%@", nil),
                                            [self dateForTx:tx], address];
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [m localCurrencyStringForAmount:received]];
                    sentLabel.text = NSLocalizedString(@"received  ", nil);
                    sentLabel.textColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                }

                sentLabel.layer.borderColor = sentLabel.textColor.CGColor;
             }

            break;

        case 1:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];

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
            [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];

            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = NSLocalizedString(@"change pin", nil);
                    cell.imageView.image = [UIImage imageNamed:@"pin"];
                    cell.imageView.alpha = 0.75;
                    break;

                case 1:
                    cell.textLabel.text = NSLocalizedString(@"import private key", nil);
                    cell.imageView.image = [UIImage imageNamed:@"cameraguide-blue-small"];
                    cell.imageView.alpha = 1.0;
                    break;

                case 2:
                    cell.textLabel.text = NSLocalizedString(@"rescan blockchain", nil);
                    cell.imageView.image = [UIImage imageNamed:@"rescan"];
                    cell.imageView.alpha = 0.75;
                    break;

                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__,
                             (int)indexPath.row);
            }
            
            break;

        case 3:
            switch (indexPath.row) {
                case 0:
                    cell = [tableView dequeueReusableCellWithIdentifier:selectorIdent];
                    [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
                    cell.detailTextLabel.text = m.localCurrencyCode;
                    break;

                case 1:
                    cell = [tableView dequeueReusableCellWithIdentifier:toggleIdent];
                    [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
                    toggleLabel = (id)[cell viewWithTag:2];
                    toggleSwitch = (id)[cell viewWithTag:3];
                    toggleSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:SETTINGS_SKIP_FEE_KEY];
                    toggleLabel.hidden = (toggleSwitch.on) ? NO : YES;
                    break;

                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__,
                             (int)indexPath.row);
            }

            break;

        case 4:
            cell = [tableView dequeueReusableCellWithIdentifier:restoreIdent];
            [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
            break;

        default:
            NSAssert(FALSE, @"%s:%d %s: unkown indexPath.section %d", __FILE__, __LINE__,  __func__,
                     (int)indexPath.section);
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (tableView == self.selectorController.tableView) return nil;

    switch (section) {
        case 0:
            return nil;

        case 1:
            return nil;
            
        case 2:
            return nil;

        case 3:
            return NSLocalizedString(@"rescan blockchain if you think you may have missing transactions, "
                                     "or are having trouble sending (rescaning can take several minutes)", nil);

        case 4:
            return NSLocalizedString(@"fees are only optional for high priority transactions", nil);

        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)section);
    }
    
    return nil;
}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView == self.selectorController.tableView) return 44.0;

    switch (indexPath.section) {
        case 0: return (indexPath.row == 0 || indexPath.row < self.transactions.count) ? TRANSACTION_CELL_HEIGHT : 44.0;
        case 1: return 44.0;
        case 2: return 44.0;
        case 3: return 44.0;
        case 4: return 44.0;
        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)indexPath.section);
    }
    
    return 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSString *s = [self tableView:tableView titleForHeaderInSection:section];

    if (s.length == 0) return 22.0;

    CGRect r = [s boundingRectWithSize:CGSizeMake(self.view.frame.size.width - 20.0, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin
                attributes:@{NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue" size:13]} context:nil];
    
    return r.size.height + 22.0 + 10.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(15.0, 0.0, v.frame.size.width - 20.0,
                                                           v.frame.size.height - 22.0)];
    
    l.text = [self tableView:tableView titleForHeaderInSection:section];
    l.backgroundColor = [UIColor clearColor];
    l.font = [UIFont fontWithName:@"HelveticaNeue" size:13];
    l.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    l.shadowColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    l.shadowOffset = CGSizeMake(0.0, 1.0);
    l.numberOfLines = 0;
    v.backgroundColor = [UIColor clearColor];
    [v addSubview:l];

    return v;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return (section + 1 == [self numberOfSectionsInTableView:tableView]) ? 22.0 : 0.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForFooterInSection:section])];
    v.backgroundColor = [UIColor clearColor];
    return v;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //TODO: include an option to generate a new wallet and sweep old balance if backup may have been compromized
    UINavigationController *c = nil;
    UILabel *l = nil;
    NSUInteger i = 0;
    UITableViewCell *cell = nil;
    NSMutableAttributedString *s = nil;
    NSMutableArray *a;
    BRWalletManager *m = [BRWalletManager sharedInstance];

    if (tableView == self.selectorController.tableView) {
        self.selectedOption = self.selectorOptions[indexPath.row];
        m.localCurrencyCode = self.selectedOption;

        [tableView reloadData];
        [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self.tableView reloadData];
        return;
    }

    switch (indexPath.section) {
        case 0: // transaction
            if (indexPath.row > 0 && indexPath.row >= self.transactions.count) {
                [tableView beginUpdates];
                self.transactions = [NSArray arrayWithArray:m.wallet.recentTransactions];
                self.moreTx = NO;
                [tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:5 inSection:0]]
                 withRowAnimation:UITableViewRowAnimationFade];
                a = [NSMutableArray arrayWithCapacity:self.transactions.count - 5];
                
                for (NSUInteger i = 5; i < self.transactions.count; i++) {
                    [a addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                }
                
                [tableView insertRowsAtIndexPaths:a withRowAnimation:UITableViewRowAnimationTop];
                [tableView endUpdates];
            }
            else if (self.transactions.count > 0) {
                // TODO: show transaction details
                i = [[self.tableView indexPathsForVisibleRows] indexOfObject:indexPath];
                cell = (i < self.tableView.visibleCells.count) ? self.tableView.visibleCells[i] : nil;
                [(id)[cell viewWithTag:2] toggleCopyMenu];
            }

            break;

        case 1:
            switch (indexPath.row) {
                case 0: // about
                    c = [self.storyboard instantiateViewControllerWithIdentifier:@"AboutViewController"];
                    l = (id)[c.view viewWithTag:411];
                    s = [[NSMutableAttributedString alloc] initWithAttributedString:l.attributedText];
#if BITCOIN_TESTNET
                    [s replaceCharactersInRange:[s.string rangeOfString:@"%net%"] withString:@"%net% (testnet)"];
#endif
                    [s replaceCharactersInRange:[s.string rangeOfString:@"%ver%"]
                     withString:NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]];
                    [s replaceCharactersInRange:[s.string rangeOfString:@"%net%"] withString:@""];
                    l.attributedText = s;
                    [l.superview.gestureRecognizers.firstObject addTarget:self action:@selector(about:)];
                    [self.navigationController pushViewController:c animated:YES];
                    break;
                    
                case 1: // backup phrase
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                      message:NSLocalizedString(@"DO NOT let anyone see your backup phrase or they can spend your "
                                                 "bitcoins.", nil) delegate:self
                      cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                      otherButtonTitles:NSLocalizedString(@"show", nil), nil] show];
                    break;

                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__,
                             (int)indexPath.row);
            }

            break;

        case 2:
            switch (indexPath.row) {
                case 0: // change pin
                    c = [self.storyboard instantiateViewControllerWithIdentifier:@"PINNav"];
                    [c.viewControllers.firstObject setCancelable:YES];
                    [c.viewControllers.firstObject setChangePin:YES];
                    c.transitioningDelegate = self;
                    [self.navigationController presentViewController:c animated:YES completion:nil];
                    [c.viewControllers.firstObject setAppeared:YES];
                    break;

                case 1: // import private key
                    [self scanQR:nil];
                    break;

                case 2: // rescan blockchain
                    [[BRPeerManager sharedInstance] rescan];
                    [self done:nil];
                    break;

                default:
                    NSAssert(FALSE, @"%s:%d %s: unkown indexPath.row %d", __FILE__, __LINE__,  __func__,
                             (int)indexPath.row);
            }

            break;

        case 3:
            switch (indexPath.row) {
                case 0: // local currency
                    self.selectorOptions =
                        [m.currencyCodes sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
                    self.selectedOption = m.localCurrencyCode;
                    self.selectorController = [[UITableViewController alloc] initWithStyle:UITableViewStylePlain];
                    self.selectorController.transitioningDelegate = self;
                    self.selectorController.tableView.dataSource = self;
                    self.selectorController.tableView.delegate = self;
                    self.selectorController.tableView.backgroundColor = [UIColor clearColor];
                    self.selectorController.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
                    self.selectorController.title = NSLocalizedString(@"local currency", nil);
                    [self.navigationController pushViewController:self.selectorController animated:YES];

                    NSUInteger i = [self.selectorOptions indexOfObject:self.selectedOption];

                    if (i != NSNotFound) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self.selectorController.tableView
                             scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]
                             atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
                        });
                    }

                    break;

                case 1: // remove standard fees
                    break;
            }

            break;

        case 4: // start/restore another wallet (handled by storyboard)
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

    UINavigationController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"PINNav"];

    [c.viewControllers.firstObject setAppeared:YES];
    [c.viewControllers.firstObject setCancelable:YES];
    c.transitioningDelegate = self;
    [self.navigationController presentViewController:c animated:YES completion:nil];
}

#pragma mark - UIViewControllerAnimatedTransitioning

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
    BOOL pop = (to == self || to == self.navigationController) ? YES : NO;

    if ([from.restorationIdentifier isEqual:@"PINNav"] && ! [[[(id)from viewControllers] firstObject] changePin] &&
        [[[(id)from viewControllers] firstObject] success]) {
        [self.navigationController
         pushViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"]
         animated:NO];

        to.view.frame = from.view.frame;
        [v insertSubview:to.view belowSubview:from.view];

        [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            from.view.alpha = 0.0;
            from.view.transform = CGAffineTransformMakeScale(0.75, 0.75);
        } completion:^(BOOL finished) {
            [from.view removeFromSuperview];
            [transitionContext completeTransition:finished];
        }];
    }
    else {
        if (self.wallpaper.superview != v) [v insertSubview:self.wallpaper belowSubview:from.view];
        to.view.center = CGPointMake(v.frame.size.width*(pop ? -1 : 3)/2, to.view.center.y);
        [v addSubview:to.view];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            to.view.center = from.view.center;
            from.view.center = CGPointMake(v.frame.size.width*(pop ? 3 : -1)/2, from.view.center.y);
            self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 -
                                                v.frame.size.width*(pop ? 0 : 1)*PARALAX_RATIO,
                                                self.wallpaper.center.y);
        } completion:^(BOOL finished) {
            if (pop) [from.view removeFromSuperview];
            [transitionContext completeTransition:finished];
        }];
    }
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
