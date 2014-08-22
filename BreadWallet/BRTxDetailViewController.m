//
//  BRTxDetailViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 7/23/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
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

#import "BRTxDetailViewController.h"
#import "BRTransaction.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "BRWallet.h"
#import "BRCopyLabel.h"
#import "NSString+Base58.h"
#import "NSData+Hash.h"

#define TRANSACTION_CELL_HEIGHT 75

@interface BRTxDetailViewController ()

@property (nonatomic, strong) NSArray *outputText, *outputDetail, *outputAmount;
@property (nonatomic, assign) int64_t sent, received, moved;
@property (nonatomic, strong) id txStatusObserver;

@end

@implementation BRTxDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (! self.txStatusObserver) {
        self.txStatusObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                [self.tableView reloadData];
            }];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
    self.txStatusObserver = nil;
    
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (void)setTransaction:(BRTransaction *)transaction
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSMutableArray *text = [NSMutableArray array], *detail = [NSMutableArray array], *amount = [NSMutableArray array];
    uint64_t fee = [m.wallet feeForTransaction:transaction];
    NSUInteger i = 0;
    
    _transaction = transaction;
    self.sent = [m.wallet amountSentByTransaction:transaction];
    self.received = [m.wallet amountReceivedFromTransaction:transaction];
    self.moved = (! [m.wallet addressForTransaction:self.transaction] && self.sent > 0) ? self.sent : 0;

    for (NSString *address in transaction.outputAddresses) {
        uint64_t amt = [transaction.outputAmounts[i++] unsignedLongLongValue];
    
        if (address == (id)[NSNull null]) {
            if (self.sent > 0) {
                [text addObject:NSLocalizedString(@"unkown address", nil)];
                [detail addObject:NSLocalizedString(@"payment output", nil)];
                [amount addObject:@(-amt)];
            }
        }
        else if ([m.wallet containsAddress:address]) {
            if (self.sent == 0 || self.moved > 0) {
                [text addObject:address];
                [detail addObject:NSLocalizedString(@"wallet address", nil)];
                [amount addObject:@(amt)];
            }
        }
        else if (self.sent > 0) {
            [text addObject:address];
            [detail addObject:NSLocalizedString(@"payment address", nil)];
            [amount addObject:@(-amt)];
        }
    }

    if (self.sent > 0 && fee > 0 && fee != UINT64_MAX) {
        [text addObject:@""];
        [detail addObject:NSLocalizedString(@"bitcoin network fee", nil)];
        [amount addObject:@(-fee)];
    }
    
    self.outputText = text;
    self.outputDetail = detail;
    self.outputAmount = amount;
}

- (void)setBackgroundForCell:(UITableViewCell *)cell indexPath:(NSIndexPath *)path
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
        case 0: return 3;
        case 1: return (self.sent > 0) ? self.outputText.count : self.transaction.inputAddresses.count;
        case 2: return (self.sent > 0) ? self.transaction.inputAddresses.count : self.outputText.count;
        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)section);
    }

    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    BRCopyLabel *detailLabel;
    UILabel *textLabel, *subtitleLabel, *amountLabel, *localCurrencyLabel;
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSUInteger peerCount = [[BRPeerManager sharedInstance] peerCount],
               relayCount = [[BRPeerManager sharedInstance] relayCountForTransaction:self.transaction.txHash];
    
    // Configure the cell...
    switch (indexPath.section) {
        case 0:
            switch (indexPath.row) {
                case 0:
                    cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCell" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    textLabel = (id)[cell viewWithTag:1];
                    detailLabel = (id)[cell viewWithTag:2];
                    subtitleLabel = (id)[cell viewWithTag:3];
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    textLabel.text = NSLocalizedString(@"id:", nil);
                    detailLabel.text = [NSString hexWithData:self.transaction.txHash.reverse];
                    subtitleLabel.text = nil;
                    break;
                    
                case 1:
                    cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCell" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    textLabel = (id)[cell viewWithTag:1];
                    detailLabel = (id)[cell viewWithTag:2];
                    subtitleLabel = (id)[cell viewWithTag:3];
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    textLabel.text = NSLocalizedString(@"status:", nil);
                    subtitleLabel.text = nil;
                    
                    if (self.transaction.blockHeight != TX_UNCONFIRMED) {
                        detailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"confirmed in block #%d", nil),
                                            self.transaction.blockHeight, self.txDateString];
                        subtitleLabel.text = self.txDateString;
                    }
                    else if (! [m.wallet transactionIsValid:self.transaction]) {
                        detailLabel.text = NSLocalizedString(@"double spend", nil);
                    }
                    else if ([m.wallet transactionIsPending:self.transaction
                              atBlockHeight:[[BRPeerManager sharedInstance] lastBlockHeight]]) {
                        detailLabel.text = NSLocalizedString(@"transaction is post-dated", nil);
                    }
                    else if (peerCount > 0 && relayCount < peerCount) {
                        detailLabel.text = NSLocalizedString(@"waiting for network propagation", nil);
                        subtitleLabel.text = [NSString
                                              stringWithFormat:NSLocalizedString(@"seen by %d of %d peers", nil),
                                              relayCount, peerCount];
                    }
                    else detailLabel.text = NSLocalizedString(@"waiting for confirmation", nil);
                    
                    break;
                    
                case 2:
                    cell = [tableView dequeueReusableCellWithIdentifier:@"TransactionCell"];
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    textLabel = (id)[cell viewWithTag:1];
                    localCurrencyLabel = (id)[cell viewWithTag:5];

                    if (self.moved > 0) {
                        textLabel.text = [m stringForAmount:self.moved];
                        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                                   [m localCurrencyStringForAmount:self.moved]];
                    }
                    else {
                        textLabel.text = [m stringForAmount:self.received - self.sent];
                        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                                   [m localCurrencyStringForAmount:self.received - self.sent]];
                    }
                    
                    break;
                    
                default:
                    break;
            }
            
            break;
            
        case 1: // drop through
        case 2:
            if ((self.sent > 0 && indexPath.section == 1) || (self.sent == 0 && indexPath.section == 2)) {
                if ([self.outputText[indexPath.row] length] > 0) {
                    cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                }
                else cell = [tableView dequeueReusableCellWithIdentifier:@"SubtitleCell" forIndexPath:indexPath];

                detailLabel = (id)[cell viewWithTag:2];
                subtitleLabel = (id)[cell viewWithTag:3];
                amountLabel = (id)[cell viewWithTag:1];
                localCurrencyLabel = (id)[cell viewWithTag:5];
                detailLabel.text = self.outputText[indexPath.row];
                subtitleLabel.text = self.outputDetail[indexPath.row];
                amountLabel.text = [m stringForAmount:[self.outputAmount[indexPath.row] longLongValue]];
                amountLabel.textColor = (self.sent > 0) ? [UIColor colorWithRed:1.0 green:0.33 blue:0.33 alpha:1.0] :
                                        [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                localCurrencyLabel.textColor = amountLabel.textColor;
                localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                           [m localCurrencyStringForAmount:[self.outputAmount[indexPath.row]
                                                                            longLongValue]]];
            }
            else if (self.transaction.inputAddresses[indexPath.row] != (id)[NSNull null]) {
                cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell" forIndexPath:indexPath];
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                detailLabel = (id)[cell viewWithTag:2];
                subtitleLabel = (id)[cell viewWithTag:3];
                amountLabel = (id)[cell viewWithTag:1];
                localCurrencyLabel = (id)[cell viewWithTag:5];
                detailLabel.text = self.transaction.inputAddresses[indexPath.row];
                amountLabel.text = nil;
                localCurrencyLabel.text = nil;
                
                if ([m.wallet containsAddress:self.transaction.inputAddresses[indexPath.row]]) {
                    subtitleLabel.text = NSLocalizedString(@"wallet address", nil);
                }
                else subtitleLabel.text = NSLocalizedString(@"spent address", nil);
            }
            else {
                cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell" forIndexPath:indexPath];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                detailLabel = (id)[cell viewWithTag:2];
                subtitleLabel = (id)[cell viewWithTag:3];
                amountLabel = (id)[cell viewWithTag:1];
                localCurrencyLabel = (id)[cell viewWithTag:5];
                detailLabel.text = NSLocalizedString(@"unkown address", nil);
                subtitleLabel.text = NSLocalizedString(@"spent input", nil);
                amountLabel.text = nil;
                localCurrencyLabel.text = nil;
            }

            [self setBackgroundForCell:cell indexPath:indexPath];
            break;
            
        default:
            NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)indexPath.section);
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0: return nil;
        case 1: return (self.sent > 0) ? NSLocalizedString(@"to:", nil) : NSLocalizedString(@"from:", nil);
        case 2: return (self.sent > 0) ? NSLocalizedString(@"from:", nil) : NSLocalizedString(@"to:", nil);
        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)section);
    }
    
    return nil;
}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: return 44.0;
        case 1: return (self.sent > 0 && [self.outputText[indexPath.row] length] == 0) ? 40 : 60.0;
        case 2: return 60.0;
        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)indexPath.section);
    }
    
    return 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSString *s = [self tableView:tableView titleForHeaderInSection:section];
    
    if (s.length == 0) return 22.0;
    
    CGRect r = [s boundingRectWithSize:CGSizeMake(self.view.frame.size.width - 30.0, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin
                attributes:@{NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue-Light" size:17]} context:nil];
    
    return r.size.height + 12.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(15.0, 10.0, v.frame.size.width - 30.0,
                                                           v.frame.size.height - 12.0)];
    
    l.text = [self tableView:tableView titleForHeaderInSection:section];
    l.backgroundColor = [UIColor clearColor];
    l.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:17];
    l.textColor = [UIColor blackColor];
    l.shadowColor = [UIColor whiteColor];
    l.shadowOffset = CGSizeMake(0.0, 1.0);
    l.numberOfLines = 0;
    v.backgroundColor = [UIColor clearColor];
    [v addSubview:l];
    
    return v;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger i = [[self.tableView indexPathsForVisibleRows] indexOfObject:indexPath];
    UITableViewCell *cell = (i < self.tableView.visibleCells.count) ? self.tableView.visibleCells[i] : nil;
    BRCopyLabel *l = (id)[cell viewWithTag:2];
    
    l.selectedColor = [UIColor clearColor];
    if (cell.selectionStyle != UITableViewCellSelectionStyleNone) [l toggleCopyMenu];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
