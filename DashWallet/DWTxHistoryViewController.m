//
//  DWTxHistoryViewController.m
//  DashWallet
//
//  Created by Aaron Voisine for BreadWallet on 6/11/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Copyright (c) 2018 Dash Core Group <contact@dash.org>
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

#import "DWTxHistoryViewController.h"
#import "DWRootViewController.h"
#import "DWTxDetailViewController.h"
#import "DWSeedViewController.h"
#import "UIImage+Utils.h"
#import <WebKit/WebKit.h>
#import "DWActionTableViewCell.h"
#import "DWTransactionTableViewCell.h"
#import "DWSettingsViewController.h"
#import "DWUpholdViewController.h"

#if SNAPSHOT
#import "DWStubTransaction.h"
#endif /* SNAPSHOT */

#define TRANSACTION_CELL_HEIGHT 75
#define OFFBLUE_COLOR [UIColor colorWithRed:25.0f/255.0f green:96.0f/255.0f blue:165.0f/255.0f alpha:1.0f]

static NSString *dateFormat(NSString *template)
{
    NSString *format = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:[NSLocale currentLocale]];
    
    format = [format stringByReplacingOccurrencesOfString:@", " withString:@" "];
    format = [format stringByReplacingOccurrencesOfString:@" a" withString:@"a"];
    format = [format stringByReplacingOccurrencesOfString:@"hh" withString:@"h"];
    format = [format stringByReplacingOccurrencesOfString:@" ha" withString:@"@ha"];
    format = [format stringByReplacingOccurrencesOfString:@"HH" withString:@"H"];
    format = [format stringByReplacingOccurrencesOfString:@"H '" withString:@"H'"];
    format = [format stringByReplacingOccurrencesOfString:@"H " withString:@"H'h' "];
    format = [format stringByReplacingOccurrencesOfString:@"H" withString:@"H'h'"
                                                  options:NSBackwardsSearch|NSAnchoredSearch range:NSMakeRange(0, format.length)];
    return format;
}

@interface DWTxHistoryViewController ()

@property (nonatomic, strong) IBOutlet UIView *logo;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *lock;

@property (nonatomic, strong) NSArray *transactions;
@property (nonatomic, assign) BOOL moreTx;
@property (nonatomic, strong) NSMutableDictionary *txDates;
@property (nonatomic, strong) id backgroundObserver, balanceObserver, txStatusObserver;

@end

@implementation DWTxHistoryViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.txDates = [NSMutableDictionary dictionary];
    self.navigationController.delegate = self;
    self.moreTx = YES;
    
#if SNAPSHOT
    _transactions = [DWStubTransaction stubTxs];
    [self updateTitleView];
    [self.navigationItem setRightBarButtonItem:nil];
    self.moreTx = NO;
#endif /* SNAPSHOT */
}

-(UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
#if SNAPSHOT
    [self.tableView reloadData];
    return;
#endif
    
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    
    if (authenticationManager.didAuthenticate) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            DSAccount * account = [DWEnvironment sharedInstance].currentAccount;
            self.transactions = account.allTransactions;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        });
    }
    
    if (! self.backgroundObserver) {
        self.backgroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                          object:nil queue:nil usingBlock:^(NSNotification *note) {
                                                              DSAccount * account = [DWEnvironment sharedInstance].currentAccount;
                                                              self.moreTx = YES;
                                                              self.transactions = account.allTransactions;
                                                              [self.tableView reloadData];
                                                              self.navigationItem.titleView = self.logo;
                                                              self.navigationItem.rightBarButtonItem = self.lock;
                                                          }];
    }
    
    if (! self.balanceObserver) {
        self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:DSWalletBalanceDidChangeNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *note) {
                                                               DSAccount * account = [DWEnvironment sharedInstance].currentAccount;
                                                               if (authenticationManager.didAuthenticate) {
                                                                   DSTransaction *tx = self.transactions.firstObject;
                                                                   
                                                                   self.transactions = account.allTransactions;
                                                                   if (self.transactions.firstObject != tx) {
                                                                       [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                                                                                     withRowAnimation:UITableViewRowAnimationAutomatic];
                                                                   }
                                                                   else [self.tableView reloadData];
                                                               }
                                                               
                                                               if (! [self.navigationItem.title isEqual:NSLocalizedString(@"Syncing:", nil)]) {
                                                                   if (! authenticationManager.didAuthenticate) self.navigationItem.titleView = self.logo;
                                                                   else [self updateTitleView];
                                                               }
                                                               
                                                               
                                                           }];
    }
    
    if (! self.txStatusObserver) {
        self.txStatusObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:DSTransactionManagerTransactionStatusDidChangeNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *note) {
                                                               DSAccount * account = [DWEnvironment sharedInstance].currentAccount;
                                                               self.transactions = account.allTransactions;
                                                               [self.tableView reloadData];
                                                           }];
    }
    
    if ([DSAuthenticationManager sharedInstance].didAuthenticate) {
        [self updateTitleView];
    } else {
        self.navigationItem.titleView = self.logo;
    }
}


-(UILabel*)titleLabel {
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSAccount * account = [DWEnvironment sharedInstance].currentAccount;
    UILabel * titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 1, 100)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [titleLabel setBackgroundColor:[UIColor clearColor]];
    NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:account.balance withTintColor:[UIColor whiteColor]] mutableCopy];
    NSString * titleString = [NSString stringWithFormat:@" (%@)",
                              [priceManager localCurrencyStringForDashAmount:account.balance]];
    [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
    titleLabel.attributedText = attributedDashString;
    return titleLabel;
}

-(void)updateTitleView {
#if SNAPSHOT
    self.navigationItem.titleView = [self titleLabel];
    int64_t fakeBalance = DUFFS * 42;
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:fakeBalance withTintColor:[UIColor whiteColor]] mutableCopy];
    NSString * titleString = [NSString stringWithFormat:@" (%@)",
                              [priceManager localCurrencyStringForDashAmount:fakeBalance]];
    [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
    ((UILabel*)self.navigationItem.titleView).attributedText = attributedDashString;
    [((UILabel*)self.navigationItem.titleView) sizeToFit];
    
    return;
#endif /* SNAPSHOT */
    
    if (self.navigationItem.titleView && [self.navigationItem.titleView isKindOfClass:[UILabel class]]) {
        DSPriceManager * priceManager = [DSPriceManager sharedInstance];
        DSAccount * account = [DWEnvironment sharedInstance].currentAccount;
        NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:account.balance withTintColor:[UIColor whiteColor]] mutableCopy];
        NSString * titleString = [NSString stringWithFormat:@" (%@)",
                                  [priceManager localCurrencyStringForDashAmount:account.balance]];
        [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
        ((UILabel*)self.navigationItem.titleView).attributedText = attributedDashString;
        [((UILabel*)self.navigationItem.titleView) sizeToFit];
    } else {
        self.navigationItem.titleView = [self titleLabel];
    }
}


- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) {
        //BUG: XXX this isn't triggered from start/recover new wallet
        if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
        self.backgroundObserver = nil;
        if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
        self.balanceObserver = nil;
        if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
        self.txStatusObserver = nil;
        //self.buyController = nil;
    }
    
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (uint32_t)blockHeight
{
    static uint32_t height = 0;
    DSChain * chain = [DWEnvironment sharedInstance].currentChain;
    uint32_t h = chain.lastBlockHeight;
    
    if (h > height) height = h;
    return height;
}

- (void)setTransactions:(NSArray *)transactions
{
    uint32_t height = self.blockHeight;
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    if (!authenticationManager.didAuthenticate &&
        [self.navigationItem.title isEqual:NSLocalizedString(@"Syncing:", nil)]) {
        _transactions = @[];
        if (transactions.count > 0) self.moreTx = YES;
    }
    else {
        if (transactions.count <= 5) self.moreTx = NO;
        _transactions = (self.moreTx) ? [transactions subarrayWithRange:NSMakeRange(0, 5)] : [transactions copy];
        
        if (!authenticationManager.didAuthenticate) {
            for (DSTransaction *tx in _transactions) {
                if (tx.blockHeight == TX_UNCONFIRMED ||
                    (tx.blockHeight > height - 5 && tx.blockHeight <= height)) continue;
                _transactions = [_transactions subarrayWithRange:NSMakeRange(0, [_transactions indexOfObject:tx])];
                self.moreTx = YES;
                break;
            }
        }
    }
}

- (NSString *)dateForTx:(DSTransaction *)tx
{
    static NSDateFormatter *monthDayHourFormatter = nil;
    static NSDateFormatter *yearMonthDayHourFormatter = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{ // BUG: need to watch for NSCurrentLocaleDidChangeNotification
        monthDayHourFormatter = [NSDateFormatter new];
        monthDayHourFormatter.dateFormat = dateFormat(@"Mdjmma");
        yearMonthDayHourFormatter = [NSDateFormatter new];
        yearMonthDayHourFormatter.dateFormat = dateFormat(@"yyMdja");
    });
    
    NSString *date = self.txDates[uint256_obj(tx.txHash)];
    
    if (date) return date;
    
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    NSTimeInterval now = [chain timestampForBlockHeight:TX_UNCONFIRMED];
    
    NSTimeInterval txTime = (tx.timestamp > 1) ? tx.timestamp : now;
    NSDate *txDate = [NSDate dateWithTimeIntervalSince1970:txTime];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger nowYear = [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
    NSInteger txYear = [calendar component:NSCalendarUnitYear fromDate:txDate];
    
    NSDateFormatter *desiredFormatter = (nowYear == txYear) ? monthDayHourFormatter : yearMonthDayHourFormatter;
    date = [desiredFormatter stringFromDate:txDate];
    if (tx.blockHeight != TX_UNCONFIRMED) self.txDates[uint256_obj(tx.txHash)] = date;
    return date;
}

// MARK: - IBAction

- (IBAction)done:(id)sender
{
    [DSEventManager saveEvent:@"tx_history:dismiss"];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)unlock:(id)sender
{
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    if (sender) [DSEventManager saveEvent:@"tx_history:unlock"];
    if (!authenticationManager.didAuthenticate) {
        [authenticationManager authenticateWithPrompt:nil andTouchId:YES alertIfLockout:YES completion:^(BOOL authenticated, BOOL cancelled) {
            if (authenticated) {
                if (sender) [DSEventManager saveEvent:@"tx_history:unlock_success"];
                
                [self updateTitleView];
                [self.navigationItem setRightBarButtonItem:nil animated:(sender) ? YES : NO];
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    DSAccount * account = [DWEnvironment sharedInstance].currentAccount;
                    self.transactions = account.allTransactions;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (sender && self.transactions.count > 0) {
                            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                                          withRowAnimation:UITableViewRowAnimationAutomatic];
                        }
                        else [self.tableView reloadData];
                    });
                });
            }
        }];
    }
}

- (IBAction)scanQR:(id)sender
{
    //TODO: show scanner in settings rather than dismissing
    [DSEventManager saveEvent:@"tx_history:scan_qr"];
    UINavigationController *nav = (id)self.navigationController.presentingViewController;
    
    nav.view.alpha = 0.0;
    
    [nav dismissViewControllerAnimated:NO completion:^{
        [(id)((DWRootViewController *)nav.viewControllers.firstObject).sendViewController scanQR:nil];
        [UIView animateWithDuration:0.1 delay:1.5 options:0 animations:^{ nav.view.alpha = 1.0; } completion:nil];
    }];
}

- (IBAction)showTx:(id)sender
{
    [DSEventManager saveEvent:@"tx_history:show_tx"];
    DWTxDetailViewController *detailController
    = [self.storyboard instantiateViewControllerWithIdentifier:@"TxDetailViewController"];
    detailController.transaction = sender;
    detailController.txDateString = [self dateForTx:sender];
    [self.navigationController pushViewController:detailController animated:YES];
}

- (IBAction)more:(id)sender
{
    [DSEventManager saveEvent:@"tx_history:more"];
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    DSAccount * account = [DWEnvironment sharedInstance].currentAccount;
    NSUInteger txCount = self.transactions.count;
    
    if (!authenticationManager.didAuthenticate) {
        [self unlock:sender];
        return;
    }
    
    [self.tableView beginUpdates];
    [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:txCount inSection:0]]
                          withRowAnimation:UITableViewRowAnimationFade];
    self.moreTx = NO;
    self.transactions = account.allTransactions;
    
    NSMutableArray *transactions = [NSMutableArray arrayWithCapacity:self.transactions.count];
    
    while (txCount == 0 || txCount < self.transactions.count) {
        [transactions addObject:[NSIndexPath indexPathForRow:txCount++ inSection:0]];
    }
    
    [self.tableView insertRowsAtIndexPaths:transactions withRowAnimation:UITableViewRowAnimationTop];
    [self.tableView endUpdates];
}

//- (void)showBuyAlert
//{
//    // grab a blurred image for the background
//    UIGraphicsBeginImageContext(self.navigationController.view.bounds.size);
//    [self.navigationController.view drawViewHierarchyInRect:self.navigationController.view.bounds
//                                         afterScreenUpdates:NO];
//    UIImage *bgImg = UIGraphicsGetImageFromCurrentImageContext();
//    UIGraphicsEndImageContext();
//    UIImage *blurredBgImg = [bgImg blurWithRadius:3];
//
//    // display the popup
//    __weak BREventConfirmView *view =
//        [[NSBundle mainBundle] loadNibNamed:@"BREventConfirmView" owner:nil options:nil][0];
//    view.titleLabel.text = NSLocalizedString(@"Buy dash in dashwallet!", nil);
//    view.descriptionLabel.text =
//        NSLocalizedString(@"You can now buy dash in\ndashwallet with cash or\nbank transfer.", nil);
//    [view.okBtn setTitle:NSLocalizedString(@"Try It!", nil) forState:UIControlStateNormal];
//
//    view.image = blurredBgImg;
//    view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
//    view.frame = self.navigationController.view.bounds;
//    view.alpha = 0;
//    [self.navigationController.view addSubview:view];
//
//    [UIView animateWithDuration:.5 animations:^{
//        view.alpha = 1;
//    }];
//
//    view.completionHandler = ^(BOOL didApprove) {
//        if (didApprove) [self showBuy];
//
//        [UIView animateWithDuration:.5 animations:^{
//            view.alpha = 0;
//        } completion:^(BOOL finished) {
//            [view removeFromSuperview];
//        }];
//    };
//}

// MARK: - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    bool buyEnabled = FALSE;
    switch (section) {
        case 0:
            if (self.transactions.count == 0) return 1;
            return (self.moreTx) ? self.transactions.count + 1 : self.transactions.count;
            
        case 1:
            return (buyEnabled ? 4 : 3);
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *noTxIdent = @"NoTxCell", *transactionIdent = @"TransactionCell", *actionIdent = @"ActionCell",
    *disclosureIdent = @"DisclosureCell";
    UITableViewCell *cell = nil;
    
    switch (indexPath.section) {
        case 0:
            if (self.moreTx && indexPath.row >= self.transactions.count) {
                cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
                DWActionTableViewCell * actionCell = (DWActionTableViewCell *)cell;
                cell.textLabel.text = (indexPath.row > 0) ? NSLocalizedString(@"more...", nil) :
                NSLocalizedString(@"Transaction history", nil);
                actionCell.imageIcon = [UIImage imageNamed:@"transaction-history"];
                actionCell.selectedImageIcon = [UIImage imageNamed:@"transaction-history-selected"];
            }
            else if (self.transactions.count > 0) {
                cell = [tableView dequeueReusableCellWithIdentifier:transactionIdent];
#if SNAPSHOT
                [self mock_configureTxCell:(DWTransactionTableViewCell *)cell indexPath:indexPath];
#else
                [self configureTxCell:(DWTransactionTableViewCell *)cell indexPath:indexPath];
#endif /* SNAPSHOT */
            }
            else cell = [tableView dequeueReusableCellWithIdentifier:noTxIdent];
            
            break;
            
        case 1:
        {
            bool buyEnabled = FALSE;
            long adjustedRow = !buyEnabled ? indexPath.row + 1 : indexPath.row;
            switch (adjustedRow) {
                case 0:
                    cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
                    cell.textLabel.text = NSLocalizedString(@"Buy Dash", nil);
                    cell.imageView.image = [UIImage imageNamed:@"dash-buy-blue-small"];
                    break;
                    
                case 1:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
                    DWActionTableViewCell * actionCell = (DWActionTableViewCell *)cell;
                    cell.textLabel.text = NSLocalizedString(@"Import private key", nil);
                    actionCell.imageIcon = [UIImage imageNamed:@"scan-qr-code"];
                    actionCell.selectedImageIcon = [UIImage imageNamed:@"scan-qr-code-selected"];
                    break;
                }
                case 2:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
                    DWActionTableViewCell * actionCell = (DWActionTableViewCell *)cell;
                    cell.textLabel.text = NSLocalizedString(@"Uphold account", nil);
                    actionCell.imageIcon = [UIImage imageNamed:@"uphold-icon"];
                    actionCell.selectedImageIcon = [UIImage imageNamed:@"uphold-icon-selected"];
                    break;
                }
                case 3:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
                    DWActionTableViewCell * actionCell = (DWActionTableViewCell *)cell;
                    cell.textLabel.text = NSLocalizedString(@"Settings", nil);
                    actionCell.imageIcon = [UIImage imageNamed:@"settings"];
                    actionCell.selectedImageIcon = [UIImage imageNamed:@"settings-selected"];
                    break;
                }
            }
            
            break;
        }
    }
    NSParameterAssert(cell);
    return cell ?: [[UITableViewCell alloc] init];
}

- (void)configureTxCell:(DWTransactionTableViewCell *)transactionCell indexPath:(NSIndexPath *)indexPath {
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSAccount * account = [DWEnvironment sharedInstance].currentAccount;

    UILabel *textLabel = transactionCell.amountLabel;
    UILabel *detailTextLabel = transactionCell.dateLabel;
    UILabel *unconfirmedLabel = transactionCell.confirmationsLabel;
    UILabel *localCurrencyLabel = transactionCell.fiatAmountLabel;
    UILabel *sentLabel = transactionCell.directionLabel;
    UILabel *balanceLabel = transactionCell.remainingAmountLabel;
    UILabel *localBalanceLabel = transactionCell.remainingFiatAmountLabel;
    UIImageView *shapeshiftImageView = transactionCell.shapeshiftImageView;
    
    DSTransaction *tx = self.transactions[indexPath.row];
    BOOL instantSendReceived = tx.instantSendReceived;
    BOOL processingInstantSend = tx.hasUnverifiedInstantSendLock;
    uint32_t transactionLocksCount = [tx.transactionLockVotes count];
    uint64_t received = [account amountReceivedFromTransaction:tx],
    sent = [account amountSentByTransaction:tx],
    balance = [account balanceAfterTransaction:tx];
    uint32_t blockHeight = self.blockHeight;
    uint32_t confirms = (tx.blockHeight > blockHeight) ? 0 : (blockHeight - tx.blockHeight) + 1;
    
    textLabel.textColor = [UIColor darkTextColor];
    sentLabel.hidden = YES;
    unconfirmedLabel.hidden = NO;
    unconfirmedLabel.backgroundColor = [UIColor clearColor];
    detailTextLabel.text = [self dateForTx:tx];
    balanceLabel.attributedText = (authenticationManager.didAuthenticate) ? [priceManager attributedStringForDashAmount:balance withTintColor:balanceLabel.textColor dashSymbolSize:CGSizeMake(9, 9)] : nil;
    localBalanceLabel.text = (authenticationManager.didAuthenticate) ? [NSString stringWithFormat:@"(%@)", [priceManager localCurrencyStringForDashAmount:balance]] : nil;
    shapeshiftImageView.hidden = !tx.associatedShapeshift;
    
    if (confirms == 0 && ![account transactionIsValid:tx]) {
        unconfirmedLabel.text = NSLocalizedString(@"INVALID", nil);
        unconfirmedLabel.backgroundColor = [UIColor redColor];
        balanceLabel.text = localBalanceLabel.text = nil;
    }
    else if (!instantSendReceived && confirms == 0 && [account transactionIsPending:tx]) {
        unconfirmedLabel.text = NSLocalizedString(@"Pending", nil);
        unconfirmedLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.2];
        textLabel.textColor = [UIColor grayColor];
        balanceLabel.text = localBalanceLabel.text = nil;
    }
    else if (!instantSendReceived && confirms == 0 && ![account transactionIsVerified:tx]) {
        unconfirmedLabel.text = NSLocalizedString(@"Unverified", nil);
    }
    else if ([account transactionOutputsAreLocked:tx]) {
        unconfirmedLabel.text = NSLocalizedString(@"Locked", nil);
        unconfirmedLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.2];
        textLabel.textColor = [UIColor colorWithRed:1 green:221/255 blue:0 alpha:1];
        balanceLabel.text = localBalanceLabel.text = nil;
    }
    else if (!instantSendReceived && confirms < 6) {
        if (confirms == 0 && processingInstantSend) unconfirmedLabel.text = NSLocalizedString(@"Processing", nil);
        else if (confirms == 0) unconfirmedLabel.text = NSLocalizedString(@"0 confirmations", nil);
        else if (confirms == 1) unconfirmedLabel.text = NSLocalizedString(@"1 confirmation", nil);
        else unconfirmedLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%d confirmations", nil),
                                      (int)confirms];
    }
    else {
        unconfirmedLabel.text = nil;
        unconfirmedLabel.hidden = YES;
        sentLabel.hidden = NO;
    }
    sentLabel.textColor = [UIColor whiteColor];
    if (sent > 0 && received == sent) {
        textLabel.attributedText = [priceManager attributedStringForDashAmount:sent withTintColor:textLabel.textColor];
        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                   [priceManager localCurrencyStringForDashAmount:sent]];
        sentLabel.text = NSLocalizedString(@"Moved", nil);
        sentLabel.backgroundColor = UIColorFromRGB(0x008DE4);
    }
    else if (sent > 0) {
        textLabel.attributedText = [priceManager attributedStringForDashAmount:received - sent withTintColor:textLabel.textColor];
        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                   [priceManager localCurrencyStringForDashAmount:received - sent]];
        sentLabel.text = NSLocalizedString(@"Sent", nil);
        sentLabel.backgroundColor = UIColorFromRGB(0xD0021B);
    }
    else {
        textLabel.attributedText = [priceManager attributedStringForDashAmount:received withTintColor:textLabel.textColor];
        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                   [priceManager localCurrencyStringForDashAmount:received]];
        if (instantSendReceived) {
            sentLabel.text = NSLocalizedString(@"Received", nil);
        } else {
            sentLabel.text = NSLocalizedString(@"Received", nil);
        }
        sentLabel.backgroundColor = UIColorFromRGB(0x7ED321);
    }
    
    if (! unconfirmedLabel.hidden) {
        unconfirmedLabel.layer.cornerRadius = 9.0;
        unconfirmedLabel.text = [unconfirmedLabel.text stringByAppendingString:@"   "];
        unconfirmedLabel.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    }
    else {
        sentLabel.layer.cornerRadius = 9.0;
        sentLabel.text = [sentLabel.text stringByAppendingString:@"   "];
        sentLabel.highlightedTextColor = sentLabel.textColor;
    }
}

#if SNAPSHOT
- (void)mock_configureTxCell:(DWTransactionTableViewCell *)transactionCell indexPath:(NSIndexPath *)indexPath {
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    
    UILabel *textLabel = transactionCell.amountLabel;
    UILabel *detailTextLabel = transactionCell.dateLabel;
    UILabel *unconfirmedLabel = transactionCell.confirmationsLabel;
    UILabel *localCurrencyLabel = transactionCell.fiatAmountLabel;
    UILabel *sentLabel = transactionCell.directionLabel;
    UILabel *balanceLabel = transactionCell.remainingAmountLabel;
    UILabel *localBalanceLabel = transactionCell.remainingFiatAmountLabel;
    UIImageView *shapeshiftImageView = transactionCell.shapeshiftImageView;
    
    DWStubTransaction *tx = self.transactions[indexPath.row];
    BOOL instantSendReceived = tx.instantSendReceived;
    BOOL processingInstantSend = tx.hasUnverifiedInstantSendLock;
    uint64_t received = tx.received;
    uint64_t sent = tx.sent;
    uint64_t balance = tx.balance;
    uint32_t confirms = tx.confirms;
    
    textLabel.textColor = [UIColor darkTextColor];
    sentLabel.hidden = YES;
    unconfirmedLabel.hidden = NO;
    unconfirmedLabel.backgroundColor = [UIColor clearColor];
    detailTextLabel.text = [self dateForTx:(DSTransaction *)tx];
    balanceLabel.attributedText = (tx.processAsAuthenticated) ? [priceManager attributedStringForDashAmount:balance withTintColor:balanceLabel.textColor dashSymbolSize:CGSizeMake(9, 9)] : nil;
    localBalanceLabel.text = (tx.processAsAuthenticated) ? [NSString stringWithFormat:@"(%@)", [priceManager localCurrencyStringForDashAmount:balance]] : nil;
    shapeshiftImageView.hidden = !tx.associatedShapeshift;
    
    if (confirms == 0 && !tx.transactionIsValid) {
        unconfirmedLabel.text = NSLocalizedString(@"INVALID", nil);
        unconfirmedLabel.backgroundColor = [UIColor redColor];
        balanceLabel.text = localBalanceLabel.text = nil;
    }
    else if (!instantSendReceived && confirms == 0 && tx.transactionIsPending) {
        unconfirmedLabel.text = NSLocalizedString(@"Pending", nil);
        unconfirmedLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.2];
        textLabel.textColor = [UIColor grayColor];
        balanceLabel.text = localBalanceLabel.text = nil;
    }
    else if (!instantSendReceived && confirms == 0 && !tx.transactionIsVerified) {
        unconfirmedLabel.text = NSLocalizedString(@"Unverified", nil);
    }
    else if (tx.transactionOutputsAreLocked) {
        unconfirmedLabel.text = NSLocalizedString(@"Locked", nil);
        unconfirmedLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.2];
        textLabel.textColor = [UIColor colorWithRed:1 green:221/255 blue:0 alpha:1];
        balanceLabel.text = localBalanceLabel.text = nil;
    }
    else if (!instantSendReceived && confirms < 6) {
        if (confirms == 0 && processingInstantSend) unconfirmedLabel.text = NSLocalizedString(@"Processing", nil);
        else if (confirms == 0) unconfirmedLabel.text = NSLocalizedString(@"0 confirmations", nil);
        else if (confirms == 1) unconfirmedLabel.text = NSLocalizedString(@"1 confirmation", nil);
        else unconfirmedLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%d confirmations", nil),
                                      (int)confirms];
    }
    else {
        unconfirmedLabel.text = nil;
        unconfirmedLabel.hidden = YES;
        sentLabel.hidden = NO;
    }
    sentLabel.textColor = [UIColor whiteColor];
    if (sent > 0 && received == sent) {
        textLabel.attributedText = [priceManager attributedStringForDashAmount:sent withTintColor:textLabel.textColor];
        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                   [priceManager localCurrencyStringForDashAmount:sent]];
        sentLabel.text = NSLocalizedString(@"Moved", nil);
        sentLabel.backgroundColor = UIColorFromRGB(0x008DE4);
    }
    else if (sent > 0) {
        textLabel.attributedText = [priceManager attributedStringForDashAmount:received - sent withTintColor:textLabel.textColor];
        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                   [priceManager localCurrencyStringForDashAmount:received - sent]];
        sentLabel.text = NSLocalizedString(@"Sent", nil);
        sentLabel.backgroundColor = UIColorFromRGB(0xD0021B);
    }
    else {
        textLabel.attributedText = [priceManager attributedStringForDashAmount:received withTintColor:textLabel.textColor];
        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                   [priceManager localCurrencyStringForDashAmount:received]];
        if (instantSendReceived) {
            sentLabel.text = NSLocalizedString(@"Received", nil);
        } else {
            sentLabel.text = NSLocalizedString(@"Received", nil);
        }
        sentLabel.backgroundColor = UIColorFromRGB(0x7ED321);
    }
    
    if (! unconfirmedLabel.hidden) {
        unconfirmedLabel.layer.cornerRadius = 9.0;
        unconfirmedLabel.text = [unconfirmedLabel.text stringByAppendingString:@"   "];
        unconfirmedLabel.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    }
    else {
        sentLabel.layer.cornerRadius = 9.0;
        sentLabel.text = [sentLabel.text stringByAppendingString:@"   "];
        sentLabel.highlightedTextColor = sentLabel.textColor;
    }
}
#endif /* SNAPSHOT */

// MARK: - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: return TRANSACTION_CELL_HEIGHT;
        case 1: return 50.0;
    }
    
    return 50.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 0;
//    NSString *sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
//
//    if (sectionTitle.length == 0) return 22.0;
//
//    CGRect r = [sectionTitle boundingRectWithSize:CGSizeMake(self.view.frame.size.width - 20.0, CGFLOAT_MAX)
//                                          options:NSStringDrawingUsesLineFragmentOrigin
//                                       attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:14]} context:nil];
//
//    return r.size.height + 22.0 + 10.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *l = [UILabel new];
    CGRect r = CGRectMake(15.0, 0.0, v.frame.size.width - 20.0, v.frame.size.height - 22.0);
    
    l.text = [self tableView:tableView titleForHeaderInSection:section];
    l.backgroundColor = [UIColor clearColor];
    l.font = [UIFont systemFontOfSize:14];
    l.textColor = [UIColor grayColor];
    l.shadowColor = [UIColor whiteColor];
    l.shadowOffset = CGSizeMake(0.0, 1.0);
    l.numberOfLines = 0;
    r.size.width = [l sizeThatFits:r.size].width;
    r.origin.x = (self.view.frame.size.width - r.size.width)/2;
    if (r.origin.x < 15.0) r.origin.x = 15.0;
    l.frame = r;
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
    UIViewController *destinationController = nil;
    
    switch (indexPath.section) {
        case 0: // transaction
            if (self.moreTx && indexPath.row >= self.transactions.count) { // more...
                [self performSelector:@selector(more:) withObject:tableView afterDelay:0.0];
            }
            else if (self.transactions.count > 0) [self showTx:self.transactions[indexPath.row]]; // transaction details
            
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            break;
            
        case 1:
        {
            bool buyEnabled = FALSE;//[[BRAPIClient sharedClient] featureEnabled:BRFeatureFlagsBuyDash];
            long adjustedRow = !buyEnabled ? indexPath.row + 1 : indexPath.row;
            switch (adjustedRow) {
                case 0: // buy dash
                    [DSEventManager saveEvent:@"tx_history:buy_btc"];
                    [tableView deselectRowAtIndexPath:indexPath animated:YES];
                    //[self showBuy];
                    break;
                    
                case 1: // Import private key
                    [DSEventManager saveEvent:@"tx_history:import_priv_key"];
                    [self scanQR:nil];
                    break;
                    
                case 2: { // uphold
                    if ([DSAuthenticationManager sharedInstance].didAuthenticate) {
                        UIViewController *upholdController = [DWUpholdViewController controller];
                        [self.navigationController pushViewController:upholdController animated:YES];
                    }
                    else {
                        [[DSAuthenticationManager sharedInstance] authenticateWithPrompt:nil andTouchId:YES alertIfLockout:YES completion:^(BOOL authenticatedOrSuccess, BOOL cancelled) {
                            if (authenticatedOrSuccess) {
                                UIViewController *upholdController = [DWUpholdViewController controller];
                                [self.navigationController pushViewController:upholdController animated:YES];
                            }
                        }];
                    }
                    [tableView deselectRowAtIndexPath:indexPath animated:YES];
                    break;
                }
                case 3: // settings
                    [DSEventManager saveEvent:@"tx_history:settings"];
                    destinationController = [DWSettingsViewController controller];
                    [self.navigationController pushViewController:destinationController animated:YES];
                    break;
            }
            
            break;
        }
    }
}

// Custom navigation transition disabled due to buggy transitions with search bar
//
//// MARK: - UIViewControllerAnimatedTransitioning
//
//// This is used for percent driven interactive transitions, as well as for container controllers that have companion
//// animations that might need to synchronize with the main animation.
//- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
//{
//    return 0.35;
//}
//
//// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
//- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
//{
//    UIView *containerView = transitionContext.containerView;
//    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
//    *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
//
//    BOOL pop = to == self || ![self.navigationController.viewControllers containsObject:from];
//
//    to.view.center = CGPointMake(containerView.frame.size.width*(pop ? -1 : 3)/2, to.view.center.y);
//    [containerView addSubview:to.view];
//
//    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
//          initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
//              to.view.center = from.view.center;
//              from.view.center = CGPointMake(containerView.frame.size.width*(pop ? 3 : -1)/2, from.view.center.y);
//          } completion:^(BOOL finished) {
//              if (pop) [from.view removeFromSuperview];
//              [transitionContext completeTransition:YES];
//          }];
//}
//
//// MARK: - UINavigationControllerDelegate
//
//- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
//                                  animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC
//                                                 toViewController:(UIViewController *)toVC
//{
//    return self;
//}
//
//// MARK: - UIViewControllerTransitioningDelegate
//
//- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
//                                                                  presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
//{
//    return self;
//}
//
//- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
//{
//    return self;
//}

@end
