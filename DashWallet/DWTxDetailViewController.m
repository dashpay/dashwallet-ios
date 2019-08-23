//
//  DWTxDetailViewController.m
//  DashWallet
//
//  Created by Aaron Voisine for BreadWallet on 7/23/14.
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

#import "DWTxDetailViewController.h"

#import <DashSync/DashSync.h>
#include <arpa/inet.h>

#import "BRCopyLabel.h"
#import "DSTransactionAmountTableViewCell.h"
#import "DSTransactionDetailTableViewCell.h"
#import "DSTransactionIdentifierTableViewCell.h"
#import "DSTransactionStatusTableViewCell.h"


#define TRANSACTION_CELL_HEIGHT 75

@interface DWTxDetailViewController ()

@property (nonatomic, strong) NSArray *inputAddresses, *outputText, *outputDetail, *outputAmount, *outputIsBitcoin;
@property (nonatomic, assign) int64_t sent, received;
@property (nonatomic, strong) id txStatusObserver;

@end

@implementation DWTxDetailViewController

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
        [[NSNotificationCenter defaultCenter] addObserverForName:DSTransactionManagerTransactionStatusDidChangeNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *note) {
                                                               DSTransaction *tx = [[DWEnvironment sharedInstance].currentAccount transactionForHash:self.transaction.txHash];
                                                               
                                                               if (tx) self.transaction = tx;
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

- (void)setTransaction:(DSTransaction *)transaction
{
    DSPriceManager *manager = [DSPriceManager sharedInstance];
    NSMutableArray *mutableInputAddresses = [NSMutableArray array], *text = [NSMutableArray array], *detail = [NSMutableArray array], *amount = [NSMutableArray array], *currencyIsBitcoinInstead = [NSMutableArray array];
    DSAccount * account = transaction.account;
    uint64_t fee = [account feeForTransaction:transaction];
    NSUInteger outputAmountIndex = 0;
    
    _transaction = transaction;
    self.sent = [account amountSentByTransaction:transaction];
    self.received = [account amountReceivedFromTransaction:transaction];
    
    for (NSString *inputAddress in transaction.inputAddresses) {
        if (![mutableInputAddresses containsObject:inputAddress]) {
            [mutableInputAddresses addObject:inputAddress];
        }
    }
    
    for (NSString *address in transaction.outputAddresses) {
        NSData * script = transaction.outputScripts[outputAmountIndex];
        uint64_t amt = [transaction.outputAmounts[outputAmountIndex++] unsignedLongLongValue];
        
        if (address == (id)[NSNull null]) {
            if (self.sent > 0) {
                if ([script UInt8AtOffset:0] == OP_RETURN) {
                    UInt8 length = [script UInt8AtOffset:1];
                    if ([script UInt8AtOffset:2] == OP_SHAPESHIFT) {
                        NSMutableData * data = [NSMutableData data];
                        uint8_t v = BITCOIN_PUBKEY_ADDRESS;
                        [data appendBytes:&v length:1];
                        NSData * addressData = [script subdataWithRange:NSMakeRange(3, length - 1)];
                        
                        [data appendData:addressData];
                        [text addObject:[NSString base58checkWithData:data]];
                        [detail addObject:NSLocalizedString(@"Bitcoin address (shapeshift)", nil)];
                        if (transaction.associatedShapeshift.outputCoinAmount) {
                            [amount addObject:@([manager amountForUnknownCurrencyString:[transaction.associatedShapeshift.outputCoinAmount stringValue]])];
                        } else {
                            [amount addObject:@(UINT64_MAX)];
                        }
                        [currencyIsBitcoinInstead addObject:@TRUE];
                    }
                } else {
                    [currencyIsBitcoinInstead addObject:@FALSE];
                    [text addObject:NSLocalizedString(@"unknown address", nil)];
                    [detail addObject:NSLocalizedString(@"payment output", nil)];
                    [amount addObject:@(-amt)];
                }
                
            }
        }
        else if ([transaction isKindOfClass:[DSProviderRegistrationTransaction class]] && [((DSProviderRegistrationTransaction*)transaction).masternodeHoldingWallet containsHoldingAddress:address]) {
            if (self.sent == 0 || self.received + MASTERNODE_COST + fee == self.sent) {
                [text addObject:address];
                [detail addObject:NSLocalizedString(@"masternode holding address", nil)];
                [amount addObject:@(amt)];
                [currencyIsBitcoinInstead addObject:@FALSE];
            }
        }
        else if ([account containsAddress:address]) {
            if (self.sent == 0 || self.received == self.sent) {
                [text addObject:address];
                if (![[DWEnvironment sharedInstance].currentChain isMainnet]) {
                    DSFundsDerivationPath * derivationPath = [account derivationPathContainingAddress:address];
                    if ([derivationPath isBIP43Based] && [derivationPath purpose] == 44) {
                        [detail addObject:[NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"wallet address", nil), @"(BIP44)"]];
                    } else if ([derivationPath isBIP32Only]) {
                        [detail addObject:[NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"wallet address", nil), @"(BIP32)"]];
                    } else {
                        [detail addObject:[NSString stringWithFormat:@"%@ (%@)", NSLocalizedString(@"wallet address", nil), [derivationPath stringRepresentation]]];
                    }
                } else {
                    [detail addObject:NSLocalizedString(@"wallet address", nil)];
                }
                [amount addObject:@(amt)];
                [currencyIsBitcoinInstead addObject:@FALSE];
            }
        }
        else if (self.sent > 0) {
            [text addObject:address];
            [detail addObject:NSLocalizedString(@"payment address", nil)];
            [amount addObject:@(-amt)];
            [currencyIsBitcoinInstead addObject:@FALSE];
        }
    }
    
    if (self.sent > 0 && fee > 0 && fee != UINT64_MAX) {
        [text addObject:@""];
        [detail addObject:NSLocalizedString(@"dash network fee", nil)];
        [amount addObject:@(-fee)];
        [currencyIsBitcoinInstead addObject:@FALSE];
    }
    
    self.inputAddresses = mutableInputAddresses;
    self.outputText = text;
    self.outputDetail = detail;
    self.outputAmount = amount;
    self.outputIsBitcoin = currencyIsBitcoinInstead;
}

- (void)setBackgroundForCell:(UITableViewCell *)cell indexPath:(NSIndexPath *)path
{    
    [cell viewWithTag:100].hidden = (path.row > 0);
    [cell viewWithTag:101].hidden = (path.row + 1 < [self tableView:self.tableView numberOfRowsInSection:path.section]);
}

// MARK: - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    switch ([self.transaction type]) {
        case DSTransactionType_Classic:
            return 3;
            break;
        case DSTransactionType_Coinbase:
            return 2;
            break;
        default:
            return 4;
            break;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    NSInteger realSection = section;
    if ([self.transaction type] == DSTransactionType_Coinbase && section == 1) realSection++;
    switch (section) {
        case 0: return self.transaction.associatedShapeshift?(([self.transaction.associatedShapeshift.shapeshiftStatus integerValue]| eShapeshiftAddressStatus_Finished)?7:6):5;
        case 1: return (self.sent > 0) ? self.outputText.count : self.inputAddresses.count;
        case 2: return (self.sent > 0) ? self.inputAddresses.count : self.outputText.count;
        case 3: {
            switch ([self.transaction type]) {
                case DSTransactionType_SubscriptionRegistration:
                    return 3;
                    break;
                case DSTransactionType_SubscriptionResetKey:
                    return 2;
                    break;
                case DSTransactionType_SubscriptionTopUp:
                    return 2;
                    break;
                case DSTransactionType_ProviderRegistration:
                {
                    DSProviderRegistrationTransaction * providerRegistrationTransaction = (DSProviderRegistrationTransaction *)self.transaction;
                    DSLocalMasternode * localMasternode = providerRegistrationTransaction.localMasternode;
                    return localMasternode.holdingKeysWallet?9:8;
                    break;
                }
                case DSTransactionType_ProviderUpdateService:
                    return 2;
                    break;
                case DSTransactionType_ProviderUpdateRegistrar:
                    return 6;
                    break;
                default:
                    return 0;
                    break;
            }
        }
    }
    
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    DSPriceManager * walletManager = [DSPriceManager sharedInstance];
    DSChainManager * chainManager = [[DSChainsManager sharedInstance] chainManagerForChain:self.transaction.chain];
    NSUInteger peerCount = chainManager.peerManager.connectedPeerCount;
    NSUInteger relayCount = [chainManager.transactionManager relayCountForTransaction:self.transaction.txHash];
    DSAccount * account = self.transaction.account;
    NSString *s;
    
    NSInteger indexPathRow = indexPath.row;
    NSInteger realSection = indexPath.section;
    if ([self.transaction type] == DSTransactionType_Coinbase && indexPath.section == 1) realSection++;
    // Configure the cell...
    switch (realSection) {
        case 0:
            if (!self.transaction.associatedShapeshift) {
                if (indexPathRow > 1) indexPathRow += 2; // no assoc
            } else if (!([self.transaction.associatedShapeshift.shapeshiftStatus integerValue] | eShapeshiftAddressStatus_Finished)) {
                if (indexPathRow > 1) indexPathRow += 1;
            }
            switch (indexPathRow) {
                case 0:
                {
                    DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    cell.titleLabel.text = NSLocalizedString(@"type:", nil);
                    if ([self.transaction isMemberOfClass:[DSBlockchainUserRegistrationTransaction class]]) {
                        cell.statusLabel.text = NSLocalizedString(@"User Registration Transaction", nil);
                    } else if ([self.transaction isMemberOfClass:[DSBlockchainUserTopupTransaction class]]) {
                        cell.statusLabel.text = NSLocalizedString(@"User Topup Transaction", nil);
                    } else if ([self.transaction isMemberOfClass:[DSBlockchainUserResetTransaction class]]) {
                        cell.statusLabel.text = NSLocalizedString(@"User Reset Transaction", nil);
                    } else if ([self.transaction isMemberOfClass:[DSProviderRegistrationTransaction class]]) {
                        cell.statusLabel.text = NSLocalizedString(@"Masternode Registration Transaction", nil);
                    } else if ([self.transaction isMemberOfClass:[DSProviderUpdateServiceTransaction class]]) {
                        cell.statusLabel.text = NSLocalizedString(@"Masternode Update Service Transaction", nil);
                    } else if ([self.transaction isMemberOfClass:[DSProviderUpdateRegistrarTransaction class]]) {
                        cell.statusLabel.text = NSLocalizedString(@"Masternode Update Registrar Transaction", nil);
                    } else if ([self.transaction isMemberOfClass:[DSCoinbaseTransaction class]]) {
                        cell.statusLabel.text = NSLocalizedString(@"Coinbase Transaction", nil);
                    } else {
                        cell.statusLabel.text = NSLocalizedString(@"Classical Transaction", nil);
                    }
                    cell.moreInfoLabel.text = nil;
                    return cell;
                    break;
                }
                case 1:
                {
                    DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    cell.titleLabel.text = NSLocalizedString(@"id:", nil);
                    s = [NSString hexWithData:[NSData dataWithBytes:self.transaction.txHash.u8
                                                             length:sizeof(UInt256)].reverse];
                    cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                 [s substringFromIndex:s.length/2]];
                    cell.identifierLabel.copyableText = s;
                    return cell;
                }
                case 2:
                {
                    DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    cell.titleLabel.text = NSLocalizedString(@"shapeshift bitcoin id:", nil);
                    cell.statusLabel.text = [self.transaction.associatedShapeshift outputTransactionId];
                    cell.moreInfoLabel.text = nil;
                    return cell;
                }
                case 3:
                {
                    DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    cell.titleLabel.text = NSLocalizedString(@"shapeshift status:", nil);
                    cell.statusLabel.text = [self.transaction.associatedShapeshift shapeshiftStatusString];
                    cell.moreInfoLabel.text = nil;
                    return cell;
                }
                case 4:
                {
                    DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    cell.titleLabel.text = NSLocalizedString(@"status:", nil);
                    cell.moreInfoLabel.text = nil;
                    
                    uint32_t lastBlockHeight = [DWEnvironment sharedInstance].currentChain.lastBlockHeight;
                    if (self.transaction.hasUnverifiedInstantSendLock) {
                        cell.statusLabel.text = NSLocalizedString(@"processing", nil);
                        cell.moreInfoLabel.text = NSLocalizedString(@"verifying quorum",nil);
                    } else if (self.transaction.instantSendReceived && ((self.transaction.blockHeight == TX_UNCONFIRMED) || (lastBlockHeight - self.transaction.blockHeight) < 6)) {
                        cell.statusLabel.text = NSLocalizedString(@"locked with InstantSend", nil);
                        if (self.transaction.blockHeight != TX_UNCONFIRMED) {
                            cell.moreInfoLabel.text = [NSString stringWithFormat:@"%@ - %@",[NSString stringWithFormat:NSLocalizedString(@"confirmed in block #%d", nil),
                                                                                        self.transaction.blockHeight], self.txDateString];
                        } else if (self.transaction.transactionLockVotes.count) {
                            cell.moreInfoLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%d out of %d lock votes",nil),self.transaction.transactionLockVotes.count,self.transaction.inputHashes.count*10];
                        } else {
                            cell.moreInfoLabel.text = NSLocalizedString(@"accepted by quorum",nil);
                        }
                    } else if ([account transactionOutputsAreLocked:self.transaction]) {
                        cell.statusLabel.text = NSLocalizedString(@"recently mined (locked)", nil);
                    } else if (self.transaction.blockHeight != TX_UNCONFIRMED) {
                        cell.statusLabel.text = [NSString stringWithFormat:NSLocalizedString(@"confirmed in block #%d", nil),
                                                 self.transaction.blockHeight, self.txDateString];
                        cell.moreInfoLabel.text = self.txDateString;
                    }
                    else if (! [account transactionIsValid:self.transaction]) {
                        cell.statusLabel.text = NSLocalizedString(@"double spend", nil);
                    }
                    else if ([account transactionIsPending:self.transaction]) {
                        cell.statusLabel.text = NSLocalizedString(@"pending", nil);
                    }
                    else if (! [account transactionIsVerified:self.transaction]) {
                        cell.statusLabel.text = [NSString stringWithFormat:NSLocalizedString(@"seen by %d of %d peers", nil),
                                                 relayCount, peerCount];
                    }
                    else cell.statusLabel.text = NSLocalizedString(@"verified, waiting for confirmation", nil);
                    
                    return cell;
                }
                case 5:
                {
                    DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    cell.titleLabel.text = NSLocalizedString(@"size:", nil);
                    uint64_t roundedFeeCostPerByte = self.transaction.roundedFeeCostPerByte;
                    if (roundedFeeCostPerByte != UINT64_MAX) { //otherwise it's being received and can't know.
                        cell.statusLabel.text = roundedFeeCostPerByte == 1?NSLocalizedString(@"1 duff/byte",nil):[NSString stringWithFormat:NSLocalizedString(@"%d duffs/byte",nil), roundedFeeCostPerByte];
                        cell.moreInfoLabel.text = [@(self.transaction.size) stringValue];
                    } else {
                        cell.statusLabel.text = [@(self.transaction.size) stringValue];
                        cell.moreInfoLabel.text = nil;
                    }
                    
                    
                    return cell;
                }
                case 6:
                {
                    DSTransactionAmountTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TransactionCellIdentifier"];
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    if (self.sent > 0 && self.sent == self.received) {
                        cell.amountLabel.attributedText = [walletManager attributedStringForDashAmount:self.sent];
                        cell.fiatAmountLabel.text = [NSString stringWithFormat:@"(%@)",
                                                     [walletManager localCurrencyStringForDashAmount:self.sent]];
                    }
                    else {
                        cell.amountLabel.attributedText = [walletManager attributedStringForDashAmount:self.received - self.sent];
                        cell.fiatAmountLabel.text = [NSString stringWithFormat:@"(%@)",
                                                     [walletManager localCurrencyStringForDashAmount:self.received - self.sent]];
                    }
                    
                    return cell;
                }
                default:
                    break;
            }
            
            break;
            
        case 1: // drop through
        case 2:
            if ((self.sent > 0 && realSection == 1) || (self.sent == 0 && realSection == 2)) {
                DSTransactionDetailTableViewCell * cell;
                if ([self.outputText[indexPath.row] length] > 0) {
                    cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCellIdentifier" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                }
                else cell = [tableView dequeueReusableCellWithIdentifier:@"SubtitleCellIdentifier" forIndexPath:indexPath];
                [self setBackgroundForCell:cell indexPath:indexPath];
                cell.addressLabel.text = self.outputText[indexPath.row];
                cell.typeInfoLabel.text = self.outputDetail[indexPath.row];
                cell.amountLabel.textColor = (self.sent > 0) ? [UIColor colorWithRed:1.0 green:0.33 blue:0.33 alpha:1.0] :
                [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                
                
                long long outputAmount = [self.outputAmount[indexPath.row] longLongValue];
                if (outputAmount == UINT64_MAX) {
                    UIFont * font = [UIFont systemFontOfSize:17 weight:UIFontWeightLight];
                    UIFontDescriptor * fontD = [font.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
                    NSAttributedString * attributedString = [[NSAttributedString alloc] initWithString:@"fetching amount" attributes:@{NSFontAttributeName: [UIFont fontWithDescriptor:fontD size:0]}];
                    
                    cell.amountLabel.attributedText = attributedString;
                    cell.fiatAmountLabel.textColor = cell.amountLabel.textColor;
                    cell.fiatAmountLabel.text = @"";
                } else {
                    
                    
                    BOOL isBitcoinInstead = [self.outputIsBitcoin[indexPath.row] boolValue];
                    if (isBitcoinInstead) {
                        cell.amountLabel.text = [walletManager stringForBitcoinAmount:[self.outputAmount[indexPath.row] longLongValue]];
                        cell.amountLabel.textColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                        cell.fiatAmountLabel.text = [NSString stringWithFormat:@"(%@)",
                                                     [walletManager localCurrencyStringForBitcoinAmount:[self.outputAmount[indexPath.row]
#pragma clang diagnostic pop
                                                                                                         longLongValue]]];
                    } else {
                        cell.amountLabel.attributedText = [walletManager attributedStringForDashAmount:[self.outputAmount[indexPath.row] longLongValue] withTintColor:cell.amountLabel.textColor dashSymbolSize:CGSizeMake(9, 9)];
                        cell.fiatAmountLabel.text = [NSString stringWithFormat:@"(%@)",
                                                     [walletManager localCurrencyStringForDashAmount:[self.outputAmount[indexPath.row]
                                                                                                      longLongValue]]];
                    }
                    cell.fiatAmountLabel.textColor = cell.amountLabel.textColor;
                }
                return cell;
            }
            else if (self.inputAddresses[indexPath.row] != (id)[NSNull null]) {
                DSTransactionDetailTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCellIdentifier" forIndexPath:indexPath];
                [self setBackgroundForCell:cell indexPath:indexPath];
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                cell.addressLabel.text = self.inputAddresses[indexPath.row];
                cell.amountLabel.text = nil;
                cell.fiatAmountLabel.text = nil;
                if ([account containsAddress:self.inputAddresses[indexPath.row]]) {
                    cell.typeInfoLabel.text = NSLocalizedString(@"wallet address", nil);
                }
                else cell.typeInfoLabel.text = NSLocalizedString(@"spent address", nil);
                return cell;
            }
            else {
                DSTransactionDetailTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCellIdentifier" forIndexPath:indexPath];
                [self setBackgroundForCell:cell indexPath:indexPath];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                
                cell.addressLabel.text = NSLocalizedString(@"unknown address", nil);
                cell.typeInfoLabel.text = NSLocalizedString(@"spent input", nil);
                cell.amountLabel.text = nil;
                cell.fiatAmountLabel.text = nil;
                return cell;
            }
            
            
            break;
        case 3:
        {
            
            if ([self.transaction isMemberOfClass:[DSBlockchainUserRegistrationTransaction class]]) {
                DSBlockchainUserRegistrationTransaction * blockchainUserRegistrationTransaction = (DSBlockchainUserRegistrationTransaction *)self.transaction;
                switch (indexPath.row) {
                    case 0:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"public key:", nil); //will be BLS public key when released
                        s = [NSData dataWithUInt160:blockchainUserRegistrationTransaction.pubkeyHash].hexString;
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                    case 1:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"username:", nil);
                        cell.statusLabel.text = blockchainUserRegistrationTransaction.username;
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                    case 2:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"topup amount:", nil);
                        cell.statusLabel.text = [[DSPriceManager sharedInstance] stringForDashAmount:blockchainUserRegistrationTransaction.topupAmount];
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                        
                }
            } else if ([self.transaction isMemberOfClass:[DSBlockchainUserTopupTransaction class]]) {
                DSBlockchainUserTopupTransaction * blockchainUserTopupTransaction = (DSBlockchainUserTopupTransaction *)self.transaction;
                switch (indexPath.row) {
                    case 0:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"registration tx:", nil);
                        s = [NSData dataWithUInt256:blockchainUserTopupTransaction.registrationTransactionHash].hexString;
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                    case 1:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"topup amount:", nil);
                        cell.statusLabel.text = [[DSPriceManager sharedInstance] stringForDashAmount:blockchainUserTopupTransaction.topupAmount];
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                        
                }
            } else if ([self.transaction isMemberOfClass:[DSBlockchainUserResetTransaction class]]) {
                DSBlockchainUserResetTransaction * blockchainUserResetTransaction = (DSBlockchainUserResetTransaction *)self.transaction;
                switch (indexPath.row) {
                    case 0:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"registration tx:", nil);
                        s = [NSData dataWithUInt256:blockchainUserResetTransaction.registrationTransactionHash].hexString;
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                    case 1:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"new public key:", nil); //this is a BLS public key once it hits mainnet
                        s = [NSData dataWithUInt160:blockchainUserResetTransaction.replacementPublicKeyHash].hexString;
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                        
                }
            } else if ([self.transaction isMemberOfClass:[DSProviderRegistrationTransaction class]]) {
                DSProviderRegistrationTransaction * providerRegistrationTransaction = (DSProviderRegistrationTransaction *)self.transaction;
                switch (indexPath.row) {
                    case 0:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"IP address/port:", nil);
                        char s[INET6_ADDRSTRLEN];
                        NSString * ipAddressString = @(inet_ntop(AF_INET, &providerRegistrationTransaction.ipAddress.u32[3], s, sizeof(s)));
                        cell.statusLabel.text = [NSString stringWithFormat:@"%@:%d",ipAddressString,providerRegistrationTransaction.port];
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                    case 1:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"owner key hash:", nil);
                        s = [NSData dataWithUInt160:providerRegistrationTransaction.ownerKeyHash].hexString;
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                    case 2:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"owner key index:", nil);
                        DSLocalMasternode * localMasternode = providerRegistrationTransaction.localMasternode;
                        cell.statusLabel.text = localMasternode.ownerKeysWallet?[NSString stringWithFormat:@"%d",localMasternode.ownerWalletIndex]:NSLocalizedString(@"not owner",nil);
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                    case 3:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"operator key:", nil);
                        s = [NSData dataWithUInt384:providerRegistrationTransaction.operatorKey].hexString;
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                    case 4:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"operator key index:", nil);
                        DSLocalMasternode * localMasternode = providerRegistrationTransaction.localMasternode;
                        cell.statusLabel.text = localMasternode.operatorKeysWallet?[NSString stringWithFormat:@"%d",localMasternode.operatorWalletIndex]:NSLocalizedString(@"not operator",nil);
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                    case 5:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"voting key hash:", nil);
                        s = [NSData dataWithUInt160:providerRegistrationTransaction.votingKeyHash].hexString;
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                    case 6:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"voting key index:", nil);
                        DSLocalMasternode * localMasternode = providerRegistrationTransaction.localMasternode;
                        cell.statusLabel.text = localMasternode.votingKeysWallet?[NSString stringWithFormat:@"%d",localMasternode.votingWalletIndex]:NSLocalizedString(@"not voter",nil);
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                    case 7:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"payout Address", nil);
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@",[NSString addressWithScriptPubKey:providerRegistrationTransaction.scriptPayout onChain:providerRegistrationTransaction.chain]];
                        
                        return cell;
                        break;
                    }
                    case 8:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"holding funds index:", nil);
                        DSLocalMasternode * localMasternode = providerRegistrationTransaction.localMasternode;
                        cell.statusLabel.text = [NSString stringWithFormat:@"%d",localMasternode.holdingWalletIndex];
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                        
                }
            } else if ([self.transaction isMemberOfClass:[DSProviderUpdateServiceTransaction class]]) {
                DSProviderUpdateServiceTransaction * providerUpdateServiceTransaction = (DSProviderUpdateServiceTransaction *)self.transaction;
                switch (indexPath.row) {
                    case 0:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"IP address/port:", nil);
                        char s[INET6_ADDRSTRLEN];
                        NSString * ipAddressString = @(inet_ntop(AF_INET, &providerUpdateServiceTransaction.ipAddress.u32[3], s, sizeof(s)));
                        cell.statusLabel.text = [NSString stringWithFormat:@"%@:%d",ipAddressString,providerUpdateServiceTransaction.port];
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                    case 1:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"registration tx:", nil);
                        s = [NSData dataWithUInt256:providerUpdateServiceTransaction.providerRegistrationTransactionHash].hexString;
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                        
                        
                }
                
            } else if ([self.transaction isMemberOfClass:[DSProviderUpdateRegistrarTransaction class]]) {
                DSProviderUpdateRegistrarTransaction * providerUpdateRegistrarTransaction = (DSProviderUpdateRegistrarTransaction *)self.transaction;
                switch (indexPath.row) {
                    case 0:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"payout address:", nil);
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@",[NSString addressWithScriptPubKey:providerUpdateRegistrarTransaction.scriptPayout onChain:providerUpdateRegistrarTransaction.chain]];
                        
                        return cell;
                        break;
                    }
                    case 1:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"operator key:", nil);
                        s = uint384_hex(providerUpdateRegistrarTransaction.operatorKey);
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                    case 2:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"operator key index:", nil);
                        DSLocalMasternode * localMasternode = providerUpdateRegistrarTransaction.providerRegistrationTransaction.localMasternode;
                        cell.statusLabel.text = localMasternode.operatorKeysWallet?[NSString stringWithFormat:@"%d",localMasternode.operatorWalletIndex]:NSLocalizedString(@"not operator",nil);
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                    case 3:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"voting key hash:", nil);
                        s = uint160_hex(providerUpdateRegistrarTransaction.votingKeyHash);
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                    case 4:
                    {
                        DSTransactionStatusTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCellIdentifier" forIndexPath:indexPath];
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.titleLabel.text = NSLocalizedString(@"voting key index:", nil);
                        DSLocalMasternode * localMasternode = providerUpdateRegistrarTransaction.providerRegistrationTransaction.localMasternode;
                        cell.statusLabel.text = localMasternode.votingKeysWallet?[NSString stringWithFormat:@"%d",localMasternode.votingWalletIndex]:NSLocalizedString(@"not voter",nil);
                        cell.moreInfoLabel.text = nil;
                        return cell;
                        break;
                    }
                    case 5:
                    {
                        DSTransactionIdentifierTableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"IdCellIdentifier" forIndexPath:indexPath];
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        [self setBackgroundForCell:cell indexPath:indexPath];
                        cell.titleLabel.text = NSLocalizedString(@"registration tx:", nil);
                        s = uint256_hex(providerUpdateRegistrarTransaction.providerRegistrationTransactionHash);
                        cell.identifierLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                                     [s substringFromIndex:s.length/2]];
                        cell.identifierLabel.copyableText = s;
                        return cell;
                        break;
                    }
                }
            }
        }
            break;
    }
    NSAssert(NO, @"Unknown cell");
    return [[UITableViewCell alloc] init];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSUInteger realSection = section;
    if ([self.transaction type] == DSTransactionType_Coinbase && section == 1) realSection++;
    switch (realSection) {
        case 0: return nil;
        case 1: return (self.sent > 0) ? NSLocalizedString(@"to:", nil) : NSLocalizedString(@"from:", nil);
        case 2: return (self.sent > 0) ? NSLocalizedString(@"from:", nil) : NSLocalizedString(@"to:", nil);
        case 3: return NSLocalizedString(@"payload:", nil);
    }
    
    return nil;
}

// MARK: - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: return 44.0;
        case 1: return (self.sent > 0 && [self.outputText[indexPath.row] length] == 0) ? 40 : 60.0;
        case 2: return 60.0;
    }
    
    return 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSString *sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
    
    if (sectionTitle.length == 0) return 22.0;
    
    CGRect textRect = [sectionTitle boundingRectWithSize:CGSizeMake(self.view.frame.size.width - 30.0, CGFLOAT_MAX)
                                                 options:NSStringDrawingUsesLineFragmentOrigin
                                              attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:17 weight:UIFontWeightLight]} context:nil];
    
    return textRect.size.height + 12.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *headerview = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                                  [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15.0, 10.0, headerview.frame.size.width - 30.0,
                                                                    headerview.frame.size.height - 12.0)];
    
    titleLabel.text = [self tableView:tableView titleForHeaderInSection:section];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightLight];
    titleLabel.textColor = [UIColor darkTextColor];
    titleLabel.numberOfLines = 0;
    headerview.backgroundColor = [UIColor clearColor];
    [headerview addSubview:titleLabel];
    
    return headerview;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger i = [self.tableView.indexPathsForVisibleRows indexOfObject:indexPath];
    UITableViewCell *cell = (i < self.tableView.visibleCells.count) ? self.tableView.visibleCells[i] : nil;
    BRCopyLabel *copyLabel = (id)[cell viewWithTag:2];
    
    copyLabel.selectedColor = [UIColor clearColor];
    if (cell.selectionStyle != UITableViewCellSelectionStyleNone) [copyLabel toggleCopyMenu];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
