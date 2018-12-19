//
//  DWSettingsViewController.m
//  DashWallet
//
//  Created by Aaron Voisine for BreadWallet on 12/3/14.
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

#import "DWSettingsViewController.h"
#import "DWSeedViewController.h"
#import "BRUserDefaultsSwitchCell.h"
#import "DSCurrencyPriceObject.h"
#import "DWAboutViewController.h"

@interface DWSettingsViewController ()

@property (nonatomic, assign) BOOL touchId;
@property (nonatomic, assign) BOOL faceId;
@property (nonatomic, strong) UITableViewController *selectorController;
@property (nonatomic, strong) NSArray *selectorOptions;
@property (nonatomic, strong) NSString *selectedOption, *noOptionsText;
@property (nonatomic, assign) NSUInteger selectorType;
@property (nonatomic, strong) UISwipeGestureRecognizer *navBarSwipe;
@property (nonatomic, strong) id balanceObserver;

@end


@implementation DWSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.touchId = [DSAuthenticationManager sharedInstance].touchIdEnabled;
    self.faceId = [DSAuthenticationManager sharedInstance].faceIdEnabled;
}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (self.navBarSwipe) [self.navigationController.navigationBar removeGestureRecognizer:self.navBarSwipe];
    self.navBarSwipe = nil;
    
    // observe the balance change notification to update the balance display
    if (! self.balanceObserver) {
        self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:DSWalletBalanceDidChangeNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *note) {
                                                               if (self.selectorType == 0) {
                                                                   self.selectorController.title =
                                                                   [NSString stringWithFormat:@"1 DASH = %@",
                                                                    [[DSPriceManager sharedInstance] localCurrencyStringForDashAmount:DUFFS]];
                                                               }
                                                           }];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
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
    return _selectorController;
}

- (void)setBackgroundForCell:(UITableViewCell *)cell tableView:(UITableView *)tableView indexPath:(NSIndexPath *)path
{    
    [cell viewWithTag:100].hidden = (path.row > 0);
    [cell viewWithTag:101].hidden = (path.row + 1 < [self tableView:tableView numberOfRowsInSection:path.section]);
}

-(BOOL)enabledAdvancedFeatures {
    NSUserDefaults * userDefaults =[NSUserDefaults standardUserDefaults];
    if ([userDefaults objectForKey:ENABLED_ADVANCED_FEATURES]) {
        return [userDefaults boolForKey:ENABLED_ADVANCED_FEATURES];
    }
    return FALSE;
}

// MARK: - IBAction

- (IBAction)done:(id)sender
{
    [DSEventManager saveEvent:@"settings:dismiss"];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)touchIdLimit:(id)sender
{
    [DSEventManager saveEvent:@"settings:touch_id_limit"];
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSChainsManager * chainsManager = [DSChainsManager sharedInstance];
    
    [authenticationManager authenticateWithPrompt:nil andTouchId:NO alertIfLockout:YES completion:^(BOOL authenticated,BOOL cancelled) {
        if (authenticated) {
            self.selectorType = 1;
            self.selectorOptions =
            @[NSLocalizedString(@"always require passcode", nil),
              [NSString stringWithFormat:@"%@      (%@)", [priceManager stringForDashAmount:DUFFS/10],
               [priceManager localCurrencyStringForDashAmount:DUFFS/10]],
              [NSString stringWithFormat:@"%@   (%@)", [priceManager stringForDashAmount:DUFFS],
               [priceManager localCurrencyStringForDashAmount:DUFFS]],
              [NSString stringWithFormat:@"%@ (%@)", [priceManager stringForDashAmount:DUFFS*10],
               [priceManager localCurrencyStringForDashAmount:DUFFS*10]]];
            if (chainsManager.spendingLimit > DUFFS*10) [chainsManager setSpendingLimitIfAuthenticated:DUFFS*10];
            self.selectedOption = self.selectorOptions[(log10(chainsManager.spendingLimit) < 6) ? 0 :
                                                       (NSUInteger)log10(chainsManager.spendingLimit) - 6];
            self.noOptionsText = nil;
            self.selectorController.title = (self.touchId)?NSLocalizedString(@"Touch ID spending limit", nil):NSLocalizedString(@"Face ID spending limit", nil);
            [self.navigationController pushViewController:self.selectorController animated:YES];
            [self.selectorController.tableView reloadData];
        } else {
            [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:YES];
        }
    }];
}

- (IBAction)navBarSwipe:(id)sender
{
    [DSEventManager saveEvent:@"settings:nav_bar_swipe"];
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    NSUInteger digits = (((priceManager.dashFormat.maximumFractionDigits - 2)/3 + 1) % 3)*3 + 2;
    
    priceManager.dashFormat.currencySymbol = [NSString stringWithFormat:@"%@%@" NARROW_NBSP, (digits == 5) ? @"m" : @"",
                                              (digits == 2) ? DITS : DASH];
    priceManager.dashFormat.maximumFractionDigits = digits;
    priceManager.dashFormat.maximum = @(MAX_MONEY/(int64_t)pow(10.0, priceManager.dashFormat.maximumFractionDigits));
    [[NSUserDefaults standardUserDefaults] setInteger:digits forKey:SETTINGS_MAX_DIGITS_KEY];
    priceManager.localCurrencyCode = priceManager.localCurrencyCode; // force balance notification
    self.selectorController.title = [NSString stringWithFormat:@"1 DASH = %@", [priceManager localCurrencyStringForDashAmount:DUFFS]];
    [self.tableView reloadData];
}

-(void)showEnableAdvancedFeatures {
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Enable advanced features?", nil)
                                 message:NSLocalizedString(@"Only enable advanced features if you are knowledgeable in blockchain technology. \nIf enabled only use advanced features that you understand.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* cancelButton = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"cancel", nil)
                                   style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction * action) {
                                       
                                   }];
    UIAlertAction* yesButton = [UIAlertAction
                                actionWithTitle:NSLocalizedString(@"yes", nil)
                                style:UIAlertActionStyleDefault
                                handler:^(UIAlertAction * action) {
                                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:ENABLED_ADVANCED_FEATURES];
                                    [self.tableView reloadData];
                                }];
    [alert addAction:yesButton];
    [alert addAction:cancelButton];
    [self presentViewController:alert animated:YES completion:nil];
}

// MARK: - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView == self.selectorController.tableView) return 1;
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == self.selectorController.tableView) return self.selectorOptions.count;
    
    switch (section) {
        case 0: return 2 + ((self.touchId || self.faceId) ? 3 : 2);
        case 1: return 3;
        case 2: return 1;
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *disclosureIdent = @"DisclosureCell", *restoreIdent = @"RestoreCell", *actionIdent = @"ActionCell",
    *selectorIdent = @"SelectorCell", *selectorOptionCell = @"SelectorOptionCell";
    UITableViewCell *cell = nil;
    
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSChainsManager * chainsManager = [DSChainsManager sharedInstance];
    
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
                    cell.textLabel.text = NSLocalizedString(@"About", nil);
                    break;
                    
                case 1:
                    cell.textLabel.text = NSLocalizedString(@"Recovery phrase", nil);
                    break;
                case 2:
                    cell = [tableView dequeueReusableCellWithIdentifier:selectorIdent];
                    cell.detailTextLabel.text = priceManager.localCurrencyCode;
                    break;
                    
                case 3:
                    if (self.touchId || self.faceId) {
                        cell = [tableView dequeueReusableCellWithIdentifier:selectorIdent];
                        cell.textLabel.text = (self.touchId)?NSLocalizedString(@"Touch ID limit", nil):NSLocalizedString(@"Face ID limit", nil);
                        cell.detailTextLabel.text = [priceManager stringForDashAmount:chainsManager.spendingLimit];
                    } else {
                        goto _switch_cell;
                    }
                    break;
                case 4:
                {
                _switch_cell:
                    cell = [tableView dequeueReusableCellWithIdentifier:@"SwitchCell" forIndexPath:indexPath];
                    BRUserDefaultsSwitchCell *switchCell = (BRUserDefaultsSwitchCell *)cell;
                    switchCell.titleLabel.text = NSLocalizedString(@"Enable receive notifications", nil);
                    [switchCell setUserDefaultsKey:USER_DEFAULTS_LOCAL_NOTIFICATIONS_KEY];
                    break;
                }
            }
            
            break;
            
        case 1:
            switch (indexPath.row) {
                case 0:
                    cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
                    cell.textLabel.text = NSLocalizedString(@"Change passcode", nil);
                    break;
                    
                case 1:
                    cell = [tableView dequeueReusableCellWithIdentifier:restoreIdent];
                    break;
                    
                case 2:
                    cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
                    cell.textLabel.text = NSLocalizedString(@"Rescan blockchain", nil);
                    break;
                    
            }
            break;
        case 2:
            if (![self enabledAdvancedFeatures]) {
                cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
                cell.textLabel.text = NSLocalizedString(@"Enable advanced features", nil);
                break;
            } else {
                switch (indexPath.row) {
                    case 0:
                        cell = [tableView dequeueReusableCellWithIdentifier:selectorIdent];
                        cell.textLabel.text = NSLocalizedString(@"Network", nil);
                        cell.detailTextLabel.text = [DWEnvironment sharedInstance].currentChain.name;
                        break;
                        
                    default:
                        break;
                }
            }
    }
    
    [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
    NSParameterAssert(cell);
    return cell ?: [[UITableViewCell alloc] init];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (tableView == self.selectorController.tableView) {
        if (self.selectorOptions.count == 0) return self.noOptionsText;
        return nil;
    }
    
    switch (section) {
        case 0:
            return NSLocalizedString(@"GENERAL",nil);
            
        case 1:
            return NSLocalizedString(@"CRITICAL",nil);
            
        case 2:
            return NSLocalizedString(@"ADVANCED",nil);
            
        case 3:
            return NSLocalizedString(@"rescan blockchain if you think you may have missing transactions, "
                                     "or are having trouble sending (rescanning can take several minutes)", nil);
    }
    
    return nil;
}

// MARK: - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSString *sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
    
    if (sectionTitle.length == 0) return 22.0;
    
    CGRect textRect = [sectionTitle boundingRectWithSize:CGSizeMake(self.view.frame.size.width - 20.0, CGFLOAT_MAX)
                                                 options:NSStringDrawingUsesLineFragmentOrigin
                                              attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:14]} context:nil];
    
    return textRect.size.height + 22.0 + 10.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *sectionHeader = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                                     [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 10.0, sectionHeader.frame.size.width - 20.0,
                                                                    sectionHeader.frame.size.height - 12.0)];
    
    titleLabel.text = [self tableView:tableView titleForHeaderInSection:section];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    titleLabel.textColor = [UIColor grayColor];
    titleLabel.shadowColor = [UIColor whiteColor];
    titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    titleLabel.numberOfLines = 0;
    sectionHeader.backgroundColor = self.tableView.backgroundColor;
    [sectionHeader addSubview:titleLabel];
    
    return sectionHeader;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return (section + 1 == [self numberOfSectionsInTableView:tableView]) ? 22.0 : 0.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    UIView *sectionFooter = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                                     [self tableView:tableView heightForFooterInSection:section])];
    sectionFooter.backgroundColor = [UIColor clearColor];
    return sectionFooter;
}

- (void)showAbout
{
    [DSEventManager saveEvent:@"settings:show_about"];
    DWAboutViewController *aboutViewController = [DWAboutViewController controller];
    [self.navigationController pushViewController:aboutViewController animated:YES];
}

- (void)showRecoveryPhrase
{
    [DSEventManager saveEvent:@"settings:show_recovery_phrase"];
    
    DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
    
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"WARNING", nil)
                                 message:[NSString stringWithFormat:@"\n%@\n\n%@\n\n%@\n",
                                          [NSLocalizedString(@"DO NOT let anyone see your recovery phrase or they can spend your dash.", nil)
                                           stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]],
                                          [NSLocalizedString(@"NEVER type your recovery phrase into password managers or elsewhere. Other devices may be infected.", nil)
                                           stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]],
                                          [NSLocalizedString(@"DO NOT take a screenshot. Screenshots are visible to other apps and devices.", nil)
                                           stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]]
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* cancelButton = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"cancel", nil)
                                   style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction * action) {
                                       [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:YES];
                                   }];
    UIAlertAction* showButton = [UIAlertAction
                                 actionWithTitle:NSLocalizedString(@"show", nil)
                                 style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction * action) {
                                     [wallet seedPhraseAfterAuthentication:^(NSString * _Nullable seedPhrase) {
                                         if (seedPhrase.length > 0) {
                                             DWSeedViewController *seedController = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
                                             seedController.seedPhrase = seedPhrase;
                                             [self.navigationController pushViewController:seedController animated:YES];
                                         } else {
                                             [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:YES];
                                         }
                                     }];
                                 }];
    [alert addAction:showButton];
    [alert addAction:cancelButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCurrencySelector
{
    [DSEventManager saveEvent:@"settings:show_currency_selector"];
    
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    
    NSArray <NSString *> *options = [priceManager.prices valueForKeyPath:@"codeAndName"];
    DSCurrencyPriceObject *price = [priceManager priceForCurrencyCode:priceManager.localCurrencyCode];
    NSUInteger currencyCodeIndex = [priceManager.prices indexOfObject:price];
    
    self.selectorType = 0;
    
    self.selectorOptions = options;
    if (currencyCodeIndex < options.count) self.selectedOption = options[currencyCodeIndex];
    self.noOptionsText = NSLocalizedString(@"no exchange rate data", nil);
    self.selectorController.title =
    [NSString stringWithFormat:@"1 DASH = %@",
     [priceManager localCurrencyStringForDashAmount:DUFFS]];
    [self.navigationController pushViewController:self.selectorController animated:YES];
    [self.selectorController.tableView reloadData];
    
    if (currencyCodeIndex < options.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.selectorController.tableView
             scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:currencyCodeIndex inSection:0]
             atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
            
            if (! self.navBarSwipe) {
                self.navBarSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(navBarSwipe:)];
                self.navBarSwipe.direction = UISwipeGestureRecognizerDirectionLeft;
                [self.navigationController.navigationBar addGestureRecognizer:self.navBarSwipe];
            }
        });
    }
}

-(void)showChangeNetwork {
    [DSEventManager saveEvent:@"settings:show_change_network"];
    UIAlertController * actionSheet = [UIAlertController
                                       alertControllerWithTitle:NSLocalizedString(@"Network", nil)
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction* mainnet = [UIAlertAction
                              actionWithTitle:DSLocalizedString(@"Mainnet", nil)
                              style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction * action) {
                                  [[DWEnvironment sharedInstance] switchToMainnetWithCompletion:^(BOOL success) {
                                      if (success) {
                                          [self.tableView reloadData];
                                      }
                                  }];
                                  
                              }];
    UIAlertAction* testnet = [UIAlertAction
                              actionWithTitle:DSLocalizedString(@"Testnet", nil)
                              style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction * action) {
                                  [[DWEnvironment sharedInstance] switchToTestnetWithCompletion:^(BOOL success) {
                                      if (success) {
                                          [self.tableView reloadData];
                                      }
                                  }];
                              }];
    
    UIAlertAction* cancel = [UIAlertAction
                             actionWithTitle:NSLocalizedString(@"cancel", nil)
                             style:UIAlertActionStyleCancel
                             handler:^(UIAlertAction * action) {
                             }];
    [actionSheet addAction:mainnet];
    [actionSheet addAction:testnet];
    [actionSheet addAction:cancel];
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //TODO: include an option to generate a new wallet and sweep old balance if backup may have been compromized
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSChainManager * chainManager = [DWEnvironment sharedInstance].currentChainManager;
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    
    NSUInteger currencyCodeIndex = 0;
    
    // if we are showing the local currency selector
    if (tableView == self.selectorController.tableView) {
        currencyCodeIndex = [self.selectorOptions indexOfObject:self.selectedOption];
        if (indexPath.row < self.selectorOptions.count) self.selectedOption = self.selectorOptions[indexPath.row];
        
        if (self.selectorType == 0) {
            if (indexPath.row < priceManager.prices.count) {
                DSCurrencyPriceObject *selectedPrice = priceManager.prices[indexPath.row];
                priceManager.localCurrencyCode = selectedPrice.code;
            }
        }
        else [[DSChainsManager sharedInstance] setSpendingLimitIfAuthenticated:(indexPath.row > 0) ? pow(10, indexPath.row + 6) : 0];
        
        if (currencyCodeIndex < self.selectorOptions.count && currencyCodeIndex != indexPath.row) {
            [tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:currencyCodeIndex inSection:0], indexPath]
                             withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self.tableView reloadData];
        return;
    }
    
    switch (indexPath.section) {
        case 0:
            switch (indexPath.row) {
                case 0: // about
                    [self showAbout];
                    break;
                    
                case 1: // recovery phrase
                    [self showRecoveryPhrase];
                    break;
                case 2: // local currency
                    [self showCurrencySelector];
                    
                    break;
                    
                case 3: // Touch ID spending limit
                    if (self.touchId || self.faceId) {
                        [self performSelector:@selector(touchIdLimit:) withObject:nil afterDelay:0.0];
                        break;
                    } else {
                        goto _deselect_switch;
                    }
                    break;
                case 4:
                _deselect_switch:
                {
                    [tableView deselectRowAtIndexPath:indexPath animated:YES];
                }
                    break;
            }
            
            break;
            
        case 1:
            switch (indexPath.row) {
                case 0: // change passcode
                    [DSEventManager saveEvent:@"settings:change_pin"];
                    [tableView deselectRowAtIndexPath:indexPath animated:YES];
                    [authenticationManager performSelector:@selector(setPinWithCompletion:) withObject:nil afterDelay:0.0];
                    break;
                    
                case 1: // start/recover another wallet (handled by storyboard)
                    [DSEventManager saveEvent:@"settings:recover"];
                    break;
                    
                case 2: // rescan blockchain
                    [chainManager rescan];
                    [DSEventManager saveEvent:@"settings:rescan"];
                    [self done:nil];
                    break;
            }
            
            break;
        case 2:
            if (![self enabledAdvancedFeatures]) {
                [self showEnableAdvancedFeatures];
            } else {
                switch (indexPath.row) {
                    case 0: // change passcode
                        [self showChangeNetwork];
                        [tableView deselectRowAtIndexPath:indexPath animated:YES];
                        break;
                }
                break;
            }
            
    }
}

// MARK: - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
