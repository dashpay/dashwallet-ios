//
//  BRSettingsViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 12/3/14.
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

#import "BRSettingsViewController.h"
#import "BRSeedViewController.h"
#import "BRWalletManager.h"
#import "BRWallet.h"

@interface BRSettingsViewController ()

@property (nonatomic, assign) BOOL touchId;
@property (nonatomic, strong) UITableViewController *selectorController;
@property (nonatomic, strong) NSArray *selectorOptions;
@property (nonatomic, strong) NSString *selectedOption;
@property (nonatomic, assign) NSUInteger selectorType;
@property (nonatomic, strong) id balanceObserver;

@end

@implementation BRSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.touchId = [BRWalletManager sharedInstance].touchIdEnabled;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    BRWalletManager *m = [BRWalletManager sharedInstance];

    if (! self.balanceObserver) {
        self.balanceObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if (self.selectorType == 0) {
                    self.selectorController.title = [NSString stringWithFormat:@"%@ = %@",
                                                     [m localCurrencyStringForAmount:SATOSHIS/m.localCurrencyPrice],
                                                     [m stringForAmount:SATOSHIS/m.localCurrencyPrice]];
                }
            }];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) {
        if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
        self.balanceObserver = nil;
    }
    
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
}

- (UITableViewController *)selectorController
{
    if (_selectorController) return _selectorController;
    _selectorController = [[UITableViewController alloc] initWithStyle:UITableViewStylePlain];
    _selectorController.transitioningDelegate = self.navigationController.viewControllers.firstObject;
    _selectorController.tableView.dataSource = self;
    _selectorController.tableView.delegate = self;
    _selectorController.tableView.backgroundColor = [UIColor clearColor];
    _selectorController.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    return _selectorController;
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

#pragma mark - IBAction

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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView == self.selectorController.tableView) return 1;
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == self.selectorController.tableView) return self.selectorOptions.count;
    
    switch (section) {
        case 0: return 2;
        case 1: return (self.touchId) ? 3 : 2;
        case 2: return 2;
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *toggleIdent = @"ToggleCell", *disclosureIdent = @"DisclosureCell", *restoreIdent = @"RestoreCell",
                    *actionIdent = @"ActionCell", *selectorIdent = @"SelectorCell",
                    *selectorOptionCell = @"SelectorOptionCell";
    UITableViewCell *cell = nil;
    UILabel *toggleLabel;
    UISwitch *toggleSwitch;
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
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = NSLocalizedString(@"about", nil);
                    break;
                    
                case 1:
                    cell.textLabel.text = NSLocalizedString(@"backup phrase", nil);
                    break;
            }
            
            break;
            
        case 1:
            switch (indexPath.row) {
                case 0:
                    cell = [tableView dequeueReusableCellWithIdentifier:selectorIdent];
                    cell.detailTextLabel.text = m.localCurrencyCode;
                    break;
            
                case 1:
                    if (self.touchId) {
                        cell = [tableView dequeueReusableCellWithIdentifier:selectorIdent];
                        cell.textLabel.text = NSLocalizedString(@"touch id limit", nil);
                        cell.detailTextLabel.text = [m stringForAmount:m.spendingLimit];
                        break;
                    }
                    // passthrough if ! self.touchId
                    
                case 2:
                    cell = [tableView dequeueReusableCellWithIdentifier:toggleIdent];
                    toggleLabel = (id)[cell viewWithTag:2];
                    toggleSwitch = (id)[cell viewWithTag:3];
                    toggleSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:SETTINGS_SKIP_FEE_KEY];
                    toggleLabel.hidden = (toggleSwitch.on) ? NO : YES;
                    break;
            }
            
            break;
            
        case 2:
            switch (indexPath.row) {
                case 0:
                    cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
                    cell.textLabel.text = NSLocalizedString(@"change passcode", nil);
                    break;
                    
                case 1:
                    cell = [tableView dequeueReusableCellWithIdentifier:restoreIdent];
                    break;
            }
    }

    [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
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
            return NSLocalizedString(@"bitcoin network fees are only optional for high priority transactions "
                                     "(removal may cause delays)", nil);            
    }
    
    return nil;
}

#pragma mark - UITableViewDelegate

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
    l.textColor = [UIColor grayColor];
    l.shadowColor = [UIColor whiteColor];
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
    UIViewController *c = nil;
    UILabel *l = nil;
    NSMutableAttributedString *s = nil;
    BRWalletManager *m = [BRWalletManager sharedInstance];
    
    if (tableView == self.selectorController.tableView) {
        self.selectedOption = self.selectorOptions[indexPath.row];
        
        if (self.selectorType == 0) {
            m.localCurrencyCode = self.selectedOption;
        }
        else m.spendingLimit = (indexPath.row > 0) ? pow(10, indexPath.row + 6) : 0;
        
        [tableView reloadData];
        [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self.tableView reloadData];
        return;
    }
    
    switch (indexPath.section) {
        case 0:
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
                      message:NSLocalizedString(@"\nDO NOT let anyone see your backup phrase or they can spend your "
                                                "bitcoins.\n\nNEVER type your backup phrase into password managers or "
                                                "elsewhere. Other devices may be infected.\n", nil) delegate:self
                      cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                      otherButtonTitles:NSLocalizedString(@"show", nil), nil] show];
                    break;
            }
            
            break;
            
        case 1:
            switch (indexPath.row) {
                case 0: // local currency
                    self.selectorType = 0;
                    self.selectorOptions = [m.currencyCodes
                                            sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
                    self.selectedOption = m.localCurrencyCode;
                    self.selectorController.title = [NSString stringWithFormat:@"%@ = %@",
                                                     [m localCurrencyStringForAmount:SATOSHIS/m.localCurrencyPrice],
                                                     [m stringForAmount:SATOSHIS/m.localCurrencyPrice]];
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
                    
                case 1: // touch id spending limit
                    if (self.touchId) {
                        self.selectorType = 1;
                        self.selectorOptions =
                            @[NSLocalizedString(@"always require passcode", nil),
                              [NSString stringWithFormat:@"%@      (%@)", [m stringForAmount:10000000],
                               [m localCurrencyStringForAmount:10000000]],
                              [NSString stringWithFormat:@"%@   (%@)", [m stringForAmount:100000000],
                               [m localCurrencyStringForAmount:100000000]],
                              [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:1000000000],
                               [m localCurrencyStringForAmount:1000000000]]];
                        if (m.spendingLimit > 1000000000) m.spendingLimit = 1000000000;
                        self.selectedOption = self.selectorOptions[(log10(m.spendingLimit) < 6) ? 0 :
                                                                   (NSUInteger)log10(m.spendingLimit) - 6];
                        self.selectorController.title = NSLocalizedString(@"touch id spending limit", nil);
                        [self.navigationController pushViewController:self.selectorController animated:YES];
                        break;
                    }
                    // passthrough if ! self.touchId
                    
                case 2: // remove standard fees
                    break;
            }
            
            break;
            
        case 2:
            switch (indexPath.row) {
                case 0: // change passcode
                    [tableView deselectRowAtIndexPath:indexPath animated:YES];
                    [m performSelector:@selector(setPin) withObject:nil afterDelay:0.0];
                    break;

                case 1: // start/restore another wallet (handled by storyboard)
                    break;
            }
            
            break;
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        return;
    }
    
    BRSeedViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
    
    if (c.authSuccess) {
        [self.navigationController pushViewController:c animated:YES];
    }
    else [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
}

@end
