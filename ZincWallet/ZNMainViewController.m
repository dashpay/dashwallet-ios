//
//  ZNMainViewController.m
//  ZincWallet
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

#import "ZNMainViewController.h"
#import "ZNPayViewController.h"
#import "ZNReceiveViewController.h"
#import "ZNWallet.h"
#import "ZNPeerManager.h"
#import <netinet/in.h>
#import "Reachability.h"

@interface ZNMainViewController ()

@property (nonatomic, strong) id urlObserver, activeObserver, balanceObserver, reachabilityObserver;
@property (nonatomic, strong) id syncStartedObserver, syncFinishedObserver, syncFailedObserver;
@property (nonatomic, assign) int syncErrorCount;

@property (nonatomic, strong) IBOutlet UIScrollView *scrollView;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;
@property (nonatomic, strong) IBOutlet UIPageControl *pageControl;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *settingsButton, *refreshButton;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;

@property (nonatomic, strong) ZNPayViewController *payController;
@property (nonatomic, strong) ZNReceiveViewController *receiveController;
@property (nonatomic, strong) Reachability *reachability;

@property (nonatomic, assign) CGPoint wallpaperStart;

@end

@implementation ZNMainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //TODO: make title use dynamic font size
    ZNWallet *w = [ZNWallet sharedInstance];
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.frame =
        CGRectMake(self.spinner.frame.origin.x, self.spinner.frame.origin.y, 20.0, self.spinner.frame.size.height);
    self.spinner.accessibilityLabel = @"synchornizing";
    
    self.settingsButton.accessibilityLabel = @"settings";
    self.refreshButton.accessibilityLabel = @"synchronize";
    self.pageControl.accessibilityLabel = @"receive money";
    
    self.wallpaperStart = self.wallpaper.center;
    
    self.urlObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:ZNURLNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            [self.scrollView setContentOffset:CGPointZero animated:YES];
            
            if (w.masterPublicKey) [self.navigationController dismissViewControllerAnimated:NO completion:nil];
        }];
    
    self.activeObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [[ZNPeerManager sharedInstance] connect];
        }];
    
    // TODO: switch to AFNetworkingReachability
    self.reachabilityObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if (self.reachability.currentReachabilityStatus != NotReachable) [[ZNPeerManager sharedInstance] connect];
        }];
    
    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:balanceChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:w.balance],
                                         [w localCurrencyStringForAmount:w.balance]];
            
            // update receive qr code if it's not on screen
            if (self.pageControl.currentPage != 1) [[self receiveController] viewWillAppear:NO];
        }];
    
    self.syncStartedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:syncStartedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if (self.navigationItem.rightBarButtonItem == self.refreshButton) {
                self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
                [self.spinner startAnimating];
            }
            
            if (w.balance == 0) self.navigationItem.title = @"syncing...";
        }];
    
    self.syncFinishedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:syncFinishedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            self.syncErrorCount = 0;
            [self.spinner stopAnimating]; //BUG: XXXX this sometimes takes several seconds to display... why?!?
            self.navigationItem.rightBarButtonItem = self.refreshButton;
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:w.balance],
                                         [w localCurrencyStringForAmount:w.balance]];
        }];
    
    //TODO: create an error banner instead of using an alert
    self.syncFailedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:syncFailedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            self.syncErrorCount++;
//            if ([note.userInfo[@"error"] code] == 504 && self.syncErrorCount < 3) {
//                [[[UIAlertView alloc] initWithTitle:@"couldn't refresh wallet balance" message:@"retrying..."
//                  delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
//                [w synchronize:YES];
//                return;
//            }
            
            [self.spinner stopAnimating];
            self.navigationItem.rightBarButtonItem = self.refreshButton;
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:w.balance],
                                         [w localCurrencyStringForAmount:w.balance]];
            
            [[[UIAlertView alloc] initWithTitle:@"couldn't refresh wallet balance"
              message:[note.userInfo[@"error"] localizedDescription] delegate:nil cancelButtonTitle:@"ok"
              otherButtonTitles:nil] show];
        }];
    
    self.reachability = [Reachability reachabilityWithHostName:@"blockchain.info"];
    [self.reachability startNotifier];
    
    self.navigationController.delegate = self;
    [self.navigationController.view insertSubview:self.wallpaper atIndex:0];
    self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:w.balance],
                                 [w localCurrencyStringForAmount:w.balance]];
}

- (void)dealloc
{
    [self.reachability stopNotifier];
    
    if (self.urlObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    if (self.activeObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];
    if (self.reachabilityObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    static BOOL firstAppearance = YES;
    ZNWallet *w = [ZNWallet sharedInstance];
    
    if (! w.masterPublicKey) {
        UINavigationController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNNewWalletNav"];
        
        [self.navigationController presentViewController:c animated:NO completion:nil];
        return;
    }
    else if (firstAppearance && ! animated) { // BUG: somehow the splash screen is showing up when handling url
        UIViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNSplashViewController"];
        
        if ([[UIScreen mainScreen] bounds].size.height < 500) { // use splash image for 3.5" screen
            [(UIImageView *)c.view setImage:[UIImage imageNamed:@"Default.png"]];
        }
        
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:NO];
        
        [self.navigationController presentViewController:c animated:NO completion:^{
            [self.navigationController dismissViewControllerAnimated:YES completion:^{
                [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
            }];
        }];
    }
    else [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
    
    if (firstAppearance) {
        firstAppearance = NO;
        
        self.scrollView.contentSize = CGSizeMake(self.scrollView.frame.size.width*2,
                                                 self.scrollView.frame.size.height);
        
        [self.scrollView addSubview:self.payController.view];
        [self addChildViewController:self.payController];
        
        self.receiveController.view.frame = CGRectMake(self.scrollView.frame.size.width, 0,
                                                       self.scrollView.frame.size.width,
                                                       self.scrollView.frame.size.height);
        [self.scrollView addSubview:self.receiveController.view];
        [self addChildViewController:self.receiveController];
        
        if (w.balance == 0) {
            [self.scrollView setContentOffset:CGPointMake(self.scrollView.frame.size.width, 0) animated:NO];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [[ZNPeerManager sharedInstance] connect];
}

- (ZNPayViewController *)payController
{
    if (_payController) return _payController;
    
    _payController = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNPayViewController"];
    return _payController;
}

- (ZNReceiveViewController *)receiveController
{
    if (_receiveController) return _receiveController;
    
    _receiveController = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNReceiveViewController"];
    return _receiveController;
}

#pragma mark - IBAction

- (IBAction)refresh:(id)sender
{
    if (! sender && [self.reachability currentReachabilityStatus] == NotReachable) return;
    
    if (self.navigationItem.rightBarButtonItem == self.refreshButton) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
        [self.spinner startAnimating];
    }
    
    if ([[ZNWallet sharedInstance] balance] == 0) self.navigationItem.title = @"syncing...";
    
    [[ZNPeerManager sharedInstance] connect];
}

- (IBAction)page:(id)sender
{
    if (! sender) {
        [self.scrollView
         setContentOffset:CGPointMake((1 - self.pageControl.currentPage)*self.scrollView.frame.size.width, 0)
         animated:YES];

        return;
    }

    if ([self.scrollView isTracking] || [self.scrollView isDecelerating] ||
        self.pageControl.currentPage == self.scrollView.contentOffset.x/self.scrollView.frame.size.width + 0.5) return;
    
    [self.scrollView setContentOffset:CGPointMake(self.pageControl.currentPage*self.scrollView.frame.size.width, 0)
     animated:YES];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    NSInteger page = scrollView.contentOffset.x/scrollView.frame.size.width + 0.5;
    
    if (self.pageControl.currentPage != page) {
        self.pageControl.currentPage = scrollView.contentOffset.x/scrollView.frame.size.width + 0.5;
        self.pageControl.accessibilityLabel = page ? @"send money" : @"receive money";
        
        [(id)(page ? self.payController : self.receiveController) hideTips];
    }
    
    self.wallpaper.center = CGPointMake(self.wallpaperStart.x - scrollView.contentOffset.x*PARALAX_RATIO,
                                        self.wallpaperStart.y);
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
    
    [UIView animateWithDuration:SEGUE_DURATION animations:^{
        if (viewController != self) {
            self.wallpaper.center = CGPointMake(self.wallpaperStart.x - self.view.frame.size.width*PARALAX_RATIO,
                                                self.wallpaperStart.y);
        }
        else self.wallpaper.center = self.wallpaperStart;
    }];
}

@end
