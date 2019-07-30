//
//  DWRootViewController.m
//  DashWallet
//
//  Created by Aaron Voisine for BreadWallet on 9/15/13.
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

#import "DWRootViewController.h"
#import "DWReceiveViewController.h"
#import "DWSendViewController.h"
#import "DWTxHistoryViewController.h"
#import "DWRestoreViewController.h"
#import "DWSeedViewController.h"
#import "DWAppDelegate.h"
#import "BRBubbleView.h"
#import "BRBouncyBurgerButton.h"
#import "UIImage+Utils.h"
#import "BREventConfirmView.h"
#import "DWVersionManager.h"
#import "DWStoryboardSegueWithCompletion.h"

#import <WebKit/WebKit.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>

#define BALANCE_TIP_START NSLocalizedString(@"This is your dash balance.", nil)

#define BALANCE_TIP NSLocalizedString(@"This is your dash balance. Dash is a currency. "\
"The exchange rate changes with the market.", nil)
#define MDASH_TIP    NSLocalizedString(@"%@ is for 'mDASH'. %@ = 1 DASH.", nil)

#define BACKUP_DIALOG_TIME_KEY @"BACKUP_DIALOG_TIME"
#define BALANCE_KEY            @"BALANCE"

static double const SYNCING_COMPLETED_PROGRESS = 0.995;

@interface DWRootViewController ()

@property (nonatomic, strong) IBOutlet UIProgressView *progress, *pulse;
@property (nonatomic, strong) IBOutlet UIView *errorBar, *splash, *logo, *blur;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *lock;
@property (nonatomic, strong) IBOutlet BRBouncyBurgerButton *burger;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIGestureRecognizer *navBarTap;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, assign) BOOL shouldShowTips, showTips, inNextTip, didAppear;
@property (nonatomic, assign) uint64_t balance;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSData *file;
@property (nonatomic, strong) DSReachabilityManager *reachability;
@property (nonatomic, strong) id urlObserver, fileObserver, balanceObserver, seedObserver;
@property (nonatomic, strong) id reachabilityObserver, syncStartedObserver, syncFinishedObserver, syncFailedObserver;
@property (nonatomic, strong) id activeObserver, resignActiveObserver, foregroundObserver, backgroundObserver;
@property (nonatomic, assign) BOOL performedMigrationChecks;

@end

@implementation DWRootViewController

// MARK: - Controller values

-(BOOL)prefersStatusBarHidden {
    return NO;
}

// MARK: - View methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    
#if SNAPSHOT
    // initialized with random wallet
    [DSWallet standardWalletWithRandomSeedPhraseForChain:[DWEnvironment sharedInstance].currentChain storeSeedPhrase:YES isTransient:NO];
#endif /* SNAPSHOT */
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    // Do any additional setup after loading the view.
    
    self.performedMigrationChecks = FALSE;
    
    _balance = UINT64_MAX;
    
    self.receiveViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"ReceiveViewController"];
    self.sendViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"SendViewController"];
    self.pageViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"PageViewController"];
    
    self.pageViewController.dataSource = self;
    [self.pageViewController setViewControllers:@[self.sendViewController]
                                      direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    self.pageViewController.view.frame = self.view.bounds;
    [self addChildViewController:self.pageViewController];
    [self.view insertSubview:self.pageViewController.view atIndex:0];
    [self.pageViewController didMoveToParentViewController:self];
    
    self.shouldShowTips = TRUE;
    
    for (UIView *view in self.pageViewController.view.subviews) {
        if (! [view isKindOfClass:[UIScrollView class]]) continue;
        self.scrollView = (id)view;
        break;
    }
    
    if (!self.errorBar.superview) {
        [self.navigationController.navigationBar addSubview:self.errorBar];
        [self.navigationController.navigationBar addConstraint:[NSLayoutConstraint constraintWithItem:self.errorBar attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.navigationController.navigationBar attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0.0]];
        [self.navigationController.navigationBar addConstraint:[NSLayoutConstraint constraintWithItem:self.errorBar attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.navigationController.navigationBar attribute:NSLayoutAttributeRight multiplier:1.0 constant:0.0]];
        [self.navigationController.navigationBar addConstraint:[NSLayoutConstraint constraintWithItem:self.errorBar attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.navigationController.navigationBar attribute:NSLayoutAttributeBottom multiplier:1.0 constant:-48.0]];
    }
    
    self.reachability = [DSReachabilityManager sharedManager];
    if (!self.reachability.monitoring) {
        [self.reachability startMonitoring];
    }
    
    self.navigationController.delegate = self;
    
    if (![[DWEnvironment sharedInstance].currentChain isMainnet]) {
        UILabel *label = [UILabel new];
        
        label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightLight];
        label.textColor = [UIColor redColor];
        label.textAlignment = NSTextAlignmentRight;
        label.text = [[DWEnvironment sharedInstance].currentChain name];
        label.tag = 0xbeef;
        [label sizeToFit];
        label.center = CGPointMake(self.view.frame.size.width - label.frame.size.width,
                                   self.view.frame.size.height - (label.frame.size.height + 5));
        [self.view addSubview:label];
    }
    
    if ([DSEnvironment sharedInstance].watchOnly) { // watch only wallet
        UILabel *label = [UILabel new];
        
        label.font = [UIFont systemFontOfSize:14];
        label.textColor = [UIColor redColor];
        label.textAlignment = NSTextAlignmentRight;
        label.text = NSLocalizedString(@"watch only", nil);
        [label sizeToFit];
        label.center = CGPointMake(self.view.frame.size.width - label.frame.size.width,
                                   self.view.frame.size.height - (label.frame.size.height + 5)*2);
        [self.view addSubview:label];
    }
    
    // detect jailbreak so we can throw up an idiot warning, in viewDidLoad so it can't easily be swizzled out
    struct stat s;
    BOOL jailbroken = (stat("/bin/sh", &s) == 0) ? YES : NO; // if we can see /bin/sh, the app isn't sandboxed
    
    // some anti-jailbreak detection tools re-sandbox apps, so do a secondary check for any MobileSubstrate dyld images
    for (uint32_t count = _dyld_image_count(), i = 0; i < count && ! jailbroken; i++) {
        if (strstr(_dyld_get_image_name(i), "MobileSubstrate")) jailbroken = YES;
    }
    
#if TARGET_IPHONE_SIMULATOR
    jailbroken = NO;
#endif
    
    if ([[DWEnvironment sharedInstance].currentChain hasAWallet]) {
        self.splash.hidden = YES;
        self.navigationController.navigationBar.hidden = NO;
    }
    DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
    if (jailbroken && wallet.totalReceived + wallet.totalSent > 0) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"WARNING", nil)
                                     message:NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                                               "Any 'jailbreak' app can access any other app's keychain data "
                                                               "(and steal your dash). "
                                                               "Wipe this wallet immediately and restore on a secure device.", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* ignoreButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"ignore", nil)
                                       style:UIAlertActionStyleCancel
                                       handler:^(UIAlertAction * action) {
                                           
                                       }];
        UIAlertAction* wipeButton = [UIAlertAction
                                     actionWithTitle:NSLocalizedString(@"wipe", nil)
                                     style:UIAlertActionStyleDestructive
                                     handler:^(UIAlertAction * action) {
                                         DWRestoreViewController *restoreController =
                                         [self.storyboard instantiateViewControllerWithIdentifier:@"WipeViewController"];
                                         
                                         [self.navigationController pushViewController:restoreController animated:NO];
                                     }];
        
        [alert addAction:ignoreButton];
        [alert addAction:wipeButton];
        [self presentViewController:alert animated:YES completion:nil];
    }
    else if (jailbroken) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"WARNING", nil)
                                     message:NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                                               "Any 'jailbreak' app can access any other app's keychain data "
                                                               "(and steal your dash).", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* ignoreButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"ignore", nil)
                                       style:UIAlertActionStyleCancel
                                       handler:^(UIAlertAction * action) {
                                           
                                       }];
        UIAlertAction* closeButton = [UIAlertAction
                                      actionWithTitle:NSLocalizedString(@"close app", nil)
                                      style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction * action) {
                                          [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                                      }];
        
        [alert addAction:ignoreButton];
        [alert addAction:closeButton];
        [self presentViewController:alert animated:YES completion:nil];
    }
    
    
    [self setObserversWithDeviceIsJailbroken:jailbroken];
}

-(void)setObserversWithDeviceIsJailbroken:(BOOL)jailbroken {
#if SNAPSHOT
    // Disable syncing in snapshot-mode
    return;
#endif /* SNAPSHOT */
    
    self.urlObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:BRURLNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
                                                      NSURL *url = note.userInfo[@"url"];
                                                      if ([url.absoluteString containsString:@"uphold"]) {
                                                          return;
                                                      }
                                                      
                                                      if ([DWEnvironment sharedInstance].currentChain.hasAWallet) {
                                                          if (self.navigationController.topViewController != self) {
                                                              [self.navigationController popToRootViewControllerAnimated:YES];
                                                          }
                                                          
                                                          if (self.navigationController.presentedViewController) {
                                                              [self.navigationController dismissViewControllerAnimated:YES completion:nil];
                                                          }
                                                          
                                                          DWSendViewController *c = self.sendViewController;
                                                          
                                                          [self.pageViewController setViewControllers:(c ? @[c] : @[])
                                                                                            direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:^(BOOL finished) {
                                                                                                self->_url = url;
                                                                                                
                                                                                                if (self.didAppear && [UIApplication sharedApplication].protectedDataAvailable) {
                                                                                                    self->_url = nil;
                                                                                                    [c performSelector:@selector(handleURL:) withObject:url afterDelay:0.0];
                                                                                                }
                                                                                            }];
                                                          
                                                      }
                                                  }];
    
    self.fileObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:BRFileNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
                                                      if ([DWEnvironment sharedInstance].currentChain.hasAWallet) {
                                                          if (self.navigationController.topViewController != self) {
                                                              [self.navigationController popToRootViewControllerAnimated:YES];
                                                          }
                                                          
                                                          if (self.navigationController.presentedViewController) {
                                                              [self.navigationController dismissViewControllerAnimated:YES completion:nil];
                                                          }
                                                          
                                                          DWSendViewController *sendController = self.sendViewController;
                                                          
                                                          [self.pageViewController setViewControllers:(sendController ? @[sendController] : @[])
                                                                                            direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:^(BOOL finished) {
                                                                                                self->_file = note.userInfo[@"file"];
                                                                                                
                                                                                                if (self.didAppear && [UIApplication sharedApplication].protectedDataAvailable) {
                                                                                                    self->_file = nil;
                                                                                                    [sendController handleFile:note.userInfo[@"file"]];
                                                                                                }
                                                                                            }];
                                                      }
                                                  }];
    
    self.foregroundObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           if ([DWEnvironment sharedInstance].currentChain.hasAWallet) {
                                                               DSEventManager *eventMan = [DSEventManager sharedEventManager];
                                                               DSChainManager * chainManager = [DWEnvironment sharedInstance].currentChainManager;
                                                               
                                                               [chainManager.peerManager connect];
                                                               [self.sendViewController updateClipboardText];
                                                               
                                                               if (eventMan.isInSampleGroup && ! eventMan.hasAskedForPermission) {
                                                                   [eventMan acquireUserPermissionInViewController:self.navigationController withCallback:nil];
                                                               }
                                                               else {
                                                                   NSString *userDefaultsKey = @"has_asked_for_push";
                                                                   [[NSUserDefaults standardUserDefaults] setBool:TRUE forKey:userDefaultsKey];
                                                                   ([(id)[UIApplication sharedApplication].delegate registerForPushNotifications]);
                                                               }
                                                           }
                                                           DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
                                                           if (jailbroken && wallet.totalReceived > 0) {
                                                               UIAlertController * alert = [UIAlertController
                                                                                            alertControllerWithTitle:NSLocalizedString(@"WARNING", nil)
                                                                                            message:NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                                                                                                      "Any 'jailbreak' app can access any other app's keychain data "
                                                                                                                      "(and steal your dash). "
                                                                                                                      "Wipe this wallet immediately and restore on a secure device.", nil)
                                                                                            preferredStyle:UIAlertControllerStyleAlert];
                                                               UIAlertAction* ignoreButton = [UIAlertAction
                                                                                              actionWithTitle:NSLocalizedString(@"ignore", nil)
                                                                                              style:UIAlertActionStyleCancel
                                                                                              handler:^(UIAlertAction * action) {
                                                                                                  
                                                                                              }];
                                                               UIAlertAction* wipeButton = [UIAlertAction
                                                                                            actionWithTitle:NSLocalizedString(@"wipe", nil)
                                                                                            style:UIAlertActionStyleDestructive
                                                                                            handler:^(UIAlertAction * action) {
                                                                                                DWRestoreViewController *restoreController =
                                                                                                [self.storyboard instantiateViewControllerWithIdentifier:@"WipeViewController"];
                                                                                                
                                                                                                [self.navigationController pushViewController:restoreController animated:NO];
                                                                                            }];
                                                               
                                                               [alert addAction:ignoreButton];
                                                               [alert addAction:wipeButton];
                                                               [self presentViewController:alert animated:YES completion:nil];
                                                           }
                                                           else if (jailbroken) {
                                                               UIAlertController * alert = [UIAlertController
                                                                                            alertControllerWithTitle:NSLocalizedString(@"WARNING", nil)
                                                                                            message:NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                                                                                                      "Any 'jailbreak' app can access any other app's keychain data "
                                                                                                                      "(and steal your dash).", nil)
                                                                                            preferredStyle:UIAlertControllerStyleAlert];
                                                               UIAlertAction* ignoreButton = [UIAlertAction
                                                                                              actionWithTitle:NSLocalizedString(@"ignore", nil)
                                                                                              style:UIAlertActionStyleCancel
                                                                                              handler:^(UIAlertAction * action) {
                                                                                                  
                                                                                              }];
                                                               UIAlertAction* closeButton = [UIAlertAction
                                                                                             actionWithTitle:NSLocalizedString(@"close app", nil)
                                                                                             style:UIAlertActionStyleDefault
                                                                                             handler:^(UIAlertAction * action) {
                                                                                                 [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                                                                                             }];
                                                               
                                                               [alert addAction:ignoreButton];
                                                               [alert addAction:closeButton];
                                                               [self presentViewController:alert animated:YES completion:nil];
                                                           }
                                                       }];
    
    self.backgroundObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           if ([DWEnvironment sharedInstance].currentChain.hasAWallet) { // lockdown the app
                                                               self.navigationItem.titleView = self.logo;
                                                               self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"burger"];
                                                               self.navigationItem.rightBarButtonItem = self.lock;
                                                               self.pageViewController.view.alpha = 1.0;
                                                               [UIApplication sharedApplication].applicationIconBadgeNumber = 0; // reset app badge number
                                                           }
                                                       }];
    
    self.activeObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           [self.blur removeFromSuperview];
                                                           self.blur = nil;
                                                       }];
    
    self.resignActiveObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           UIView *keyWindow = [UIApplication sharedApplication].keyWindow;
                                                           UIImage *img;
                                                           
                                                           if (! [keyWindow viewWithTag:-411]) { // only take a screenshot if no views are marked highly sensitive
                                                               UIGraphicsBeginImageContext([UIScreen mainScreen].bounds.size);
                                                               [keyWindow drawViewHierarchyInRect:[UIScreen mainScreen].bounds afterScreenUpdates:NO];
                                                               img = UIGraphicsGetImageFromCurrentImageContext();
                                                               UIGraphicsEndImageContext();
                                                           }
                                                           else img = [UIImage imageNamed:@"wallpaper-default"];
                                                           
                                                           [self.blur removeFromSuperview];
                                                           self.blur = [[UIImageView alloc] initWithImage:[img dw_blurWithRadius:3]];
                                                           [keyWindow.subviews.lastObject addSubview:self.blur];
                                                       }];
    
    self.reachabilityObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:DSReachabilityDidChangeNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
                                                      
                                                      if ([DWEnvironment sharedInstance].currentChain.hasAWallet && self.reachability.networkReachabilityStatus != DSReachabilityStatusNotReachable &&
                                                          [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
                                                          [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
                                                      }
                                                      else if ([DWEnvironment sharedInstance].currentChain.hasAWallet && self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) {
                                                          [self showErrorBar];
                                                      }
                                                  }];
    
    self.balanceObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:DSWalletBalanceDidChangeNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
                                                      double progress = [DWEnvironment sharedInstance].currentChainManager.syncProgress;
                                                      
                                                      if (self->_balance != UINT64_MAX && progress > DBL_EPSILON && progress + DBL_EPSILON < 1.0) { // wait for sync
                                                          self.balance = self->_balance; // this updates the local currency value with the latest exchange rate
                                                          return;
                                                      }
                                                      
                                                      [self showBackupDialogIfNeeded];
                                                      [self.receiveViewController updateAddress];
                                                      self.balance = [DWEnvironment sharedInstance].currentWallet.balance;
                                                  }];
    
    self.seedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:DSChainWalletsDidChangeNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           NSDictionary * userInfo = note.userInfo;
                                                           DSChain * chain = [DWEnvironment sharedInstance].currentChain;
                                                           if ([userInfo objectForKey:DSChainManagerNotificationChainKey] && [userInfo objectForKey:DSChainManagerNotificationChainKey] == chain) {
                                                               [self.receiveViewController updateAddress];
                                                               self.balance = [DWEnvironment sharedInstance].currentWallet.balance;
                                                               if (chain.wallets.count == 0) { //a wallet was deleted, we need to go back to wallet nav
                                                                   [self showNewWalletController];
                                                               }
                                                           }
                                                       }];
    
    self.syncStartedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:DSTransactionManagerSyncStartedNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           if (self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) return;
                                                           [self hideErrorBarWithCompletion:nil];
                                                           [self startSyncingActivity];
                                                       }];
    
    self.syncFinishedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:DSTransactionManagerSyncFinishedNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           [self stopSyncingActivity];
                                                           if (! self.shouldShowTips) [self hideTips];
                                                           self.shouldShowTips = YES;
                                                           if (![DSAuthenticationManager sharedInstance].didAuthenticate) self.navigationItem.titleView = self.logo;
                                                           [self.receiveViewController updateAddress];
                                                           self.balance = [DWEnvironment sharedInstance].currentWallet.balance;
                                                       }];
    
    self.syncFailedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:DSTransactionManagerSyncFailedNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           [self stopSyncingActivity];
                                                           [self.receiveViewController updateAddress];
                                                           [self showErrorBar];
                                                       }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"burger"];
    self.pageViewController.view.alpha = 1.0;
    if ([DSAuthenticationManager sharedInstance].didAuthenticate) [self unlock:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    self.didAppear = YES;
    
    if (! self.navBarTap) {
        self.navBarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(navBarTap:)];
        self.navBarTap.delegate = self;
        [self.navigationController.navigationBar addGestureRecognizer:self.navBarTap];
    }
    
    [super viewDidAppear:animated];
}

- (void)protectedViewDidAppear
{
    [super protectedViewDidAppear];
    
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    DSVersionManager * dashSyncVersionManager = [DSVersionManager sharedInstance];
    DWVersionManager * dashwalletVersionManager = [DWVersionManager sharedInstance];
    DSChain * chain = [DWEnvironment sharedInstance].currentChain;
    
    //todo improve this to a better architecture
    if ([defs integerForKey:SETTINGS_MAX_DIGITS_KEY] == 5) {
        priceManager.dashFormat.currencySymbol = @"m" BTC NARROW_NBSP;
        priceManager.dashFormat.maximumFractionDigits = 5;
        priceManager.dashFormat.maximum = @((MAX_MONEY/DUFFS)*1000);
    }
    else if ([defs integerForKey:SETTINGS_MAX_DIGITS_KEY] == 8) {
        priceManager.dashFormat.currencySymbol = BTC NARROW_NBSP;
        priceManager.dashFormat.maximumFractionDigits = 8;
        priceManager.dashFormat.maximum = @(MAX_MONEY/DUFFS);
    }
    
#if SNAPSHOT
    // Don't set passcode
    return;
#endif /* SNAPSHOT */
    
    //todo : this should be implemented in DashSync, not here
    if (!chain.hasAWallet && [dashSyncVersionManager noOldWallet]) {
        if (!authenticationManager.passcodeEnabled) {
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:NSLocalizedString(@"turn device passcode on", nil)
                                         message:NSLocalizedString(@"\nA device passcode is needed to safeguard your wallet. Go to settings and "
                                                                   "turn passcode on to continue.", nil)
                                         preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* closeButton = [UIAlertAction
                                          actionWithTitle:NSLocalizedString(@"close app", nil)
                                          style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction * action) {
                                              [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                                          }];
            [alert addAction:closeButton];
            [self presentViewController:alert animated:YES completion:nil];
        }
        else {
            [self.navigationController
             presentViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"] animated:NO
             completion:^{
                 self.splash.hidden = YES;
                 self.navigationController.navigationBar.hidden = NO;
                 [self.pageViewController setViewControllers:@[self.receiveViewController]
                                                   direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
             }];
            self.showTips = YES;
        }
    }
    else {
        DSWallet *wallet = [[DWEnvironment sharedInstance] currentWallet];
        [dashSyncVersionManager upgradeVersion1ExtendedKeysForWallet:wallet chain:[DWEnvironment sharedInstance].currentChain withMessage:NSLocalizedString(@"please enter pin to upgrade wallet", nil) withCompletion:^(BOOL success, BOOL neededUpgrade, BOOL authenticated, BOOL cancelled) {
            if (!success && neededUpgrade && !authenticated) {
                [self forceUpdateWalletAuthentication:cancelled];
            } else {
                NSArray * wallets = [DWEnvironment sharedInstance].allWallets;
                [dashSyncVersionManager upgradeExtendedKeysForWallets:wallets withMessage:NSLocalizedString(@"please enter pin to upgrade wallet", nil) withCompletion:^(BOOL success, BOOL neededUpgrade, BOOL authenticated, BOOL cancelled) {
                    if (!success && neededUpgrade && !authenticated) {
                        [self forceUpdateWalletAuthentication:cancelled];
                    } else {
                        [dashwalletVersionManager checkPassphraseWasShownCorrectlyForWallet:[wallets firstObject] withCompletion:^(BOOL needsCheck, BOOL authenticated, BOOL cancelled, NSString * _Nullable seedPhrase) {
                            if (needsCheck && !authenticated) {
                                [self forceUpdateWalletAuthentication:cancelled];
                            }
                            
                            if (needsCheck) {
                                UIAlertController * alert = [UIAlertController
                                                             alertControllerWithTitle:NSLocalizedString(@"Action Needed", nil)
                                                             message:NSLocalizedString(@"In a previous version of Dashwallet, when initially displaying your passphrase on this device we have determined that this App did not correctly display all 12 seed words. Please write down your full passphrase again.", nil)
                                                             preferredStyle:UIAlertControllerStyleAlert];
                                UIAlertAction* showButton = [UIAlertAction
                                                             actionWithTitle:NSLocalizedString(@"show", nil)
                                                             style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction * action) {
                                                                 DWSeedViewController *seedController = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
                                                                 seedController.seedPhrase = seedPhrase;
                                                                 [self.navigationController pushViewController:seedController animated:YES];
                                                             }];
                                UIAlertAction* ignoreButton = [UIAlertAction
                                                               actionWithTitle:NSLocalizedString(@"ignore", nil)
                                                               style:UIAlertActionStyleCancel
                                                               handler:^(UIAlertAction * action) {
                                                                   
                                                               }];
                                
                                [alert addAction:ignoreButton];
                                [alert addAction:showButton]; //ok button should be on the right side as per Apple guidelines, as reset is the less desireable option
                                [alert setPreferredAction:showButton];
                                [self presentViewController:alert animated:YES completion:nil];
                            } else {
                                [self setInitialPin];
                            }
                            
                            if (self->_balance == UINT64_MAX && [defs objectForKey:BALANCE_KEY]) self.balance = [defs doubleForKey:BALANCE_KEY];
                            self.splash.hidden = YES;
                            
                            self.navigationController.navigationBar.hidden = NO;
                            self.pageViewController.view.alpha = 1.0;
                            self.performedMigrationChecks = TRUE;
                            [self showBackupDialogIfNeeded];
                            [self.receiveViewController updateAddress];
                            if (self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) [self showErrorBar];
                            
                            if (self.navigationController.visibleViewController == self) {
                                [self setNeedsStatusBarAppearanceUpdate];
                            }
                            
                            if (!authenticated) {
                                if ([defs doubleForKey:PIN_UNLOCK_TIME_KEY] + WEEK_TIME_INTERVAL < [NSDate timeIntervalSince1970]) {
                                    [authenticationManager authenticateWithPrompt:nil andTouchId:NO alertIfLockout:YES completion:^(BOOL authenticated,BOOL cancelled) {
                                        if (authenticated) {
                                            [self unlock:nil];
                                        }
                                    }];
                                }
                            }
                            
                            if (self.navigationController.visibleViewController == self) {
                                if (self.showTips) [self performSelector:@selector(tip:) withObject:nil afterDelay:0.3];
                            }
                            
                            if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
                                [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
                                [UIApplication sharedApplication].applicationIconBadgeNumber = 0; // reset app badge number
                                
                                if (self.url) {
                                    [self.sendViewController handleURL:self.url];
                                    self.url = nil;
                                }
                                else if (self.file) {
                                    [self.sendViewController handleFile:self.file];
                                    self.file = nil;
                                }
                            }
                        }];
                    }
                }];
            }
        }];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.navBarTap) [self.navigationController.navigationBar removeGestureRecognizer:self.navBarTap];
    self.navBarTap = nil;
    [self hideTips];
    
    [super viewWillDisappear:animated];
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
    if ([self nextTip]) return NO;
    
    return YES;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    [super prepareForSegue:segue sender:sender];
    
    (segue.destinationViewController).transitioningDelegate = self;
    (segue.destinationViewController).modalPresentationStyle = UIModalPresentationCustom;
    [self hideErrorBarWithCompletion:nil];
    
    if ([sender isEqual:NSLocalizedString(@"show phrase", nil)]) { // show recovery phrase
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
                                       }];
        UIAlertAction* showButton = [UIAlertAction
                                     actionWithTitle:NSLocalizedString(@"show", nil)
                                     style:UIAlertActionStyleDefault
                                     handler:^(UIAlertAction * action) {
                                         if (![DWEnvironment sharedInstance].currentChain.hasAWallet) {
                                             DWSeedViewController *seedController = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
                                             [self.navigationController pushViewController:seedController animated:YES];
                                         } else {
                                             DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
                                             [wallet seedPhraseAfterAuthentication:^(NSString * _Nullable seedPhrase) {
                                                 if (seedPhrase.length > 0) {
                                                     DWSeedViewController *seedController = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
                                                     seedController.seedPhrase = seedPhrase;
                                                     [self.navigationController pushViewController:seedController animated:YES];
                                                 }
                                             }];
                                         }
                                     }];
        [alert addAction:showButton];
        [alert addAction:cancelButton];
        [self presentViewController:alert animated:YES completion:nil];
    }
    //    else if ([sender isEqual:@"buy alert"]) {
    //        UINavigationController *nav = segue.destinationViewController;
    //
    //        [nav.topViewController performSelector:@selector(showBuy) withObject:nil afterDelay:1.0];
    //    }
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.urlObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    if (self.fileObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.fileObserver];
    if (self.foregroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.foregroundObserver];
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    if (self.activeObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];
    if (self.resignActiveObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];
    if (self.reachabilityObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.seedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.seedObserver];
    if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
}

- (void)setBalance:(uint64_t)balance
{
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    
    if (balance > _balance && [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        [self.view addSubview:[[[BRBubbleView viewWithText:[NSString
                                                            stringWithFormat:NSLocalizedString(@"received %@ (%@)", nil), [priceManager stringForDashAmount:balance - _balance],
                                                            [priceManager localCurrencyStringForDashAmount:balance - _balance]]
                                                    center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                               popOutAfterDelay:3.0]];
        [[DWEnvironment sharedInstance] playPingSound];
    }
    
    _balance = balance;
    
    // use setDouble since setInteger won't hold a uint64_t
    [[NSUserDefaults standardUserDefaults] setDouble:balance forKey:BALANCE_KEY];
    
    if (self.shouldShowTips && self.navigationItem.titleView && [self.navigationItem.titleView isKindOfClass:[UILabel class]]) {
        [self updateTitleViewBalance];
    }
}

-(UILabel*)titleLabel {
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
    UILabel * titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 1, 200)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleLabel setBackgroundColor:[UIColor clearColor]];
    NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:wallet.balance withTintColor:[UIColor whiteColor] useSignificantDigits:TRUE] mutableCopy];
    NSString * titleString = [NSString stringWithFormat:@" (%@)",
                              [priceManager localCurrencyStringForDashAmount:wallet.balance]];
    [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
    titleLabel.attributedText = attributedDashString;
    return titleLabel;
}

-(void)updateTitleViewBalance {
    if (self.navigationItem.titleView && [self.navigationItem.titleView isKindOfClass:[UILabel class]]) {
        DSPriceManager * priceManager = [DSPriceManager sharedInstance];
        DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
        NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:wallet.balance withTintColor:[UIColor whiteColor] useSignificantDigits:TRUE] mutableCopy];
        NSString * titleString = [NSString stringWithFormat:@" (%@)",
                                  [priceManager localCurrencyStringForDashAmount:wallet.balance]];
        [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
        ((UILabel*)self.navigationItem.titleView).attributedText = attributedDashString;
        [((UILabel*)self.navigationItem.titleView) sizeToFit];
    } else {
        self.navigationItem.titleView = [self titleLabel];
    }
}

- (void)startSyncingActivity
{
    self.shouldShowTips = NO;
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    self.progress.hidden = self.pulse.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{ self.progress.alpha = 1.0; }];
    [self updateProgress];
}

- (void)stopSyncingActivity
{
    double progress = [DWEnvironment sharedInstance].currentChainManager.syncProgress;
    
    if (progress > DBL_EPSILON && progress + DBL_EPSILON < 1.0) return; // not done syncing
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateProgress) object:nil];
    if (!self.shouldShowTips) {
        [self hideTips];
    }
    self.shouldShowTips = YES;
    
    [self updateNavigationBarTitle];
    
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    [self.progress setProgress:1.0 animated:YES];
    [self.pulse setProgress:1.0 animated:YES];
    
    [UIView animateWithDuration:0.2 animations:^{
        self.progress.alpha = self.pulse.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.progress.hidden = self.pulse.hidden = YES;
        self.progress.progress = self.pulse.progress = 0.0;
    }];
}

- (void)setProgressTo:(NSNumber *)n
{
    self.progress.progress = n.floatValue;
}

- (void)updateProgress
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateProgress) object:nil];
    
    double progress = [DWEnvironment sharedInstance].currentChainManager.syncProgress;
    
    if (progress > DBL_EPSILON && ! self.shouldShowTips && self.tipView.alpha > 0.5) {
        DSChain *chain = [DWEnvironment sharedInstance].currentChainManager.chain;
        self.tipView.text = [NSString stringWithFormat:NSLocalizedString(@"block #%d of %d", nil),
                             chain.lastBlockHeight,
                             chain.estimatedBlockHeight];
    }
    
    if (progress < SYNCING_COMPLETED_PROGRESS) {
        self.progress.hidden = self.pulse.hidden = NO;
        self.progress.alpha = 1.0;
        
        static int counter = 0;
        
        if ((counter % 13) == 0) {
            self.pulse.alpha = 1.0;
            [self.pulse setProgress:progress animated:progress > self.pulse.progress];
            [self.progress setProgress:progress animated:progress > self.progress.progress];
            
            if (progress > self.progress.progress) {
                [self performSelector:@selector(setProgressTo:) withObject:@(progress) afterDelay:1.0];
            }
            else self.progress.progress = progress;
            
            [UIView animateWithDuration:1.59 delay:1.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
                self.pulse.alpha = 0.0;
            } completion:nil];
            
            [self.pulse performSelector:@selector(setProgress:) withObject:nil afterDelay:2.59];
        }
        else if ((counter % 13) >= 5) {
            [self.progress setProgress:progress animated:progress > self.progress.progress];
            [self.pulse setProgress:progress animated:progress > self.pulse.progress];
        }
        
        counter++;
    }
    else {
        self.progress.alpha = 0.0;
        self.pulse.alpha = 0.0;
    }
    
    [self updateNavigationBarTitle];
    
    [self performSelector:@selector(updateProgress) withObject:nil afterDelay:0.2];
}

- (void)updateNavigationBarTitle
{
    double progress = [DWEnvironment sharedInstance].currentChainManager.syncProgress;
    
    if (progress < SYNCING_COMPLETED_PROGRESS) {
        self.navigationItem.titleView = nil;
        self.navigationItem.title = [NSString stringWithFormat:@"%@ %0.1f%%", NSLocalizedString(@"Syncing:", nil), progress * 100.0];
    }
    else {
        if (![DSAuthenticationManager sharedInstance].didAuthenticate) {
            self.navigationItem.titleView = self.logo;
        }
        else {
            self.navigationItem.titleView = nil;
            [self updateTitleViewBalance];
        }
    }
}

- (void)showErrorBar
{
    if (self.navigationItem.prompt != nil || self.navigationController.presentedViewController != nil) return;
    self.navigationItem.prompt = @"";
    self.errorBar.hidden = NO;
    self.errorBar.alpha = 0.0;
    
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn animations:^{
                            self.burger.center = CGPointMake(self.burger.center.x, 70.0);
                            self.errorBar.alpha = 1.0;
                        } completion:nil];
    
    if (! self.shouldShowTips) [self hideTips];
    self.shouldShowTips = YES;
    if (![DSAuthenticationManager sharedInstance]) self.navigationItem.titleView = self.logo;
    self.balance = _balance; // reset navbar title
    self.progress.hidden = self.pulse.hidden = YES;
}

- (void)hideErrorBarWithCompletion:(void (^ _Nullable)(BOOL finished))completion
{
    if (self.navigationItem.prompt == nil) return;
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
                            self.burger.center = CGPointMake(self.burger.center.x, 40.0);
                            self.errorBar.alpha = 0.0;
                        } completion:^(BOOL finished) {
                            self.navigationItem.prompt = nil;
                            self.errorBar.hidden = YES;
                            if (completion) completion(finished);
                        }];
}

- (void)showBackupDialogIfNeeded
{
    if (!self.performedMigrationChecks) return;
    DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSTimeInterval now = [NSDate timeIntervalSince1970];
    
    if (self.navigationController.visibleViewController != self || ! [defs boolForKey:WALLET_NEEDS_BACKUP_KEY] ||
        wallet.balance == 0 || [defs doubleForKey:BACKUP_DIALOG_TIME_KEY] > now - 1.5*DAY_TIME_INTERVAL) return;
    
    BOOL first = ([defs doubleForKey:BACKUP_DIALOG_TIME_KEY] < 1.0) ? YES : NO;
    
    [defs setDouble:now forKey:BACKUP_DIALOG_TIME_KEY];
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:(first) ? NSLocalizedString(@"you received dash!", nil) : NSLocalizedString(@"IMPORTANT", nil)
                                 message:[NSString stringWithFormat:NSLocalizedString(@"\n%@\n\nif you ever lose your phone, you will need it to "
                                                                                      "recover your wallet", nil),
                                          (first) ? NSLocalizedString(@"next, write down your recovery phrase", nil) :
                                          NSLocalizedString(@"WRITE DOWN YOUR RECOVERY PHRASE", nil)]
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* doItLaterButton = [UIAlertAction
                                      actionWithTitle:NSLocalizedString(@"do it later", nil)
                                      style:UIAlertActionStyleCancel
                                      handler:^(UIAlertAction * action) {
                                          
                                      }];
    UIAlertAction* showPhraseButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"show phrase", nil)
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction * action) {
                                           DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
                                           [wallet seedPhraseAfterAuthentication:^(NSString * _Nullable seedPhrase) {
                                               if (seedPhrase.length > 0) {
                                                   DWSeedViewController *seedController = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
                                                   seedController.seedPhrase = seedPhrase;
                                                   [self.navigationController pushViewController:seedController animated:YES];
                                               }
                                           }];
                                       }];
    
    [alert addAction:doItLaterButton];
    [alert addAction:showPhraseButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)hideTips
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(tip:) object:nil];
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

- (BOOL)nextTip
{
    if (self.tipView.alpha < 0.5) { // if the tip view is dismissed, cycle through child view controller tips
        BOOL ret;
        
        if (self.inNextTip) return NO; // break out of recursive loop
        self.inNextTip = YES;
        ret = [self.pageViewController.viewControllers.lastObject nextTip];
        self.inNextTip = NO;
        return ret;
    }
    
    BRBubbleView *tipView = self.tipView;
    
    self.tipView = nil;
    [tipView popOut];
    
    if ([tipView.text hasPrefix:BALANCE_TIP]) {
        DSPriceManager * priceManager = [DSPriceManager sharedInstance];
        UINavigationBar *b = self.navigationController.navigationBar;
        NSString *text = [NSString stringWithFormat:MDASH_TIP, priceManager.dashFormat.currencySymbol, [priceManager stringForDashAmount:DUFFS]];
        CGRect r = [self.navigationItem.title boundingRectWithSize:b.bounds.size options:0
                                                        attributes:b.titleTextAttributes context:nil];
        
        self.tipView = [BRBubbleView viewWithAttributedText:[text attributedStringForDashSymbolWithTintColor:[UIColor whiteColor] dashSymbolSize:CGSizeMake(13, 11)]
                                                   tipPoint:CGPointMake(b.center.x + 5.0 - r.size.width/2.0,
                                                                        b.frame.origin.y + b.frame.size.height - 10)
                                               tipDirection:BRBubbleTipDirectionUp];
        self.tipView.backgroundColor = tipView.backgroundColor;
        self.tipView.font = tipView.font;
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips) {
        self.showTips = NO;
        [self.pageViewController.viewControllers.lastObject tip:self];
    }
    
    return YES;
}

// MARK: - Segues
-(void)setInitialPin {
    [[DSAuthenticationManager sharedInstance] setPinIfNeededWithCompletion:^(BOOL needed, BOOL success) {
        if (needed && !success) [self setInitialPin]; //try again
    }];
}

// MARK: - IBAction

- (IBAction)tip:(id)sender
{
    DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSChain * chain = [DWEnvironment sharedInstance].currentChain;
    
    if (sender == self.receiveViewController) {
        DWSendViewController *sendController = self.sendViewController;
        
        [(id)self.pageViewController setViewControllers:@[sendController]
                                              direction:UIPageViewControllerNavigationDirectionReverse animated:YES
                                             completion:^(BOOL finished) { [sendController tip:sender]; }];
    }
    else if (sender == self.sendViewController) {
        self.scrollView.scrollEnabled = YES;
        [(id)self.pageViewController setViewControllers:@[self.receiveViewController]
                                              direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:nil];
    }
    else if (self.showTips && wallet.walletCreationTime + DAY_TIME_INTERVAL < [NSDate timeIntervalSince1970]) {
        self.showTips = NO;
    }
    else {
        UINavigationBar *b = self.navigationController.navigationBar;
        NSString *tip;
        if (priceManager.localCurrencyDashPrice) {
            tip = (self.shouldShowTips) ? [NSString stringWithFormat:@"%@ \n 1%@ = %@",BALANCE_TIP_START,DASH,[priceManager localCurrencyStringForDashAmount:DUFFS]] :
            [NSString stringWithFormat:NSLocalizedString(@"block #%d of %d", nil),
             [chain lastBlockHeight],
             [chain estimatedBlockHeight]];
        } else {
            tip = (self.shouldShowTips) ? [NSString stringWithFormat:@"%@",BALANCE_TIP]:
            [NSString stringWithFormat:NSLocalizedString(@"block #%d of %d", nil),
             [chain lastBlockHeight],
             [chain estimatedBlockHeight]];
        }
        NSMutableAttributedString *attributedTip = [[NSMutableAttributedString alloc]
                                                    initWithString:[tip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        
        NSRange range = [attributedTip.string rangeOfString:DASH options:NSBackwardsSearch];
        if (range.length != 0)
            [attributedTip replaceCharactersInRange:range
                               withAttributedString:[NSString dashSymbolAttributedStringWithTintColor:[UIColor whiteColor] forDashSymbolSize:CGSizeMake(13, 11)]];
        self.tipView = [BRBubbleView viewWithAttributedText:attributedTip
                                                   tipPoint:CGPointMake(b.center.x, b.frame.origin.y + b.frame.size.height - 10)
                                               tipDirection:BRBubbleTipDirectionUp];
        self.tipView.font = [UIFont systemFontOfSize:14.0];
        self.tipView.userInteractionEnabled = NO;
        UIWindow *currentWindow = [UIApplication sharedApplication].keyWindow;
        [currentWindow addSubview:[self.tipView popIn]];
        if (self.showTips) self.scrollView.scrollEnabled = NO;
    }
}

- (IBAction)unlock:(id)sender
{
    if ([DSAuthenticationManager sharedInstance].didAuthenticate) {
        [self updateTitleViewBalance];
        [self.navigationItem setRightBarButtonItem:nil animated:(sender) ? YES : NO];
    } else {
        [DSEventManager saveEvent:@"root:unlock"];
        [[DSAuthenticationManager sharedInstance] authenticateWithPrompt:nil andTouchId:YES alertIfLockout:YES completion:^(BOOL authenticated,BOOL cancelled) {
            if (authenticated) {
                [DSEventManager saveEvent:@"root:unlock_success"];
                [self updateTitleViewBalance];
                [self.navigationItem setRightBarButtonItem:nil animated:(sender) ? YES : NO];
            }
        }];
    }
}

- (IBAction)connect:(id)sender
{
    [DSEventManager saveEvent:@"root:connect"];
    if (! sender && [self.reachability networkReachabilityStatus] == DSReachabilityStatusNotReachable) return;
    [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
    [DSEventManager saveEvent:@"root:connect_success"];
    if (self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) [self showErrorBar];
}

- (IBAction)navBarTap:(id)sender
{
    if ([self nextTip]) return;
    
    if (! self.errorBar.hidden) {
        [self hideErrorBarWithCompletion:^(BOOL finished) {
            [self connect:sender];
        }];
    }
    else if (![DSAuthenticationManager sharedInstance].didAuthenticate && self.shouldShowTips) {
        [self unlock:sender];
    }
    else [self tip:sender];
}

- (void)showBuyAlert
{
    // grab a blurred image for the background
    UIGraphicsBeginImageContext(self.navigationController.view.bounds.size);
    [self.navigationController.view drawViewHierarchyInRect:self.navigationController.view.bounds
                                         afterScreenUpdates:NO];
    UIImage *bgImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImage *blurredBgImg = [bgImg dw_blurWithRadius:3];
    
    // display the popup
    __weak BREventConfirmView *view =
    [[NSBundle mainBundle] loadNibNamed:@"BREventConfirmView" owner:nil options:nil][0];
    view.titleLabel.text = NSLocalizedString(@"Buy dash in dashwallet!", nil);
    view.descriptionLabel.text =
    NSLocalizedString(@"You can now buy dash in\ndashwallet with cash or\nbank transfer.", nil);
    [view.okBtn setTitle:NSLocalizedString(@"Try It!", nil) forState:UIControlStateNormal];
    
    view.image = blurredBgImg;
    view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    view.frame = self.navigationController.view.bounds;
    view.alpha = 0;
    [self.navigationController.view addSubview:view];
    
    [UIView animateWithDuration:.5 animations:^{
        view.alpha = 1;
    }];
    
    view.completionHandler = ^(BOOL didApprove) {
        if (didApprove) [self performSegueWithIdentifier:@"SettingsSegue" sender:@"buy alert"];
        
        [UIView animateWithDuration:.5 animations:^{
            view.alpha = 0;
        } completion:^(BOOL finished) {
            [view removeFromSuperview];
        }];
    };
}

// MARK: - UIPageViewControllerDataSource

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController
      viewControllerBeforeViewController:(UIViewController *)viewController
{
    return (viewController == self.receiveViewController) ? self.sendViewController : nil;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController
       viewControllerAfterViewController:(UIViewController *)viewController
{
    return (viewController == self.sendViewController) ? self.receiveViewController : nil;
}

- (NSInteger)presentationCountForPageViewController:(UIPageViewController *)pageViewController
{
    return 2;
}

- (NSInteger)presentationIndexForPageViewController:(UIPageViewController *)pageViewController
{
    return (pageViewController.viewControllers.lastObject == self.receiveViewController) ? 1 : 0;
}

// MARK: - UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return (transitionContext.isAnimated) ? 0.35 : 0.0;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    UIView *containerView = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
    *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    
    if (to == self || from == self) { // nav stack push/pop
        self.progress.hidden = self.pulse.hidden = YES;
        [containerView addSubview:to.view];
        to.view.center = CGPointMake(containerView.frame.size.width*(to == self ? -1 : 3)/2, to.view.center.y);
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
              initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                  to.view.center = from.view.center;
                  from.view.center = CGPointMake(containerView.frame.size.width*(to == self ? 3 : -1)/2, from.view.center.y);
              } completion:^(BOOL finished) {
                  if (to == self) {
                      [from.view removeFromSuperview];
                      self.navigationController.navigationBarHidden = YES; // hack to fix topLayoutGuide bug
                      [self.navigationController performSelector:@selector(setNavigationBarHidden:) withObject:nil
                                                      afterDelay:0];
                  }
                  
                  if (self.progress.progress > 0) self.progress.hidden = self.pulse.hidden = NO;
                  [transitionContext completeTransition:YES];
              }];
    }
    else if ([to isKindOfClass:[UINavigationController class]] && from == self.navigationController) { // modal display
        // to.view must be added to superview prior to positioning it off screen for its navbar to underlap statusbar
        [self.navigationController.navigationBar.superview insertSubview:to.view
                                                            belowSubview:self.navigationController.navigationBar];
        [containerView layoutIfNeeded];
        to.view.center = CGPointMake(to.view.center.x, containerView.frame.size.height*3/2);
        
        UINavigationItem *item = [(id)to topViewController].navigationItem;
        UIView *titleView = item.titleView;
        UIBarButtonItem *rightButton = item.rightBarButtonItem;
        
        item.title = nil;
        item.leftBarButtonItem.image = [UIImage imageNamed:@"none"];
        item.titleView = nil;
        item.rightBarButtonItem = nil;
        self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"none"];
        [containerView addSubview:self.burger];
        [containerView layoutIfNeeded];
        
        CGRect rect =[self.navigationController.navigationBar convertRect:CGRectMake(0, 0, self.navigationController.navigationBar.frame.size.width, self.navigationController.navigationBar.frame.size.height)  toView:containerView];
        float startX = 0; //a little hacky but good enough for now.
        if (containerView.frame.size.width> 375) {
            startX = 30;
        } else {
            startX = 26;
        }
        self.burger.center = CGPointMake(startX, rect.origin.y + (rect.size.height / 2) - 1);
        self.burger.hidden = NO;
        [self.burger setX:YES completion:nil];
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
              initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                  to.view.center = CGPointMake(to.view.center.x, containerView.frame.size.height/2);
                  self.pageViewController.view.alpha = 0.0;
                  self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                                    containerView.frame.size.height/4.0);
              } completion:^(BOOL finished) {
                  self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                                    containerView.frame.size.height/2.0);
                  
                  if (![DSAuthenticationManager sharedInstance].didAuthenticate) {
                      item.rightBarButtonItem = rightButton;
                      if (self.shouldShowTips) item.titleView = titleView;
                  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
                      if ([(id)[(UINavigationController *)to topViewController] respondsToSelector:@selector(updateTitleView)]) {
                          [(id)[(UINavigationController *)to topViewController] performSelector:@selector(updateTitleView)];
                      } else {
                          item.title = self.navigationItem.title;
                      }
#pragma clang diagnostic pop
                  }
                  item.leftBarButtonItem.image = [UIImage imageNamed:@"x"];
                  [containerView addSubview:to.view];
                  [transitionContext completeTransition:YES];
              }];
    }
    else if ([from isKindOfClass:[UINavigationController class]] && to == self.navigationController) { // modal dismiss
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
            [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
            [self.sendViewController updateClipboardText];
        }
        
        if ([DSAuthenticationManager sharedInstance].didAuthenticate) [self unlock:nil];
        [self.navigationController.navigationBar.superview insertSubview:from.view
                                                            belowSubview:self.navigationController.navigationBar];
        
        UINavigationItem *item = [(id)from topViewController].navigationItem;
        UIView *titleView = item.titleView;
        UIBarButtonItem *rightButton = item.rightBarButtonItem;
        
        item.title = nil;
        item.leftBarButtonItem.image = [UIImage imageNamed:@"none"];
        item.titleView = nil;
        item.rightBarButtonItem = nil;
        self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"none"];
        self.burger.hidden = NO;
        [containerView layoutIfNeeded];
        CGRect rect =[self.navigationController.navigationBar convertRect:CGRectMake(0, 0, self.navigationController.navigationBar.frame.size.width, self.navigationController.navigationBar.frame.size.height)  toView:containerView];
        float startX = 0; //a little hacky but good enough for now.
        if (containerView.frame.size.width> 375) {
            startX = 30;
        } else {
            startX = 26;
        }
        self.burger.center = CGPointMake(startX, rect.origin.y + (rect.size.height / 2) - 1);
        [self.burger setX:NO completion:nil];
        self.pageViewController.view.alpha = 0.0;
        self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                          containerView.frame.size.height/4.0 - self.navigationController.navigationBar.frame.size.height);
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
              initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                  from.view.center = CGPointMake(from.view.center.x, containerView.frame.size.height*3/2);
                  self.pageViewController.view.alpha = 1.0;
                  self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                                    containerView.frame.size.height/2 - self.navigationController.navigationBar.frame.size.height);
              } completion:^(BOOL finished) {
                  item.rightBarButtonItem = rightButton;
                  item.titleView = titleView;
                  item.title = self.navigationItem.title;
                  item.leftBarButtonItem.image = [UIImage imageNamed:@"x"];
                  [from.view removeFromSuperview];
                  self.burger.hidden = YES;
                  self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"burger"];
                  [transitionContext completeTransition:YES];
                  if (self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) [self showErrorBar];
              }];
    }
}

// MARK: - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                  animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC
                                                 toViewController:(UIViewController *)toVC
{
    return self;
}

// MARK: - UIViewControllerTransitioningDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
{
    return self;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    return self;
}

- (IBAction)unwindToRootViewController:(UIStoryboardSegue *)segue {
    //nothing goes here
    if([segue isKindOfClass:[DWStoryboardSegueWithCompletion class]]){
        DWStoryboardSegueWithCompletion *segtemp = (DWStoryboardSegueWithCompletion*)segue;// local prevents warning
        segtemp.completion = ^{
            [self setInitialPin];
        };
    }
}

// MARK: - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch{
    
    if (gestureRecognizer == self.navBarTap && [touch.view isKindOfClass:[UIControl class]]) {
        return NO;
    }
    return YES;
}

@end
