//
//  BRRootViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 9/15/13.
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

#import "BRRootViewController.h"
#import "BRReceiveViewController.h"
#import "BRSendViewController.h"
#import "BRBubbleView.h"
#import "BRBouncyBurgerButton.h"
#import "BRPeerManager.h"
#import "BRWalletManager.h"
#import "BRWallet.h"
#import "Reachability.h"
#import <sys/stat.h>
#import <mach-o/dyld.h>

#define BALANCE_TIP NSLocalizedString(@"This is your bitcoin balance. Bitcoin is a currency. "\
                                       "The exchange rate changes with the market.", nil)
#define BITS_TIP    NSLocalizedString(@"%@ is for 'bits'. %@ = 1 bitcoin.", nil)

#define BACKUP_DIALOG_TIME_KEY @"BACKUP_DIALOG_TIME"

@interface BRRootViewController ()

@property (nonatomic, strong) IBOutlet UIProgressView *progress, *pulse;
@property (nonatomic, strong) IBOutlet UILabel *percent;
@property (nonatomic, strong) IBOutlet UIView *errorBar, *wallpaper, *splash, *logo;
@property (nonatomic, strong) IBOutlet UIGestureRecognizer *navBarTap;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *lock;
@property (nonatomic, strong) IBOutlet BRBouncyBurgerButton *burger;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, assign) BOOL appeared, showTips, inNextTip;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) id urlObserver, fileObserver, foregroundObserver, backgroundObserver, balanceObserver;
@property (nonatomic, strong) id reachabilityObserver, syncStartedObserver, syncFinishedObserver, syncFailedObserver;
@property (nonatomic, assign) NSTimeInterval timeout, start;

@end

@implementation BRRootViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

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

    self.receiveViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"ReceiveViewController"];
    self.sendViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"SendViewController"];
    self.pageViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"PageViewController"];

    self.pageViewController.dataSource = self;
    [self.pageViewController setViewControllers:@[self.sendViewController]
     direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    self.pageViewController.view.frame = self.view.bounds;
    [self addChildViewController:self.pageViewController];
    [self.view insertSubview:self.pageViewController.view belowSubview:self.splash];
    [self.pageViewController didMoveToParentViewController:self];

    for (UIView *view in self.pageViewController.view.subviews) {
        if (! [view isKindOfClass:[UIScrollView class]]) continue;
        self.scrollView = (id)view;
        self.scrollView.delegate = self;
        //self.scrollView.delaysContentTouches = NO; // this allows buttons to respond more quickly
        break;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];

    self.urlObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRURLNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            BRSendViewController *c = self.sendViewController;
        
            [self.pageViewController setViewControllers:@[c] direction:UIPageViewControllerNavigationDirectionForward
             animated:NO completion:^(BOOL finished) { [c handleURL:note.userInfo[@"url"]]; }];
        }];

    self.fileObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRFileNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            BRSendViewController *c = self.sendViewController;

            [self.pageViewController setViewControllers:@[c] direction:UIPageViewControllerNavigationDirectionForward
             animated:NO completion:^(BOOL finished) { [c handleFile:note.userInfo[@"file"]]; }];
        }];

    self.foregroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.appeared && m.wallet) [[BRPeerManager sharedInstance] connect];

            if (jailbroken && m.wallet.balance > 0) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                  message:NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                            "Any 'jailbreak' app can access any other app's keychain data "
                                            "(and steal your bitcoins). "
                                            "Wipe this wallet immediately and restore on a secure device.", nil)
                 delegate:self cancelButtonTitle:NSLocalizedString(@"ignore", nil)
                 otherButtonTitles:NSLocalizedString(@"wipe", nil), nil] show];
            }
            else if (jailbroken) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                  message:NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                            "Any 'jailbreak' app can access any other app's keychain data "
                                            "(and steal your bitcoins).", nil)
                  delegate:self cancelButtonTitle:NSLocalizedString(@"ignore", nil)
                  otherButtonTitles:NSLocalizedString(@"close app", nil), nil] show];
            }
        }];

    self.backgroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.appeared && m.wallet) { // lockdown the app
                m.didAuthenticate = NO;
                self.navigationItem.titleView = self.logo;
                self.navigationItem.rightBarButtonItem = self.lock;

                if (self.navigationController.topViewController != self) {
                    [self.navigationController popToRootViewControllerAnimated:YES];
                }

                if (self.navigationController.presentedViewController) {
                    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
                }
            }
        }];

    self.reachabilityObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if (self.appeared && self.reachability.currentReachabilityStatus != NotReachable &&
                [[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground) {
                [[BRPeerManager sharedInstance] connect];
            }
            else if (self.appeared && self.reachability.currentReachabilityStatus == NotReachable) [self showErrorBar];
        }];

    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if ([[BRPeerManager sharedInstance] syncProgress] < 1.0) return; // wait for sync before updating balance
            [self showBackupDialogIfNeeded];
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                         [m localCurrencyStringForAmount:m.wallet.balance]];

            // update receive qr code if it's not on screen
            if (self.pageViewController.viewControllers.lastObject != self.receiveViewController) {
                [self.receiveViewController updateAddress];
            }
        }];

    self.syncStartedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncStartedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            BRPeerManager *p = [BRPeerManager sharedInstance];

            if (self.reachability.currentReachabilityStatus != NotReachable) [self hideErrorBar];
            [self startActivityWithTimeout:0];

            if (p.lastBlockHeight + 2016/2 < p.estimatedBlockHeight &&
                m.seedCreationTime + 60*60*24 < [NSDate timeIntervalSinceReferenceDate]) {
                self.percent.hidden = NO;
                self.navigationItem.title = NSLocalizedString(@"syncing...", nil);
            }
        }];
    
    self.syncFinishedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFinishedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.timeout < 1.0) [self stopActivityWithSuccess:YES];
            [self showBackupDialogIfNeeded];
            self.percent.hidden = YES;
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                         [m localCurrencyStringForAmount:m.wallet.balance]];
        }];
    
    self.syncFailedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFailedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.timeout < 1.0) [self stopActivityWithSuccess:NO];
            [self showErrorBar];
            [self showBackupDialogIfNeeded];
            self.percent.hidden = YES;
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                         [m localCurrencyStringForAmount:m.wallet.balance]];
        }];
    
    //TODO: XXX applicationProtectedDataDidBecomeAvailable observer
    
    self.reachability = [Reachability reachabilityForInternetConnection];
    [self.reachability startNotifier];

    self.navigationController.delegate = self;
    self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                 [m localCurrencyStringForAmount:m.wallet.balance]];

#if BITCOIN_TESTNET
    UILabel *label = [UILabel new];

    label.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:13.0];
    label.textColor = [UIColor redColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.text = @"testnet";
    [label sizeToFit];
    label.center = CGPointMake(self.view.frame.size.width - label.frame.size.width,
                               self.view.frame.size.height - label.frame.size.height - 5);
    [self.view addSubview:label];
#endif

    if (! [[UIApplication sharedApplication] isProtectedDataAvailable] || m.wallet) {
        // TODO: XXXX require auth
        self.splash.hidden = YES;
        self.navigationController.navigationBar.hidden = NO;
        [[UIApplication sharedApplication] setStatusBarHidden:NO];
    }
    
    [self showBackupDialogIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    BRWalletManager *m = [BRWalletManager sharedInstance];

    if ([[UIApplication sharedApplication] isProtectedDataAvailable] && ! m.wallet) {
        [self.navigationController
        presentViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"] animated:NO
        completion:^{
            self.splash.hidden = YES;
            self.navigationController.navigationBar.hidden = NO;
        }];

        self.showTips = YES;
        [self unlock:nil];
        return;
    }

    self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"burger"];
    self.pageViewController.view.alpha = 1.0;
    if (m.didAuthenticate) [self unlock:nil];

    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground) {
        [[BRPeerManager sharedInstance] connect];
    }

    //TODO: try making the balance start at zero and quickly increase to the actual balance, ala city guides

    if (! self.appeared) {
        self.appeared = YES;

        if (m.wallet.balance == 0) {
            [self.pageViewController setViewControllers:@[self.receiveViewController]
             direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    if (! self.navBarTap) {
        self.navBarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(navBarTap:)];
        [self.navigationController.navigationBar addGestureRecognizer:self.navBarTap];
    }

    self.splash.hidden = YES;
    self.navigationController.navigationBar.hidden = NO;
    if (self.reachability.currentReachabilityStatus == NotReachable) [self showErrorBar];

    if (self.navigationController.visibleViewController == self) {
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
        [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];

        if (self.showTips) [self performSelector:@selector(tip:) withObject:nil afterDelay:0.3];
        [self showBackupDialogIfNeeded];
    }

    [super viewDidAppear:animated];
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

    [segue.destinationViewController setTransitioningDelegate:self];
    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
    [self hideErrorBar];
    
    if (sender == self) { // show backup phrase
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
          message:NSLocalizedString(@"\nDO NOT let anyone see your backup phrase or they can spend your bitcoins.\n\n"
                                    "DO NOT take a screenshot. Screenshots are visible to other apps and devices.\n",
                                    nil) delegate:[[(id)segue.destinationViewController viewControllers] firstObject]
          cancelButtonTitle:NSLocalizedString(@"cancel", nil) otherButtonTitles:NSLocalizedString(@"show", nil), nil]
         show];
    }
}

- (void)viewDidLayoutSubviews
{
    self.wallpaper.center = CGPointMake(self.wallpaper.center.x, self.wallpaper.superview.frame.size.height/2);
    [self scrollViewDidScroll:self.scrollView];
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self.reachability stopNotifier];

    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.urlObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    if (self.fileObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.fileObserver];
    if (self.foregroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.foregroundObserver];
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    if (self.reachabilityObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
}

- (void)startActivityWithTimeout:(NSTimeInterval)timeout
{
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];

    if (timeout > 1 && start + timeout > self.start + self.timeout) {
        self.timeout = timeout;
        self.start = start;
    }

    [UIApplication sharedApplication].idleTimerDisabled = YES;
    self.progress.hidden = self.pulse.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{ self.progress.alpha = 1.0; }];
    [self updateProgress];
}

- (void)stopActivityWithSuccess:(BOOL)success
{
    double progress = [[BRPeerManager sharedInstance] syncProgress];

    self.start = self.timeout = 0.0;
    if (progress > DBL_EPSILON && progress < 1.0) return; // not done syncing
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    if (self.progress.alpha < 0.5) return;

    if (success) {
        [self.progress setProgress:1.0 animated:YES];
        [self.pulse setProgress:1.0 animated:YES];
        
        [UIView animateWithDuration:0.2 animations:^{
            self.progress.alpha = self.pulse.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.progress.hidden = self.pulse.hidden = YES;
            self.progress.progress = self.pulse.progress = 0.0;
        }];
    }
    else {
        self.progress.hidden = self.pulse.hidden = YES;
        self.progress.progress = self.pulse.progress = 0.0;
    }
}

- (void)setProgressTo:(NSNumber *)n
{
    self.progress.progress = [n floatValue];
}

- (void)updateProgress
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateProgress) object:nil];

    static int counter = 0;
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate] - self.start;
    double progress = [[BRPeerManager sharedInstance] syncProgress];

    if (self.timeout > 1.0 && 0.1 + 0.9*t/self.timeout < progress) progress = 0.1 + 0.9*t/self.timeout;
    if (progress <= DBL_EPSILON) progress = self.progress.progress;

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
    self.percent.text = [NSString stringWithFormat:@"%0.1f%%", (progress > 0.1 ? progress - 0.1 : 0.0)*111.0];
    if (progress < 1.0) [self performSelector:@selector(updateProgress) withObject:nil afterDelay:0.2];
}

- (void)showErrorBar
{
    if (self.navigationItem.prompt != nil) return;
    self.navigationItem.prompt = @"";
    self.errorBar.hidden = NO;
    self.errorBar.alpha = 0.0;
    
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration delay:0.0
    options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.burger.center = CGPointMake(self.burger.center.x, 70.0);
        self.errorBar.alpha = 1.0;
    } completion:nil];
}

- (void)hideErrorBar
{
    if (self.navigationItem.prompt == nil) return;
    self.navigationItem.prompt = nil;

    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration delay:0.0
    options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.burger.center = CGPointMake(self.burger.center.x, 40.0);
        self.errorBar.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (self.navigationItem.prompt == nil) self.errorBar.hidden = YES;
    }];
}

- (void)hideTips
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(tip:) object:nil];
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

- (BOOL)nextTip
{
    if (self.tipView.alpha < 0.5) {
        BOOL r;

        if (self.inNextTip) return NO; // break out of recursive loop
        self.inNextTip = YES;
        r = [self.pageViewController.viewControllers.lastObject nextTip];
        self.inNextTip = NO;
        return r;
    }

    BRBubbleView *v = self.tipView;

    self.tipView = nil;
    [v popOut];

    if ([v.text hasPrefix:BALANCE_TIP]) {
        BRWalletManager *m = [BRWalletManager sharedInstance];
        UINavigationBar *b = self.navigationController.navigationBar;
        NSString *text = [NSString stringWithFormat:BITS_TIP, m.format.currencySymbol, [m stringForAmount:SATOSHIS]];
        CGRect r = [self.navigationItem.title boundingRectWithSize:b.bounds.size options:0
                    attributes:b.titleTextAttributes context:nil];

        self.tipView = [BRBubbleView viewWithText:text
                        tipPoint:CGPointMake(b.center.x + 5.0 - r.size.width/2.0,
                                             b.frame.origin.y + b.frame.size.height - 10)
                        tipDirection:BRBubbleTipDirectionUp];
        self.tipView.backgroundColor = v.backgroundColor;
        self.tipView.font = v.font;
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips) {
        self.showTips = NO;
        [self.pageViewController.viewControllers.lastObject tip:self];
    }

    return YES;
}

- (void)showBackupDialogIfNeeded
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    if (self.navigationController.visibleViewController != self || ! [defs boolForKey:WALLET_NEEDS_BACKUP_KEY] ||
        m.wallet.balance == 0 || [defs doubleForKey:BACKUP_DIALOG_TIME_KEY] > now - 36*60*60) return;
    
    BOOL first = ([defs doubleForKey:BACKUP_DIALOG_TIME_KEY] < 1.0) ? YES : NO;
    
    [defs setDouble:now forKey:BACKUP_DIALOG_TIME_KEY];
    
    [[[UIAlertView alloc]
      initWithTitle:(first) ? NSLocalizedString(@"you received bitcoin!", nil) : NSLocalizedString(@"IMPORTANT", nil)
      message:[NSString
               stringWithFormat:NSLocalizedString(@"\n%@\n\nwrite down your backup phrase and use it to restore on "
                                                  "another device if this one is ever lost or broken", nil),
               (first) ? NSLocalizedString(@"next, backup your wallet", nil) :
               NSLocalizedString(@"BACKUP YOUR WALLET", nil)] delegate:self
      cancelButtonTitle:NSLocalizedString(@"do it later", nil) otherButtonTitles:NSLocalizedString(@"backup", nil), nil]
     show];
}

#pragma mark - IBAction

- (IBAction)tip:(id)sender
{
    if (sender == self.receiveViewController) {
        BRSendViewController *c = self.sendViewController;

        [(id)self.pageViewController setViewControllers:@[c] direction:UIPageViewControllerNavigationDirectionReverse
        animated:YES completion:^(BOOL finished) { [c tip:sender]; }];
        return;
    }
    else if (sender == self.sendViewController) {
        self.scrollView.scrollEnabled = YES;
        [(id)self.pageViewController setViewControllers:@[self.receiveViewController]
         direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:nil];
        return;
    }

    UINavigationBar *b = self.navigationController.navigationBar;

    self.tipView = [BRBubbleView viewWithText:BALANCE_TIP
                    tipPoint:CGPointMake(b.center.x, b.frame.origin.y + b.frame.size.height - 10)
                    tipDirection:BRBubbleTipDirectionUp];
    if (self.showTips) self.tipView.text = [self.tipView.text stringByAppendingString:@" (1/6)"];
    self.tipView.backgroundColor = [UIColor orangeColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    self.tipView.userInteractionEnabled = NO;
    [self.view addSubview:[self.tipView popIn]];
    if (self.showTips) self.scrollView.scrollEnabled = NO;
}

- (IBAction)unlock:(id)sender
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    
    if (sender && ! m.didAuthenticate && ! [m authenticateWithPrompt:nil]) return;
    
    self.navigationItem.titleView = nil;
    self.navigationItem.rightBarButtonItem = nil;
}

- (IBAction)connect:(id)sender
{
    if (! sender && [self.reachability currentReachabilityStatus] == NotReachable) return;

    [[BRPeerManager sharedInstance] connect];
}

- (IBAction)navBarTap:(id)sender
{
    if ([self nextTip]) return;

    if (! self.errorBar.hidden) {
        [self connect:sender];
    }
    else if (! [[BRWalletManager sharedInstance] didAuthenticate]) {
        [self unlock:sender];
    }
    else [self tip:sender];
}

#pragma mark - UIPageViewControllerDataSource

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

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat off = scrollView.contentOffset.x + (scrollView.contentInset.left < 0 ? scrollView.contentInset.left : 0);
    
    self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 - PARALAX_RATIO*off, self.wallpaper.center.y);
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;

    if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:NSLocalizedString(@"close app", nil)]) abort();

    if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:NSLocalizedString(@"wipe", nil)]) {
        [[[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"CONFIRM WIPE", nil) delegate:self
          cancelButtonTitle:NSLocalizedString(@"cancel", nil) destructiveButtonTitle:NSLocalizedString(@"wipe", nil)
          otherButtonTitles:nil] showInView:[[UIApplication sharedApplication] keyWindow]];
        return;
    }
    
    [self performSegueWithIdentifier:@"SettingsSegue" sender:self];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != actionSheet.destructiveButtonIndex) return;

    [[BRWalletManager sharedInstance] setSeedPhrase:nil];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:WALLET_NEEDS_BACKUP_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UINavigationController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"];

    [self.navigationController presentViewController:c animated:NO completion:nil];

    [[[UIAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"the app will now close", nil) delegate:self
      cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"close app", nil), nil] show];
}

#pragma mark - UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return (transitionContext.isAnimated) ? 0.35 : 0.0;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    UIView *v = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];

    if (to == self || from == self) { // nav stack push/pop
        if (self.wallpaper.superview != v) {
            v.backgroundColor = self.view.backgroundColor;
            self.view.backgroundColor = [UIColor clearColor];
            [v insertSubview:self.wallpaper belowSubview:from.view];
        }

        self.progress.hidden = self.pulse.hidden = YES;
        [v addSubview:to.view];
        to.view.center = CGPointMake(v.frame.size.width*(to == self ? -1 : 3)/2, to.view.center.y);

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            to.view.center = from.view.center;
            from.view.center = CGPointMake(v.frame.size.width*(to == self ? 3 : -1)/2, from.view.center.y);
            self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 -
                                                v.frame.size.width*(to == self ? 0 : 1)*PARALAX_RATIO,
                                                self.wallpaper.center.y);
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
        to.view.center = CGPointMake(to.view.center.x, v.frame.size.height*3/2);

        UINavigationItem *item = [[(id)to viewControllers].firstObject navigationItem];
        UIView *titleView = item.titleView;
        UIBarButtonItem *rightButton = item.rightBarButtonItem;

        item.title = nil;
        item.leftBarButtonItem.image = nil;
        item.titleView = nil;
        item.rightBarButtonItem = nil;
        self.navigationItem.leftBarButtonItem.image = nil;
        [v addSubview:self.burger];
        [v layoutIfNeeded];
        self.burger.center = CGPointMake(26.0, 40.0);
        self.burger.hidden = NO;
        [self.burger setX:YES completion:nil];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            to.view.center = CGPointMake(to.view.center.x, v.frame.size.height/2);
            self.pageViewController.view.alpha = 0.0;
            self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                              v.frame.size.height/4.0);
        } completion:^(BOOL finished) {
            self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                              v.frame.size.height/2.0);
            item.rightBarButtonItem = rightButton;
            item.titleView = titleView;
            item.leftBarButtonItem.image = [UIImage imageNamed:@"x"];
            item.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                          [m localCurrencyStringForAmount:m.wallet.balance]];
            [v addSubview:to.view];
            [transitionContext completeTransition:YES];
        }];
    }
    else if ([from isKindOfClass:[UINavigationController class]] && to == self.navigationController) { // modal dismiss
        if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground) {
            [[BRPeerManager sharedInstance] connect];
        }
        
        if (m.didAuthenticate) [self unlock:nil];
        [self.navigationController.navigationBar.superview insertSubview:from.view
         belowSubview:self.navigationController.navigationBar];
        [(id)from topViewController].navigationItem.title = nil;
        self.burger.hidden = NO;
        [v layoutIfNeeded];
        self.burger.center = CGPointMake(26.0, 40.0);
        [self.burger setX:NO completion:nil];
        self.pageViewController.view.alpha = 0.0;
        self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                          v.frame.size.height/4.0);

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            from.view.center = CGPointMake(from.view.center.x, v.frame.size.height*3/2);
            self.pageViewController.view.alpha = 1.0;
            self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                              v.frame.size.height/2);
        } completion:^(BOOL finished) {
            [from.view removeFromSuperview];
            self.burger.hidden = YES;
            self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"burger"];
            [transitionContext completeTransition:YES];
            if (self.reachability.currentReachabilityStatus == NotReachable) [self showErrorBar];
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
