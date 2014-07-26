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

#define TRANSACTION_CELL_HEIGHT 75

@interface BRTxDetailViewController ()

@end

@implementation BRTxDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    uint64_t sent = [m.wallet amountSentByTransaction:self.transaction],
             fee = [m.wallet feeForTransaction:self.transaction];
    NSUInteger feecount = (fee > 0 && fee < UINT64_MAX) ? 1 : 0;

    switch (section) {
        case 0:
            return 1;

        case 1:
            return 1;

        case 2:
            return (sent > 0) ?
                   self.transaction.outputAddresses.count + feecount : self.transaction.inputAddresses.count;
            
        case 3:
            return (sent > 0) ?
                   self.transaction.inputAddresses.count : self.transaction.outputAddresses.count + feecount;

        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)section);
    }

    // Return the number of rows in the section.
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *transactionIdent = @"TransactionCell", *infoIdent = @"InfoCell", *detailIdent = @"DetailCell";
    UITableViewCell *cell;
    BRCopyLabel *textLabel, *detailTextLabel;
    UILabel *unconfirmedLabel, *sentLabel, *localCurrencyLabel;
    BRWalletManager *m = [BRWalletManager sharedInstance];
    uint64_t received, sent;
    uint32_t height, confirms;
    BOOL to;
    
    // Configure the cell...
    switch (indexPath.section) {
        case 0:
            cell = [tableView dequeueReusableCellWithIdentifier:infoIdent forIndexPath:indexPath];
            textLabel = (id)[cell viewWithTag:1];
            textLabel.text = [NSString hexWithData:self.transaction.txHash];
            break;

        case 1:
            cell = [tableView dequeueReusableCellWithIdentifier:transactionIdent forIndexPath:indexPath];
            textLabel = (id)[cell viewWithTag:1];
            detailTextLabel = (id)[cell viewWithTag:2];
            unconfirmedLabel = (id)[cell viewWithTag:3];
            localCurrencyLabel = (id)[cell viewWithTag:5];
            sentLabel = (id)[cell viewWithTag:6];

            received = [m.wallet amountReceivedFromTransaction:self.transaction];
            sent = [m.wallet amountSentByTransaction:self.transaction];
            height = [[BRPeerManager sharedInstance] lastBlockHeight];
            confirms = (self.transaction.blockHeight == TX_UNCONFIRMED) ? 0 :
                       (height - self.transaction.blockHeight) + 1;
            
            unconfirmedLabel.hidden = NO;
            unconfirmedLabel.layer.cornerRadius = 3.0;
            unconfirmedLabel.backgroundColor = [UIColor lightGrayColor];
            sentLabel.hidden = YES;
            sentLabel.layer.cornerRadius = 3.0;
            sentLabel.layer.borderWidth = 0.5;
            detailTextLabel.text = self.txDateString;
            
            if (confirms == 0 && ! [m.wallet transactionIsValid:self.transaction]) {
                unconfirmedLabel.text = NSLocalizedString(@"INVALID  ", nil);
                unconfirmedLabel.backgroundColor = [UIColor redColor];
            }
            else if (confirms == 0 && [m.wallet transactionIsPending:self.transaction atBlockHeight:height]) {
                unconfirmedLabel.text = NSLocalizedString(@"pending  ", nil);
                unconfirmedLabel.backgroundColor = [UIColor redColor];
            }
            else if (confirms == 0 && ! [[BRPeerManager sharedInstance] transactionIsVerified:self.transaction.txHash]){
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
            
            if (! [m.wallet addressForTransaction:self.transaction] && sent > 0) {
                textLabel.text = [m stringForAmount:sent];
                localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                           [m localCurrencyStringForAmount:sent]];
                detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ within wallet", nil),
                                        self.txDateString];
                sentLabel.text = NSLocalizedString(@"moved  ", nil);
            }
            else if (sent > 0) {
                textLabel.text = [m stringForAmount:received - sent];
                localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                           [m localCurrencyStringForAmount:received - sent]];
                sentLabel.text = NSLocalizedString(@"sent  ", nil);
                sentLabel.textColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.67];
            }
            else {
                textLabel.text = [m stringForAmount:received];
                detailTextLabel.text = self.txDateString;
                localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                           [m localCurrencyStringForAmount:received]];
                sentLabel.text = NSLocalizedString(@"received  ", nil);
                sentLabel.textColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
            }
            
            sentLabel.layer.borderColor = sentLabel.textColor.CGColor;

            if (self.transaction.blockHeight != TX_UNCONFIRMED) {
                detailTextLabel.text = [detailTextLabel.text
                                        stringByAppendingFormat:NSLocalizedString(@" - confirmed in block #%d", nil),
                                        self.transaction.blockHeight];
            }
            
            break;
            
        case 2: // drop through
        case 3:
            cell = [tableView dequeueReusableCellWithIdentifier:detailIdent forIndexPath:indexPath];
            textLabel = (id)[cell viewWithTag:1];
            detailTextLabel = (id)[cell viewWithTag:2];
            sent = [m.wallet amountSentByTransaction:self.transaction];
            to = ((sent > 0 && indexPath.section == 2) || (sent == 0 && indexPath.section == 3)) ? YES : NO;

            if (to && indexPath.row >= self.transaction.outputAddresses.count) {
                textLabel.text = NSLocalizedString(@"bitcoin network fee", nil);
                detailTextLabel.textColor = [UIColor colorWithRed:1.0 green:0.33 blue:0.33 alpha:1.0];
                detailTextLabel.text = [m stringForAmount:[m.wallet feeForTransaction:self.transaction]];
            }
            else if (to && self.transaction.outputAddresses[indexPath.row] != (id)[NSNull null]) {
                textLabel.text = self.transaction.outputAddresses[indexPath.row];
                
                if ([m.wallet containsAddress:self.transaction.outputAddresses[indexPath.row]]) {
                    detailTextLabel.textColor = (sent > 0) ? [UIColor lightGrayColor] :
                                                [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                    detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
                                            [m stringForAmount:[self.transaction.outputAmounts[indexPath.row]
                                                                unsignedLongLongValue]],
                                            (sent > 0) ? NSLocalizedString(@"change address", nil) :
                                            NSLocalizedString(@"wallet address", nil)];
                }
                else {
                    detailTextLabel.textColor = (sent > 0) ? [UIColor colorWithRed:1.0 green:0.33 blue:0.33 alpha:1.0] :
                                                [UIColor lightGrayColor];
                    detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
                                            [m stringForAmount:[self.transaction.outputAmounts[indexPath.row]
                                                                unsignedLongLongValue]],
                                            (sent > 0) ? NSLocalizedString(@"payment address", nil) :
                                            NSLocalizedString(@"other payment/change", nil)];
                }
            }
            else if (to) {
                textLabel.text = NSLocalizedString(@"unkown address", nil);
                detailTextLabel.textColor = [UIColor lightGrayColor];
                detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
                                        [m stringForAmount:[self.transaction.outputAmounts[indexPath.row]
                                                            unsignedLongLongValue]],
                                        (sent > 0) ? NSLocalizedString(@"payment output", nil) :
                                        NSLocalizedString(@"other payment/change", nil)];
            }
            else {
                detailTextLabel.textColor = [UIColor lightGrayColor];
                
                if (self.transaction.inputAddresses[indexPath.row] != (id)[NSNull null]) {
                    textLabel.text = self.transaction.inputAddresses[indexPath.row];
                    
                    if ([m.wallet containsAddress:self.transaction.inputAddresses[indexPath.row]]) {
                        detailTextLabel.text = NSLocalizedString(@"wallet address", nil);
                    }
                    else detailTextLabel.text = NSLocalizedString(@"sender's address", nil);
                }
                else {
                    textLabel.text = NSLocalizedString(@"unkown address", nil);
                    detailTextLabel.text = NSLocalizedString(@"sender's input", nil);
                }
            }
            
            break;
            
        default:
            NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)indexPath.section);
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0:
            return NSLocalizedString(@"transaction id:", nil);
            
        case 1:
            return @"summary:";

        case 2:
            return ([[[BRWalletManager sharedInstance] wallet] amountSentByTransaction:self.transaction] > 0) ?
                   NSLocalizedString(@"to:", nil) : NSLocalizedString(@"from:", nil);
            
        case 3:
            return ([[[BRWalletManager sharedInstance] wallet] amountSentByTransaction:self.transaction] > 0) ?
                   NSLocalizedString(@"from:", nil) : NSLocalizedString(@"to:", nil);

        default:
            NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)section);
    }
    
    return nil;
}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: return 44.0;
        case 1: return TRANSACTION_CELL_HEIGHT;
        case 2: return 60.0;
        case 3: return 60.0;
        default: NSAssert(FALSE, @"%s:%d %s: unkown section %d", __FILE__, __LINE__,  __func__, (int)indexPath.section);
    }
    
    return 44.0;
}


@end
