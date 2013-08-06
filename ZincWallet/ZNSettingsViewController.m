//
//  ZNSettingsViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/11/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNSettingsViewController.h"
#import "ZNSeedViewController.h"
#import "ZNWallet.h"
#import <QuartzCore/QuartzCore.h>

#define TRANSACTION_CELL_HEIGHT 75

@interface ZNSettingsViewController ()

@property (nonatomic, strong) NSArray *transactions;
@property (nonatomic, strong) id balanceObserver;
@property (nonatomic, strong) UIImageView *wallpaper;
@property (nonatomic, assign) CGPoint wallpaperStart;

@end

@implementation ZNSettingsViewController

//XXX need setting for denomination (BTC, mBTC or uBTC)
//XXX also for local currency, and exchange rate source

//XXX only show most recent 10-20 transactions and have a separate page for the rest with section headers for each day

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
    
    // HelveticaNeue-Medium is missing the BTC char :(
#if DARK_THEME
    [self.navigationController.navigationBar
     setTitleTextAttributes:@{UITextAttributeFont:[UIFont fontWithName:@"HelveticaNeue-Bold" size:19.0]}];
#else
    [self.navigationController.navigationBar
     setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor lightGrayColor],
                              UITextAttributeTextShadowColor:[UIColor whiteColor],
                              UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0.0, 1.0)],
                              UITextAttributeFont:[UIFont fontWithName:@"HelveticaNeue-Bold" size:19.0]}];
#endif

    if ([self.navigationController.navigationBar respondsToSelector:@selector(shadowImage)]) {
        [self.navigationController.navigationBar setShadowImage:[UIImage new]];
    }
    
    self.navigationController.navigationBar.clipsToBounds = YES;
    
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

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"wallpaper-default.png"]
     forBarMetrics:UIBarMetricsDefault];
}

- (void)viewWillDisappear:(BOOL)animated
{
    const float mask[6] = { 222, 255, 222, 255, 222, 255 };
    
    [self.navigationController.navigationBar
     setBackgroundImage:[UIImage imageWithCGImage:CGImageCreateWithMaskingColors([[UIImage new] CGImage], mask)]
     forBarMetrics:UIBarMetricsDefault];

    [super viewWillDisappear:animated];
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
        default: NSAssert(FALSE, @"[%s %s] line %d: unkown section %d", object_getClassName(self), sel_getName(_cmd),
                          __LINE__, section);
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

#if DARK_THEME
            textLabel.textColor = [UIColor whiteColor];
            textLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.15];
            
            localCurrencyLabel.textColor = [UIColor whiteColor];
            localCurrencyLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.15];
            
            detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
            detailTextLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.15];
            
            unconfirmedLabel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.67];
            unconfirmedLabel.textColor = [UIColor colorWithRed:0 green:0.33 blue:0.67 alpha:1.0];
            
            sentLabel.textColor = [UIColor whiteColor];
            sentLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.15];
            
            noTxLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.67];
            noTxLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.15];
#endif

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
                NSDictionary *tx = self.transactions[indexPath.row];
                __block uint64_t received = 0, spent = 0;
                int height = -1;
                
                [tx[@"inputs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    if (obj[@"prev_out"][@"addr"] && [w containsAddress:obj[@"prev_out"][@"addr"]]) {
                        spent += [obj[@"prev_out"][@"value"] unsignedLongLongValue];
                    }
                }];

                __block BOOL withinWallet = spent > 0 ? YES : NO;
                
                [tx[@"out"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    if (obj[@"addr"] && [w containsAddress:obj[@"addr"]]) {
                        received += [obj[@"value"] unsignedLongLongValue];
                        if (spent == 0) detailTextLabel.text = [@"to: " stringByAppendingString:obj[@"addr"]];
                    }
                    else if (spent > 0) {
                        if (obj[@"addr"]) detailTextLabel.text = [@"to: " stringByAppendingString:obj[@"addr"]];
                        withinWallet = NO;
                    }
                }];
                
                noTxLabel.hidden = YES;
                sentLabel.hidden = YES;
                unconfirmedLabel.hidden = NO;
                unconfirmedLabel.layer.cornerRadius = 3.0;
                
                if (tx[@"block_height"]) height = w.lastBlockHeight - [tx[@"block_height"] unsignedIntegerValue];
                
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
                }
                else {
                    textLabel.text = [w stringForAmount:received];
                    localCurrencyLabel.text =
                       [NSString stringWithFormat:@"(%@)", [w localCurrencyStringForAmount:received]];
                    sentLabel.text = @"recieved";
                }

                CGRect f = unconfirmedLabel.frame;
                
                f.size.width = [unconfirmedLabel.text sizeWithFont:unconfirmedLabel.font].width + 10;
                unconfirmedLabel.frame = f;
                                
                if (! detailTextLabel.text) detailTextLabel.text = @"can't decode payment address";
            }
            break;
            
        case 1:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            
            switch (indexPath.row) {
                case 0:
//                    cell.textLabel.text = @"safety tips";
//                    break;
//
//                case 1:
                    cell.textLabel.text = @"backup phrase";
                    cell.userInteractionEnabled = YES;
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
#if DARK_THEME
                    cell.textLabel.textColor = [UIColor whiteColor];
                    cell.textLabel.highlightedTextColor = [UIColor colorWithRed:0.0 green:0.33 blue:0.67 alpha:1.0];
                    cell.selectedBackgroundView = [[UIView alloc] initWithFrame:cell.frame];
                    cell.selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.67];
#endif
                    break;
                    
                case 1:
                    cell.textLabel.text = nil;
                    cell.userInteractionEnabled = NO;
                    cell.accessoryType = UITableViewCellAccessoryNone;
                    break;
            
                default: NSAssert(FALSE, @"[%s %s] line %d: unkown indexPath.row %d", object_getClassName(self),
                                  sel_getName(_cmd), __LINE__, indexPath.row);
            }
            break;
            
        case 2:
            cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];

            switch (indexPath.row) {
                case 0:
                    //cell.contentView.backgroundColor =
                    //    [UIColor colorWithPatternImage:[UIImage imageNamed:@"redgradient.png"]];
                    cell.textLabel.text = @"restore or start a new wallet";
#if DARK_THEME
                    cell.textLabel.textColor = [UIColor whiteColor];
#else
                    cell.textLabel.textColor = [UIColor redColor];
#endif
                    cell.textLabel.shadowColor = [UIColor clearColor];
                    cell.selectedBackgroundView = [[UIView alloc] initWithFrame:cell.frame];
                    cell.selectedBackgroundView.backgroundColor =
                        [UIColor colorWithPatternImage:[UIImage imageNamed:@"redgradient.png"]];
                    break;
                                        
                default:
                    NSAssert(FALSE, @"[%s %s] line %d: unkown indexPath.row %d", object_getClassName(self),
                             sel_getName(_cmd), __LINE__, indexPath.row);
            }
            break;
            
        default:
            NSAssert(FALSE, @"[%s %s] line %d: unkown indexPath.section %d", object_getClassName(self),
                     sel_getName(_cmd), __LINE__, indexPath.section);
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0: return @"recent transactions";
        case 1: return @"settings";
        case 2: return @"caution ⇣";
        default: NSAssert(FALSE, @"[%s %s] line %d: unkown section %d", object_getClassName(self), sel_getName(_cmd),
                          __LINE__, section);
    }
    
    return nil;
}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat h;
    
    switch (indexPath.section) {
        case 0:
            return TRANSACTION_CELL_HEIGHT;

        case 1:
            switch (indexPath.row) {
                case 0:
                    return 44;

                case 1:
                    h = tableView.frame.size.height - 22*3 -
                        self.navigationController.navigationBar.frame.size.height*2 -
                        (self.transactions.count ? self.transactions.count*TRANSACTION_CELL_HEIGHT :
                         TRANSACTION_CELL_HEIGHT);
                    return h > 0 ? h : 0;

                default:
                    NSAssert(FALSE, @"[%s %s] line %d: unkown indexPath.row %d", object_getClassName(self),
                             sel_getName(_cmd), __LINE__, indexPath.row);
            }
            return 44;
            
        case 2:
            return 44;

        default:
            NSAssert(FALSE, @"[%s %s] line %d: unkown indexPath.section %d", object_getClassName(self),
                     sel_getName(_cmd), __LINE__, indexPath.section);
    }
    
    return 44;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 22.0)];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, self.view.frame.size.width - 20, 22.0)];;
    
    l.text = [self tableView:tableView titleForHeaderInSection:section];
    l.backgroundColor = [UIColor clearColor];
#if DARK_THEME
    l.font = [UIFont fontWithName:@"HelveticaNeue" size:15];
    l.textColor = [UIColor colorWithRed:0.0 green:0.33 blue:0.67 alpha:1.0];
    
    //v.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.67];
    v.backgroundColor = [UIColor colorWithRed:0.75 green:0.87 blue:1.0 alpha:.85];
#else
    l.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15];
    l.textColor = [UIColor whiteColor];
    l.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.15];
    l.shadowOffset = CGSizeMake(0.0, 1.0);

    v.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.67];
#endif
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
//                    //XXX show safety tips
//                    [[[UIAlertView alloc] initWithTitle:nil message:@"Don't eat yellow snow." delegate:self
//                      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//                    break;
//                    
//                case 1:
                    [[[UIAlertView alloc] initWithTitle:@"WARNING" message:@"DO NOT let anyone see your backup phrase "
                      "or they can spend your bitcoins." delegate:self cancelButtonTitle:@"cancel"
                      otherButtonTitles:@"show", nil] show];
                    break;
                    
                default:
                    NSAssert(FALSE, @"[%s %s] line %d: unkown indexPath.row %d", object_getClassName(self),
                             sel_getName(_cmd), __LINE__, indexPath.row);
            }
            break;
            
        // section 2 is handled in storyboard
        case 2:
            break;
            
        default:
            NSAssert(FALSE, @"[%s %s] line %d: unkown indexPath.section %d", object_getClassName(self),
                     sel_getName(_cmd), __LINE__, indexPath.section);
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
