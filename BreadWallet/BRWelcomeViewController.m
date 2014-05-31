//
//  BRWelcomeViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 7/8/13.
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

#import "BRWelcomeViewController.h"
#import "BRWalletManager.h"

#define WALLPAPER_ANIMATION_DURATION 30.0
#define WALLPAPER_ANIMATION_X 240.0
#define WALLPAPER_ANIMATION_Y 0.0

@interface BRWelcomeViewController ()

@property (nonatomic, assign) BOOL hasAppeared, animating;
@property (nonatomic, strong) id activeObserver, resignActiveObserver;

@property (nonatomic, strong) IBOutlet UIView *paralax, *wallpaper;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *logoXCenter, *walletXCenter, *restoreXCenter;
@end

@implementation BRWelcomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
        
    [self.navigationController.navigationBar
     setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor],
                              NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue" size:17.0]}];
    
    self.navigationController.delegate = self;

    self.activeObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if ([[BRWalletManager sharedInstance] wallet]) { // sanity check
                [self.navigationController.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            }

            if (! self.animating) {
                self.animating = YES;

                [UIView animateWithDuration:WALLPAPER_ANIMATION_DURATION delay:0.0
                 options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse
                 animations:^{
                     self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 - WALLPAPER_ANIMATION_X,
                                                         self.wallpaper.frame.size.height/2 - WALLPAPER_ANIMATION_Y);
                 } completion:^(BOOL finished) {
                     self.animating = NO;
                 }];
            }
        }];
    
    self.resignActiveObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2, self.wallpaper.center.y);
        }];
}

- (void)dealloc
{
    self.navigationController.delegate = nil;
    if (self.activeObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];
    if (self.resignActiveObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:NO];

    if (self.hasAppeared) {
        self.logoXCenter.constant = self.view.frame.size.width;
        self.navigationItem.titleView.hidden = NO;
    }
    else {
        self.walletXCenter.constant = -self.view.frame.size.width;
        self.restoreXCenter.constant = -self.view.frame.size.width;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    dispatch_async(dispatch_get_main_queue(), ^{ // animation sometimes doesn't work if run directly in viewDidAppear
        if ([[BRWalletManager sharedInstance] wallet]) { // sanity check
            [self.navigationController.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        }

        if (! self.animating) {
            self.animating = YES;

            [UIView animateWithDuration:WALLPAPER_ANIMATION_DURATION delay:0.0
             options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse
             animations:^{
                 self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 - WALLPAPER_ANIMATION_X,
                                                     self.wallpaper.frame.size.height/2 - WALLPAPER_ANIMATION_Y);
             } completion:^(BOOL finished) {
                 self.animating = NO;
             }];
        }

        if (! self.hasAppeared) {
            self.hasAppeared = YES;
            self.logoXCenter.constant = self.view.frame.size.width;
            self.walletXCenter.constant = 0;
            self.restoreXCenter.constant = 0;
            self.navigationItem.titleView.hidden = NO;
            self.navigationItem.titleView.alpha = 0.0;

            [UIView animateWithDuration:0.35 delay:1.0 usingSpringWithDamping:0.8 initialSpringVelocity:0
             options:UIViewAnimationOptionCurveEaseOut animations:^{
                [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationSlide];
                self.navigationItem.titleView.alpha = 1.0;
                self.paralax.center = CGPointMake(self.view.frame.size.width*PARALAX_RATIO, self.paralax.center.y);
                [self.view layoutIfNeeded];
            } completion:nil];
        }
    });
}

//- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
//    [super prepareForSegue:segue sender:sender];
//
//    [segue.destinationViewController setTransitioningDelegate:self];
//    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
//}

- (void)viewDidLayoutSubviews
{
    if (self.paralax.superview == self.view) {
        self.paralax.center = CGPointMake(self.paralax.center.x, self.paralax.superview.frame.size.height/2);
    }
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

    if (self.paralax.superview != v) {
        self.paralax.center = CGPointMake(-v.frame.size.width*PARALAX_RATIO,
                                          (v.frame.size.height - self.paralax.frame.size.height)/2);
        [v insertSubview:self.paralax belowSubview:from.view];
    }

    to.view.center = CGPointMake(v.frame.size.width*(to == self ? -1 : 3)/2, to.view.center.y);
    [v addSubview:to.view];

    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
     initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        to.view.center = from.view.center;
        from.view.center = CGPointMake(v.frame.size.width*(to == self ? 3 : -1)/2, from.view.center.y);
        self.paralax.center = CGPointMake(v.frame.size.width*(to == self ? -1 : -2)*PARALAX_RATIO,
                                          self.paralax.center.y);
    } completion:^(BOOL finished) {
        if (to == self) [from.view removeFromSuperview];
        [transitionContext completeTransition:finished];
    }];
}

#pragma mark - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC
toViewController:(UIViewController *)toVC
{
    return self;
}

//TODO: implement interactive transitions

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
