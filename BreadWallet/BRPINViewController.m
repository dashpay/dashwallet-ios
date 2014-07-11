//
//  BRPINViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 7/5/14.
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

#import "BRPINViewController.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "NSString+Base58.h"

#define PIN_LENGTH 4
#define CIRCLE     @"\xE2\x97\x8B" // white (empty) circle, unicode U+25CB (utf-8)
#define DOT        @"\xE2\x97\x8F" // black (filled) circle, uincode U+25CF (utf-8)

@interface BRPINViewController ()

@property (nonatomic, strong) IBOutlet UILabel *titleLabel, *dotsLabel, *dipsLabel, *lockLabel;
@property (nonatomic, strong) IBOutlet UIButton *cancelButton, *resetButton;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;
@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *padButtons;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *logoXCenter, *titleXCenter, *dotsXCenter, *padXCenter,
                                                          *wallpaperX;

@property (nonatomic, strong) NSMutableString *pin, *verifyPin;
@property (nonatomic, strong) NSMutableSet *badPins;
@property (nonatomic, strong) id txStatusObserver;

@end

@implementation BRPINViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    [self.navigationController.navigationBar
     setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor],
                              NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue" size:17.0]}];

    self.navigationController.delegate = self;
    
    NSShadow *shadow = [NSShadow new];

    [shadow setShadowColor:[UIColor colorWithWhite:0.0 alpha:0.15]];
    [shadow setShadowBlurRadius:1.0];
    [shadow setShadowOffset:CGSizeMake(0.0, 1.0)];

    for (UIButton *b in self.padButtons) {
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
                                        initWithAttributedString:[b attributedTitleForState:UIControlStateNormal]];

        [s addAttribute:NSShadowAttributeName value:shadow range:NSMakeRange(0, s.length)];
        [b setAttributedTitle:s forState:UIControlStateNormal];
    }

    if (! self.appeared) {
        self.titleXCenter.constant = self.dotsXCenter.constant = self.padXCenter.constant = self.view.bounds.size.width;
    }
    else {
        self.logoXCenter.constant = self.view.bounds.size.width;
        self.wallpaperX.constant = self.view.bounds.size.width*PARALAX_RATIO;
    }

    self.txStatusObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [self checkLockout];
        }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.pin = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), PIN_LENGTH));
    self.badPins = [NSMutableSet set];

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:NO];
    [[BRPeerManager sharedInstance] connect];
    [self checkLockout];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (self.appeared) return;
    self.appeared = YES;

    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    
    self.titleXCenter.constant = self.dotsXCenter.constant = self.padXCenter.constant = 0.0;
    self.logoXCenter.constant = self.view.bounds.size.width;
    self.wallpaperX.constant = self.view.bounds.size.width*PARALAX_RATIO;

    [UIView animateWithDuration:0.35 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
     animations:^{ [self.view layoutIfNeeded]; } completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.pin = nil;
    self.badPins = nil;

    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (void)checkLockout
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSUInteger failCount = m.pinFailCount;

    if (failCount > 2) {
        uint32_t failHeight = m.pinFailHeight, wait = pow(5, failCount - 3),
                 lastHeight = [[BRPeerManager sharedInstance] lastBlockHeight];

        if (failHeight + wait > lastHeight) { // locked out
            uint32_t minutes = (failHeight + wait - lastHeight)*10, hours = minutes/60, days = hours/24;
            NSString *units = NSLocalizedString(@"minutes", nil), *time;

            if (hours == 1) units = NSLocalizedString(@"hour", nil);
            if (hours > 1) units = NSLocalizedString(@"hours", nil);
            if (days == 1) units = NSLocalizedString(@"day", nil);
            if (days > 1) units = NSLocalizedString(@"days", nil);
            time = [NSString stringWithFormat:@"%u %@", days ? days : (hours ? hours : minutes), units];

            self.lockLabel.text =
               [NSString stringWithFormat:NSLocalizedString(@"wallet disabled\n\ntry again after block #%u\n(about %@)",
                                                            nil), failHeight + wait, time, failCount];
            [self.cancelButton setTitle:NSLocalizedString(@"reset pin", key) forState:UIControlStateNormal];

            for (UIButton *b in self.padButtons) {
                b.enabled = NO;
            }

            if (self.lockLabel.hidden) {
                self.lockLabel.hidden = NO;
                self.lockLabel.alpha = 0.0;
                [UIView animateWithDuration:0.2 animations:^{ self.lockLabel.alpha = 1.0; }];
            }

            return;
        }
    }

    // not locked out
    if (self.pin.length > 0) return;

    if (m.pin.length == PIN_LENGTH) {
        self.titleLabel.text = NSLocalizedString(@"enter pin", nil);
    }
    else self.titleLabel.text = NSLocalizedString(@"choose a pin", nil);

    [self.cancelButton setTitle:(self.appeared ? NSLocalizedString(@"cancel", key) : @"")
     forState:UIControlStateNormal];

    for (UIButton *b in self.padButtons) {
        b.enabled = YES;
    }

    if (! self.lockLabel.hidden) {
        [UIView animateWithDuration:0.2 animations:^{
            self.lockLabel.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.lockLabel.alpha = 1.0;
            self.lockLabel.hidden = YES;
        }];
    }
}

#pragma mark - IBAction

- (IBAction)number:(id)sender
{
    [sender setAlpha:0.15];
    [UIView animateWithDuration:0.35 animations:^{ [sender setAlpha:1.0]; }];

    if (self.pin.length >= PIN_LENGTH) return;
    [self.pin appendFormat:@"%C", [[sender currentAttributedTitle].string characterAtIndex:0]];

    BRWalletManager *m = [BRWalletManager sharedInstance];

    if (self.pin.length < PIN_LENGTH) {
        self.dipsLabel.alpha = 0.0;
        self.dipsLabel.transform = CGAffineTransformMakeScale(1.0, 0.0);
        self.dipsLabel.text = DOT;

        for (NSUInteger i = 1; i < self.pin.length; i++) {
            self.dipsLabel.text = [self.dipsLabel.text stringByAppendingString:@"  " DOT];
        }

        [UIView animateWithDuration:0.15 animations:^{
            self.dipsLabel.alpha = 1.0;
            self.dipsLabel.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            self.dipsLabel.alpha = 0.0;
            self.dotsLabel.text = self.dipsLabel.text;

            for (NSUInteger i = self.pin.length; i < PIN_LENGTH; i++) {
                self.dotsLabel.text = [self.dotsLabel.text stringByAppendingString:@"  " CIRCLE];
            }
        }];

        if (! [self.cancelButton.currentTitle isEqual:NSLocalizedString(@"delete", nil)]) {
            [UIView animateWithDuration:0.15 animations:^{
                self.cancelButton.alpha = 0.0;
            } completion:^(BOOL finished) {
                [self.cancelButton setTitle:NSLocalizedString(@"delete", nil) forState:UIControlStateNormal];
                [UIView animateWithDuration:0.15 animations:^{ self.cancelButton.alpha = 1.0; }];
            }];
        }
    }
    else if ([self.pin isEqual:m.pin]) { // successful pin attempt
        self.pin.string = @"";
        [self.badPins removeAllObjects];

        if (m.pinFailCount > 0) {
            m.pinFailCount = 0;
            m.pinFailHeight = 0;
        }
    }
    else if (m.pin.length == PIN_LENGTH) { // failed pin attempt
        if (! [self.badPins containsObject:self.pin]) {
            [self.badPins addObject:self.pin];
            self.pin = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), PIN_LENGTH));
            m.pinFailCount++;
            m.pinFailHeight = [[BRPeerManager sharedInstance] lastBlockHeight];
        }
        else self.pin.string = @"";

        [self checkLockout];

        self.dotsLabel.text = DOT @"  " DOT @"  " DOT @"  " DOT;
        self.dotsXCenter.constant = 30.0;
            
        [UIView animateWithDuration:0.05 delay:0.1 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            self.dotsLabel.text = CIRCLE @"  " CIRCLE @"  " CIRCLE @"  " CIRCLE;
            self.dotsXCenter.constant = 0.0;

            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.2 initialSpringVelocity:0.0 options:0
             animations:^{ [self.view layoutIfNeeded]; } completion:nil];
        }];
    }
    else if (self.verifyPin.length == 0) { // reenter pin
        self.verifyPin = self.pin;
        self.pin = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), PIN_LENGTH));
        self.dotsLabel.text = DOT @"  " DOT @"  " DOT @"  " DOT;
        self.dotsXCenter.constant = -self.dotsLabel.bounds.size.width/2 - self.view.bounds.size.width/2;
        self.titleXCenter.constant = self.dotsXCenter.constant;

        [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            self.titleLabel.text = NSLocalizedString(@"reenter pin", nil);
            self.dotsLabel.text = CIRCLE @"  " CIRCLE @"  " CIRCLE @"  " CIRCLE;
            self.dotsXCenter.constant = self.dotsLabel.bounds.size.width/2 + self.view.bounds.size.width/2;
            self.titleXCenter.constant = self.dotsXCenter.constant;
            [self.view layoutIfNeeded];
            self.dotsXCenter.constant = self.titleXCenter.constant = 0;

            [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
             animations:^{ [self.view layoutIfNeeded]; } completion:nil];
        }];
    }
    else if (! [self.pin isEqual:self.verifyPin]) { // reenter pin mismatch
        self.verifyPin = nil;
        self.pin.string = @"";
        self.dotsLabel.text = DOT @"  " DOT @"  " DOT @"  " DOT;
        self.dotsXCenter.constant = 30.0;

        [UIView animateWithDuration:0.05 delay:0.1 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            self.titleLabel.text = NSLocalizedString(@"choose a pin", nil);
            self.dotsLabel.text = CIRCLE @"  " CIRCLE @"  " CIRCLE @"  " CIRCLE;
            self.dotsXCenter.constant = 0.0;

            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.2 initialSpringVelocity:0.0 options:0
             animations:^{ [self.view layoutIfNeeded]; } completion:nil];
        }];
    }
    else { // set new pin
        m.pin = self.verifyPin;
        self.verifyPin = nil;
        self.pin.string = @"";
        self.dotsLabel.text = DOT @"  " DOT @"  " DOT @"  " DOT;
        [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    }
}

- (IBAction)cancel:(id)sender
{
    [sender setAlpha:0.15];
    [UIView animateWithDuration:0.35 animations:^{ [sender setAlpha:1.0]; }];

    if (self.pin.length > 0) {
        self.dipsLabel.alpha = 1.0;
        self.dipsLabel.text = DOT;

        for (NSUInteger i = 1; i < self.pin.length; i++) {
            self.dipsLabel.text = [self.dipsLabel.text stringByAppendingString:@"  " DOT];
        }

        self.dotsLabel.text = [[self.dipsLabel.text substringToIndex:self.dipsLabel.text.length - 1]
                               stringByAppendingString:CIRCLE];

        for (NSUInteger i = self.pin.length; i < PIN_LENGTH; i++) {
            self.dotsLabel.text = [self.dotsLabel.text stringByAppendingString:@"  " CIRCLE];
        }

        [UIView animateWithDuration:0.15 animations:^{
            self.dipsLabel.alpha = 0.0;
            self.dipsLabel.transform = CGAffineTransformMakeScale(1.0, 0.0);
        } completion:^(BOOL finished) {
            self.dipsLabel.transform = CGAffineTransformIdentity;
        }];

        [self.pin deleteCharactersInRange:NSMakeRange(self.pin.length - 1, 1)];
    }

    if (self.pin.length > 0) return;

    if ([[sender currentTitle] isEqual:NSLocalizedString(@"delete", nil)]) {
        [UIView animateWithDuration:0.15 animations:^{
            [sender setAlpha:0.0];
        } completion:^(BOOL finished) {
            [sender setTitle:(self.appeared ? NSLocalizedString(@"cancel", nil) : @"") forState:UIControlStateNormal];
            [UIView animateWithDuration:0.15 animations:^{ [sender setAlpha:1.0]; }];
        }];
    }
    else if ([[sender currentTitle] isEqual:NSLocalizedString(@"reset pin", nil)]) {
        UIViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"PINResetController"];

        [self.navigationController pushViewController:c animated:YES];
    }
    else if (self.appeared) {
        [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
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

    if (self.wallpaper.superview != v) {
        [v insertSubview:self.wallpaper belowSubview:from.view];
    }

    to.view.center = CGPointMake(v.frame.size.width*(to == self ? -1 : 3)/2, to.view.center.y);
    [v addSubview:to.view];

    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
    initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.lockLabel.alpha = (to == self) ? 1.0 : 0.0;
        to.view.center = from.view.center;
        from.view.center = CGPointMake(v.frame.size.width*(to == self ? 3 : -1)/2, from.view.center.y);
        self.wallpaper.center = CGPointMake(self.wallpaper.bounds.size.width/2 -
                                            v.bounds.size.width*(to == self ? 1 : 2)*PARALAX_RATIO,
                                            self.wallpaper.center.y);
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
