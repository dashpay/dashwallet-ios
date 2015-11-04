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
#import "BRRootViewController.h"
#import "BRWalletManager.h"
#import "BREventManager.h"


@interface BRWelcomeViewController ()

@property (nonatomic, assign) BOOL hasAppeared, animating;
@property (nonatomic, strong) id foregroundObserver, backgroundObserver;
@property (nonatomic, strong) UINavigationController *seedNav;

@property (nonatomic, strong) IBOutlet UIView *paralax, *wallpaper;
@property (nonatomic, strong) IBOutlet UILabel *startLabel, *recoverLabel, *warningLabel;
@property (nonatomic, strong) IBOutlet UIButton *newwalletButton, *recoverButton, *generateButton, *showButton;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *logoXCenter, *walletXCenter, *restoreXCenter,
                                                          *paralaxXLeft, *wallpaperXLeft;

@end


@implementation BRWelcomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
        
    self.navigationController.delegate = self;

    self.newwalletButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.recoverButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.newwalletButton.titleLabel.adjustsLetterSpacingToFitWidth = YES;
    self.recoverButton.titleLabel.adjustsLetterSpacingToFitWidth = YES;
#pragma clang diagnostic pop

    self.foregroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [self animateWallpaper];
        }];
    
    self.backgroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            self.wallpaperXLeft.constant = 0;
            [self.wallpaper.superview layoutIfNeeded];
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
    [BREventManager saveEvent:@"welcome:shown"];

    dispatch_async(dispatch_get_main_queue(), ^{ // animation sometimes doesn't work if run directly in viewDidAppear
#if SNAPSHOT
        [[UIApplication sharedApplication] setStatusBarHidden:NO];
        self.navigationItem.titleView.hidden = NO;
        self.navigationItem.titleView.alpha = 1.0;
        self.logoXCenter.constant = self.view.frame.size.width;
        self.walletXCenter.constant = self.restoreXCenter.constant = 0.0;
        self.paralaxXLeft.constant = self.view.frame.size.width*PARALAX_RATIO;
        return;
#endif

        if (! [BRWalletManager sharedInstance].noWallet) { // sanity check
            [self.navigationController.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        }
        
        if (! self.hasAppeared) {
            self.hasAppeared = YES;
            self.paralaxXLeft = [NSLayoutConstraint constraintWithItem:self.view.superview
                                 attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.paralax
                                 attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0];
            [self.view.superview insertSubview:self.paralax belowSubview:self.view];
            [self.view.superview addConstraint:self.paralaxXLeft];
            [self.view.superview addConstraint:[NSLayoutConstraint constraintWithItem:self.view.superview
             attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.paralax
             attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]];
            self.view.superview.backgroundColor = self.paralax.backgroundColor;
            [self.view.superview layoutIfNeeded];
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
        
        [self animateWallpaper];
    });
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [super prepareForSegue:segue sender:sender];

//    [segue.destinationViewController setTransitioningDelegate:self];
//    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
    
    self.startLabel = (id)[[segue.destinationViewController view] viewWithTag:4];
    self.recoverLabel = (id)[[segue.destinationViewController view] viewWithTag:5];
    self.warningLabel = (id)[[segue.destinationViewController view] viewWithTag:2];
    self.generateButton = (id)[[segue.destinationViewController view] viewWithTag:1];
    [self.generateButton addTarget:self action:@selector(generate:) forControlEvents:UIControlEventTouchUpInside];
    self.generateButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.generateButton.titleLabel.adjustsLetterSpacingToFitWidth = YES;
#pragma clang diagnostic pop

    self.showButton = (id)[[segue.destinationViewController view] viewWithTag:3];
    [self.showButton addTarget:self action:@selector(show:) forControlEvents:UIControlEventTouchUpInside];
    
    if (self.warningLabel) {
        NSTextAttachment *noEye = [NSTextAttachment new], *noKey = [NSTextAttachment new];
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
                                        initWithAttributedString:self.warningLabel.attributedText];
    
        noEye.image = [UIImage imageNamed:@"no-eye"];
        [s replaceCharactersInRange:[s.string rangeOfString:@"%no-eye%"]
         withAttributedString:[NSAttributedString attributedStringWithAttachment:noEye]];
        noKey.image = [UIImage imageNamed:@"no-key"];
        [s replaceCharactersInRange:[s.string rangeOfString:@"%no-key%"]
         withAttributedString:[NSAttributedString attributedStringWithAttachment:noKey]];
        
        [s replaceCharactersInRange:[s.string rangeOfString:@"WARNING"]
         withString:NSLocalizedString(@"WARNING", nil)];
        [s replaceCharactersInRange:[s.string rangeOfString:@"\nDO NOT let anyone see your recovery\n"
                                     "phrase or they can spend your bitcoins.\n"]
         withString:NSLocalizedString(@"\nDO NOT let anyone see your recovery\n"
                                      "phrase or they can spend your bitcoins.\n", nil)];
        [s replaceCharactersInRange:[s.string rangeOfString:@"\nNEVER type your recovery phrase into\n"
                                     "password managers or elsewhere.\nOther devices may be infected.\n"]
         withString:NSLocalizedString(@"\nNEVER type your recovery phrase into\npassword managers or elsewhere.\n"
                                      "Other devices may be infected.\n", nil)];
        self.warningLabel.attributedText = s;
    }
}

- (void)animateWallpaper
{
    if (self.animating) return;
    self.animating = YES;
//    self.wallpaperXLeft.constant = -240.0;
//
//    [UIView animateWithDuration:30.0 delay:0.0
//    options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
//    animations:^{
//        [self.wallpaper.superview layoutIfNeeded];
//    } completion:^(BOOL finished) {
//        self.animating = NO;
//    }];
}

#pragma mark IBAction

- (IBAction)generate:(id)sender
{
    [BREventManager saveEvent:@"welcome:generate"];
    if (! [BRWalletManager sharedInstance].passcodeEnabled) {
        [BREventManager saveEvent:@"welcome:passcode_disabled"];
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"turn device passcode on", nil)
          message:NSLocalizedString(@"\nA device passcode is needed to safeguard your wallet. Go to settings and turn "
                                    "passcode on to continue.", nil)
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        return;
    }

    [self.navigationController.navigationBar.topItem setHidesBackButton:YES animated:YES];
    [sender setEnabled:NO];
    self.seedNav = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedNav"];
    self.warningLabel.hidden = self.showButton.hidden = NO;
    self.warningLabel.alpha = self.showButton.alpha = 0.0;
        
    [UIView animateWithDuration:0.5 animations:^{
        self.warningLabel.alpha = self.showButton.alpha = 1.0;
        self.navigationController.navigationBar.topItem.titleView.alpha = 0.33*0.5;
        self.startLabel.alpha = self.recoverLabel.alpha = 0.33;
        self.generateButton.alpha = 0.33;
    }];
}

- (IBAction)show:(id)sender
{
    [BREventManager saveEvent:@"welcome:show"];
    [self.navigationController presentViewController:self.seedNav animated:YES completion:^{
        self.warningLabel.hidden = self.showButton.hidden = YES;
        self.navigationController.navigationBar.topItem.titleView.alpha = 1.0;
        self.startLabel.alpha = self.recoverLabel.alpha = 1.0;
        self.generateButton.alpha = 1.0;
        self.generateButton.enabled = YES;
        self.navigationController.navigationBar.topItem.hidesBackButton = NO;
    }];
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
