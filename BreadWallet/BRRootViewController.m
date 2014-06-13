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

#define BALANCE_TIP NSLocalizedString(@"This is your bitcoin balance. Bitcoin is a currency. "\
                                       "The exchange rate changes with the market.", nil)

@interface BRRootViewController ()

@property (nonatomic, strong) IBOutlet UIProgressView *progress, *pulse;
@property (nonatomic, strong) IBOutlet UIView *errorBar, *wallpaper;
@property (nonatomic, strong) IBOutlet UIGestureRecognizer *navBarTap;
@property (nonatomic, strong) IBOutlet BRBouncyBurgerButton *burger;

@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, assign) BOOL appeared, showTips, inNextTip;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) id urlObserver, fileObserver, activeObserver, balanceObserver, reachabilityObserver;
@property (nonatomic, strong) id syncStartedObserver, syncFinishedObserver, syncFailedObserver;
@property (nonatomic, assign) NSTimeInterval timeout, start;

@end

@implementation BRRootViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.receiveViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"ReceiveViewController"];
    self.sendViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"SendViewController"];
    self.pageViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"PageViewController"];

    self.pageViewController.dataSource = self;
    [self.pageViewController setViewControllers:@[self.sendViewController]
     direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    self.pageViewController.view.frame = self.view.bounds;
    [self addChildViewController:self.pageViewController];
    [self.view addSubview:self.pageViewController.view];
    [self.pageViewController didMoveToParentViewController:self];

    for (UIView *view in self.pageViewController.view.subviews) {
        if (! [view isKindOfClass:[UIScrollView class]]) continue;
        [(UIScrollView *)view setDelegate:self];
        [(UIScrollView *)view setDelaysContentTouches:NO]; // this allows buttons to respond more quickly
        break;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];

    self.urlObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRURLNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            [self.pageViewController setViewControllers:@[self.sendViewController]
             direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
            self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2, self.wallpaper.center.y);
            if (m.wallet) [self.navigationController dismissViewControllerAnimated:NO completion:nil];
        }];

    self.fileObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRFileNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            [self.pageViewController setViewControllers:@[self.sendViewController]
             direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
            self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2, self.wallpaper.center.y);
            if (m.wallet) [self.navigationController dismissViewControllerAnimated:NO completion:nil];
        }];

    self.activeObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.appeared) [[BRPeerManager sharedInstance] connect];
        }];

    self.reachabilityObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if (self.appeared && self.reachability.currentReachabilityStatus != NotReachable) {
                [[BRPeerManager sharedInstance] connect];
            }
            else if (self.appeared && self.reachability.currentReachabilityStatus == NotReachable) {
                [self showErrorBar];
            }
        }];

    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if ([[BRPeerManager sharedInstance] syncProgress] < 1.0) return; // wait for sync before updating balance

            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                         [m localCurrencyStringForAmount:m.wallet.balance]];

            // update receive qr code if it's not on screen
            if (self.pageViewController.viewControllers.lastObject != self.receiveViewController) {
                [self.receiveViewController viewWillAppear:NO];
            }
        }];

    self.syncStartedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncStartedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.reachability.currentReachabilityStatus != NotReachable) [self hideErrorBar];
            [self startActivityWithTimeout:0];

            if (m.wallet.balance == 0 && m.seedCreationTime == BITCOIN_REFERENCE_BLOCK_TIME) {
                self.navigationItem.title = @"syncing...";
            }
        }];
    
    self.syncFinishedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFinishedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.timeout < 1.0) [self stopActivityWithSuccess:YES];
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                         [m localCurrencyStringForAmount:m.wallet.balance]];
        }];
    
    self.syncFailedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFailedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.timeout < 1.0) [self stopActivityWithSuccess:NO];
            [self showErrorBar];
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                         [m localCurrencyStringForAmount:m.wallet.balance]];
        }];
    
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
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if ([[UIApplication sharedApplication] isProtectedDataAvailable] && ! [[BRWalletManager sharedInstance] wallet]) {
        UINavigationController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"];

        [self.navigationController presentViewController:c animated:NO completion:nil];
        self.showTips = YES;
        return;
    }

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    [[BRPeerManager sharedInstance] connect];
}

- (void)viewDidAppear:(BOOL)animated
{
    self.navBarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(navBarTap:)];
    self.navBarTap.delegate = self;
    [self.navigationController.navigationBar addGestureRecognizer:self.navBarTap];

    if (! self.appeared) {
        self.appeared = YES;
        
        if ([[[BRWalletManager sharedInstance] wallet] balance] == 0) {
            [self.pageViewController setViewControllers:@[self.receiveViewController]
             direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:nil];
        }

        if (self.showTips) [self performSelector:@selector(tip:) withObject:nil afterDelay:0.3];
    }

    if (self.reachability.currentReachabilityStatus == NotReachable) [self showErrorBar];

    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self.navigationController.navigationBar removeGestureRecognizer:self.navBarTap];
    self.navBarTap = nil;

    [super viewWillDisappear:animated];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [super prepareForSegue:segue sender:sender];

    [segue.destinationViewController setTransitioningDelegate:self];
    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
    [self hideErrorBar];
}

- (void)viewDidLayoutSubviews
{
    self.wallpaper.center = CGPointMake(self.wallpaper.center.x, self.wallpaper.superview.frame.size.height/2);
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self.reachability stopNotifier];

    if (self.urlObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    if (self.fileObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.fileObserver];
    if (self.activeObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];
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
    if (progress < 1.0) [self performSelector:@selector(updateProgress) withObject:nil afterDelay:0.2];
}

- (void)showErrorBar {
    if (self.navigationItem.prompt != nil) return;
    self.navigationItem.prompt = @"";
    self.errorBar.hidden = NO;
    self.errorBar.alpha = 0.0;
    
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration delay:0.0
     options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.errorBar.alpha = 1.0;
    } completion:nil];
}

- (void)hideErrorBar {
    if (self.navigationItem.prompt == nil) return;
    self.navigationItem.prompt = nil;

    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration delay:0.0
     options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.errorBar.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (self.navigationItem.prompt == nil) self.errorBar.hidden = YES;
    }];
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

    [self.tipView popOut];
    self.tipView = nil;
    if (self.showTips) [self.pageViewController.viewControllers.lastObject tip:self];
    self.showTips = NO;
    return YES;
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
        [(id)self.pageViewController setViewControllers:@[self.receiveViewController]
         direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:nil];
        return;
    }

    self.tipView = [BRBubbleView viewWithText:BALANCE_TIP
                    tipPoint:CGPointMake(self.view.bounds.size.width/2.0,
                                         self.navigationController.navigationBar.frame.origin.y +
                                         self.navigationController.navigationBar.frame.size.height - 10)
                    tipDirection:BRBubbleTipDirectionUp];

    self.tipView.backgroundColor = [UIColor orangeColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    [self.view addSubview:[self.tipView popIn]];
}

- (IBAction)connect:(id)sender
{
    if (! sender && [self.reachability currentReachabilityStatus] == NotReachable) return;

    [[BRPeerManager sharedInstance] connect];
}

- (IBAction)navBarTap:(id)sender
{
    if ([self nextTip]) return;

    if (self.errorBar.hidden) {
        [self tip:sender];
    }
    else [self connect:sender];
}

#pragma mark UIPageViewControllerDataSource

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

#pragma mark UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 - PARALAX_RATIO*(scrollView.contentOffset.x +
                                        (scrollView.contentInset.left < 0 ? scrollView.contentInset.left : 0)),
                                        self.wallpaper.center.y);
}

#pragma mark UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return 0.35;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    UIView *v = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];

    if (to == self || from == self) { // nav stack push/pop
        if (self.wallpaper.superview != v) {
            v.backgroundColor = self.view.backgroundColor;
            self.view.backgroundColor = [UIColor clearColor];
            [v insertSubview:self.wallpaper belowSubview:from.view];
        }

        to.view.center = CGPointMake(v.frame.size.width*(to == self ? -1 : 3)/2, to.view.center.y);
        [v addSubview:to.view];
    
        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            to.view.center = from.view.center;
            from.view.center = CGPointMake(v.frame.size.width*(to == self ? 3 : -1)/2, from.view.center.y);
            self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 -
                                                v.frame.size.width*(to == self ? 0 : 1)*PARALAX_RATIO,
                                                self.wallpaper.center.y);
        } completion:^(BOOL finished) {
            if (to == self) [from.view removeFromSuperview];
            [transitionContext completeTransition:finished];
        }];
    }
    else if ([to isKindOfClass:[UINavigationController class]] && from == self.navigationController) { // modal display
        // to.view must be added to superview prior to positioning it off screen for its navbar to underlap statusbar
        [self.navigationController.navigationBar.superview insertSubview:to.view
         belowSubview:self.navigationController.navigationBar];
        to.view.center = CGPointMake(to.view.center.x, v.frame.size.height*3/2);

        UIBarButtonItem *item = [(id)to topViewController].navigationItem.leftBarButtonItem;
        NSString *title = self.navigationItem.title;

        [(id)to topViewController].navigationItem.leftBarButtonItem = nil;
        [(id)to topViewController].navigationItem.title = nil;

        [self.burger setX:YES completion:^(BOOL finished) {
            [(id)to topViewController].navigationItem.leftBarButtonItem = item;
            [(id)to topViewController].navigationItem.title = title;
            [v addSubview:to.view];
            [transitionContext completeTransition:finished];
        }];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            to.view.center = CGPointMake(to.view.center.x, v.frame.size.height/2);
            self.pageViewController.view.center =
                CGPointMake(self.pageViewController.view.center.x, v.frame.size.height/4);
            self.pageViewController.view.alpha = 0.0;
        } completion:nil];
    }
    else if ([from isKindOfClass:[UINavigationController class]] && to == self.navigationController) { // modal dismiss
        UIBarButtonItem *item = [(id)from topViewController].navigationItem.leftBarButtonItem;

        [(id)from topViewController].navigationItem.leftBarButtonItem = nil;
        [(id)from topViewController].navigationItem.title = nil;
        if (self.reachability.currentReachabilityStatus == NotReachable) [self showErrorBar];
        [self.burger setX:NO completion:nil];
        [v insertSubview:to.view belowSubview:from.view];
        [self.navigationController.navigationBar.superview insertSubview:from.view
         belowSubview:self.navigationController.navigationBar];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            from.view.center = CGPointMake(from.view.center.x, v.frame.size.height*3/2);
            self.pageViewController.view.center =
                CGPointMake(self.pageViewController.view.center.x, v.frame.size.height/2);
            self.pageViewController.view.alpha = 1.0;
        } completion:^(BOOL finished) {
            [(id)from topViewController].navigationItem.leftBarButtonItem = item;
            [from.view removeFromSuperview];
            [transitionContext completeTransition:finished];
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

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    return ([touch.view isKindOfClass:[UIButton class]]) ? NO : YES;
}

@end
