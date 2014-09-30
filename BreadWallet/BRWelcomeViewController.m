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
@property (nonatomic, strong) id foregroundObserver, backgroundObserver;
@property (nonatomic, strong) UINavigationController *seedNav;

@property (nonatomic, strong) IBOutlet UIView *paralax, *wallpaper;
@property (nonatomic, strong) IBOutlet UILabel *startLabel, *warningLabel;
@property (nonatomic, strong) IBOutlet UIButton *generateButton, *showButton;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *logoXCenter, *walletXCenter, *restoreXCenter, *paralaxXLeft;

@end

@implementation BRWelcomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
        
    self.navigationController.delegate = self;

    self.foregroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if ([[BRWalletManager sharedInstance] wallet]) { // sanity check
                [self.navigationController.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            }
            else [self animateWallpaper];
        }];
    
    self.backgroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2, self.wallpaper.center.y);
        }];
}

- (void)dealloc
{
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.foregroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.foregroundObserver];
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:animated];
    
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
        
        [self animateWallpaper];
        
        if (! self.hasAppeared) {
            self.hasAppeared = YES;
            self.logoXCenter.constant = self.view.frame.size.width;
            self.walletXCenter.constant = 0.0;
            self.restoreXCenter.constant = 0.0;
            self.paralaxXLeft.constant = self.view.frame.size.width*PARALAX_RATIO;
            self.navigationItem.titleView.hidden = NO;
            self.navigationItem.titleView.alpha = 0.0;

            [UIView animateWithDuration:0.35 delay:1.0 usingSpringWithDamping:0.8 initialSpringVelocity:0.0
             options:UIViewAnimationOptionCurveEaseOut animations:^{
                [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationSlide];
                self.navigationItem.titleView.alpha = 1.0;
                [self.view.superview layoutIfNeeded];
            } completion:nil];
        }
    });
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [super prepareForSegue:segue sender:sender];

//    [segue.destinationViewController setTransitioningDelegate:self];
//    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
    
    self.startLabel = (id)[[segue.destinationViewController view] viewWithTag:4];
    self.warningLabel = (id)[[segue.destinationViewController view] viewWithTag:2];
    self.generateButton = (id)[[segue.destinationViewController view] viewWithTag:1];
    [self.generateButton addTarget:self action:@selector(generate:) forControlEvents:UIControlEventTouchUpInside];
    self.showButton = (id)[[segue.destinationViewController view] viewWithTag:3];
    [self.showButton addTarget:self action:@selector(show:) forControlEvents:UIControlEventTouchUpInside];
    
    if (self.warningLabel) {
        NSTextAttachment *noEye = [NSTextAttachment new], *noShot = [NSTextAttachment new];
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
                                        initWithAttributedString:self.warningLabel.attributedText];
    
        noEye.image = [UIImage imageNamed:@"no-eye"];
        [s replaceCharactersInRange:[s.string rangeOfString:@"%no-eye%"]
         withAttributedString:[NSAttributedString attributedStringWithAttachment:noEye]];
        noShot.image = [UIImage imageNamed:@"no-shot"];
        [s replaceCharactersInRange:[s.string rangeOfString:@"%no-shot%"]
         withAttributedString:[NSAttributedString attributedStringWithAttachment:noShot]];
        self.warningLabel.attributedText = s;
    }
}

- (void)animateWallpaper
{
    if (self.animating) return;
    self.animating = YES;
    
    if (self.paralax.superview != self.view.superview) {
        NSLayoutConstraint *c = self.paralaxXLeft;
        UIView *v = self.view.superview;
    
        self.paralaxXLeft = [NSLayoutConstraint constraintWithItem:(c.firstItem == self.paralax ? c.firstItem : v)
                             attribute:c.firstAttribute relatedBy:c.relation
                             toItem:(c.secondItem == self.paralax ? c.secondItem : v) attribute:c.secondAttribute
                             multiplier:c.multiplier constant:c.constant];
        [v insertSubview:self.paralax belowSubview:self.view];
        [v addConstraint:self.paralaxXLeft];

        NSArray *a = self.wallpaper.superview.constraints;
        
        [self.wallpaper.superview
         removeConstraints:[a objectsAtIndexes:[a indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return ([obj firstItem] == self.wallpaper || [obj secondItem] == self.wallpaper) ? YES : NO;
        }]]];
        
        [v layoutIfNeeded];
        self.paralax.center = CGPointMake(self.paralax.center.x, v.bounds.size.height/2.0);
    }
    
    [UIView animateWithDuration:WALLPAPER_ANIMATION_DURATION delay:0.0
    options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse animations:^{
        self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2.0 - WALLPAPER_ANIMATION_X,
                                            self.wallpaper.frame.size.height/2.0 - WALLPAPER_ANIMATION_Y);
    } completion:^(BOOL finished) {
        self.animating = NO;
    }];
}

#pragma mark IBAction

- (IBAction)generate:(id)sender
{
    // make the user wait a few seconds so they'll get bored enough to read the information on the screen
    [self.navigationController.navigationBar.topItem setHidesBackButton:YES animated:YES];
    [sender setEnabled:NO];

    self.seedNav = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedNav"];
    
    self.warningLabel.hidden = self.showButton.hidden = NO;
    self.warningLabel.alpha = self.showButton.alpha = 0.0;
        
    [UIView animateWithDuration:0.5 animations:^{
        self.warningLabel.alpha = self.showButton.alpha = 1.0;
        self.navigationController.navigationBar.topItem.titleView.alpha = 0.33*0.5;
        self.startLabel.alpha = 0.33;
        self.generateButton.alpha = 0.33;
    }];
}

- (IBAction)show:(id)sender
{
    [self.navigationController presentViewController:self.seedNav animated:YES completion:nil];
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

    to.view.center = CGPointMake(v.frame.size.width*(to == self ? -1 : 3)/2.0, to.view.center.y);
    [v addSubview:to.view];
    [v layoutIfNeeded];

    self.paralaxXLeft.constant = v.frame.size.width*(to == self ? 1 : 2)*PARALAX_RATIO;
    
    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
    initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        to.view.center = from.view.center;
        from.view.center = CGPointMake(v.frame.size.width*(to == self ? 3 : -1)/2.0, from.view.center.y);
        [self.paralax.superview layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (to == self) [from.view removeFromSuperview];
        [transitionContext completeTransition:YES];
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
