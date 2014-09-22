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
#import "BRBubbleView.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "BRTransaction.h"
#import "NSString+Base58.h"
#import <AudioToolbox/AudioServices.h>

#define PIN_LENGTH 4
#define CIRCLE     @"\xE2\x97\x8B" // white (empty) circle, unicode U+25CB (utf-8)
#define DOT        @"\xE2\x97\x8F" // black (filled) circle, uincode U+25CF (utf-8)

@interface BRPINViewController ()

@property (nonatomic, strong) IBOutlet UILabel *titleLabel, *dotsLabel, *lockLabel;
@property (nonatomic, strong) IBOutlet UIButton *cancelButton;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;
@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *padButtons;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *logoXCenter, *titleXCenter, *dotsXCenter, *padXCenter,
                                                          *wallpaperXLeft;

@property (nonatomic, strong) NSMutableString *pin, *verifyPin;
@property (nonatomic, strong) NSMutableSet *badPins;
@property (nonatomic, assign) BOOL fail;
@property (nonatomic, strong) id txStatusObserver;

@end

@implementation BRPINViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.navigationController.delegate = self;
    
    NSShadow *shadow = [NSShadow new];
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
                                    initWithAttributedString:self.lockLabel.attributedText];

    [shadow setShadowColor:[UIColor colorWithWhite:0.0 alpha:0.15]];
    [shadow setShadowBlurRadius:1.0];
    [shadow setShadowOffset:CGSizeMake(0.0, 1.0)];

    [s addAttribute:NSShadowAttributeName value:shadow range:NSMakeRange(0, s.length)];
    self.lockLabel.attributedText = s;

    for (UIButton *b in self.padButtons) {
        s = [[NSMutableAttributedString alloc]
             initWithAttributedString:[b attributedTitleForState:UIControlStateNormal]];
        [s addAttribute:NSShadowAttributeName value:shadow range:NSMakeRange(0, s.length)];
        [b setAttributedTitle:s forState:UIControlStateNormal];
    }

    if (self.appeared) {
        self.logoXCenter.constant = self.view.bounds.size.width;
        self.wallpaperXLeft.constant = self.view.bounds.size.width*PARALAX_RATIO;
    }
    else {
        self.titleXCenter.constant = self.dotsXCenter.constant = self.padXCenter.constant = self.view.bounds.size.width;
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

    _success = NO;
    self.pin = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), PIN_LENGTH));
    self.badPins = [NSMutableSet set];
    self.verifyPin = nil;
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:animated];
    
    if (self.appeared) {
        self.logoXCenter.constant = self.view.bounds.size.width;
        self.wallpaperXLeft.constant = self.view.bounds.size.width*PARALAX_RATIO;
    }

    [self checkLockout];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [[BRPeerManager sharedInstance] connect];

    if (! self.appeared) {
        self.titleXCenter.constant = self.dotsXCenter.constant = self.padXCenter.constant = 0.0;
        self.logoXCenter.constant = self.view.bounds.size.width;
        self.wallpaperXLeft.constant = self.view.bounds.size.width*PARALAX_RATIO;

        [UIView animateWithDuration:0.35 delay:0.1 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
        animations:^{ [self.view layoutIfNeeded]; } completion:nil];
    }

    [self performSelector:@selector(checkLockout) withObject:nil afterDelay:0.0];
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.pin = nil;
    self.badPins = nil;
    self.verifyPin = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)checkLockout
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    if (! [[UIApplication sharedApplication] isProtectedDataAvailable]) {
        [self.padButtons makeObjectsPerformSelector:@selector(setEnabled:) withObject:nil];
        [self performSelector:@selector(checkLockout) withObject:nil afterDelay:0.1];
        return;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRPeerManager *p = [BRPeerManager sharedInstance];
    NSUInteger failCount = m.pinFailCount, i;

    if (failCount > 2) {
        uint32_t lastHeight = p.lastBlockHeight, failHeight = m.pinFailHeight,
                 wait = (failCount > 16) ? TX_MAX_LOCK_HEIGHT - lastHeight : pow(5, failCount - 4),
                 now = [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970;

        if (failHeight >= TX_MAX_LOCK_HEIGHT) wait = pow(5, failCount - 3)*60; // wait is in seconds instead of blocks

        if ((failHeight < TX_MAX_LOCK_HEIGHT && failHeight + wait > lastHeight) || failHeight + wait > now) { // locked
            if (p.estimatedBlockHeight > lastHeight) lastHeight = p.estimatedBlockHeight;
            if (failHeight < TX_MAX_LOCK_HEIGHT && failHeight > lastHeight) lastHeight = failHeight;

            uint32_t minutes = (failHeight < TX_MAX_LOCK_HEIGHT) ? (failHeight + wait - lastHeight)*10 :
                               (failHeight + wait + 59 - now)/60;
            uint32_t hours = minutes/60, days = hours/24;
            NSString *units = NSLocalizedString(@"minute", nil), *time, *s;
            NSMutableAttributedString *t = [[NSMutableAttributedString alloc]
                                            initWithAttributedString:self.lockLabel.attributedText];

            if (minutes > 1) units = NSLocalizedString(@"minutes", nil);
            if (hours == 1) units = NSLocalizedString(@"hour", nil);
            if (hours > 1) units = NSLocalizedString(@"hours", nil);
            if (days == 1) units = NSLocalizedString(@"day", nil);
            if (days > 1) units = NSLocalizedString(@"days", nil);
            time = [NSString stringWithFormat:@"%u %@", days ? days : (hours ? hours : minutes), units];

            if (failHeight < TX_MAX_LOCK_HEIGHT) {
                [[BRPeerManager sharedInstance] performSelector:@selector(connect) withObject:nil afterDelay:0.0];
                s = [NSString
                     stringWithFormat:NSLocalizedString(@"wallet disabled\n\ntry again after block #%u\n(about %@)",
                     nil), failHeight + wait, time];
            }
            else s = [NSString stringWithFormat:NSLocalizedString(@"wallet disabled\n\ntry again in %@", nil), time];

            i = [t.string rangeOfString:@"\n\n"].location + 2;
            [t replaceCharactersInRange:NSMakeRange(i, t.string.length - i)
             withString:[s substringFromIndex:[s rangeOfString:@"\n\n"].location + 2]];
            self.lockLabel.attributedText = t;
            [self.cancelButton setTitle:NSLocalizedString(@"reset pin", nil) forState:UIControlStateNormal];
            self.cancelButton.enabled = YES;
            [self.padButtons makeObjectsPerformSelector:@selector(setEnabled:) withObject:nil];

            if (self.lockLabel.hidden) {
                self.lockLabel.hidden = NO;
                self.lockLabel.alpha = 0.0;
                [UIView animateWithDuration:0.2 animations:^{ self.lockLabel.alpha = 1.0; }];
            }

            [self performSelector:@selector(checkLockout) withObject:nil afterDelay:10.0];
            return;
        }
    }

    // not locked
    if (self.pin.length > 0) return;

    if (! self.success) {
        if (m.pin.length == PIN_LENGTH) {
            self.titleLabel.text = (self.changePin) ? NSLocalizedString(@"enter current pin", nil) :
                                   NSLocalizedString(@"enter pin", nil);
        }
        else self.titleLabel.text = NSLocalizedString(@"choose a pin", nil);
    }

    [self.cancelButton setTitle:(self.cancelable && ! self.fail) ? NSLocalizedString(@"cancel", key) : @""
     forState:UIControlStateNormal];
    self.cancelButton.enabled = (self.cancelable && ! self.fail) ? YES : NO;

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
    if (self.pin.length >= PIN_LENGTH) return;
    [self.pin appendFormat:@"%C", [[sender currentAttributedTitle].string characterAtIndex:0]];

    BRWalletManager *m = [BRWalletManager sharedInstance];

    if (self.pin.length < PIN_LENGTH) {
        self.dotsLabel.text = DOT;

        for (NSUInteger i = 1; i < PIN_LENGTH; i++) {
            self.dotsLabel.text = [self.dotsLabel.text
                                   stringByAppendingString:(i < self.pin.length) ? @"  " DOT : @"  " CIRCLE];
        }

        if (! [self.cancelButton.currentTitle isEqual:NSLocalizedString(@"delete", nil)]) {
            [self.cancelButton setTitle:NSLocalizedString(@"delete", nil) forState:UIControlStateNormal];
            self.cancelButton.enabled = YES;
        }
    }
    else if (! self.success && [self.pin isEqual:m.pin]) { // successful pin attempt
        if (m.pinFailCount > 0) {
            m.pinFailCount = 0;
            m.pinFailHeight = 0;
        }

        _success = YES;
        self.fail = NO;
        self.dotsLabel.text = DOT @"  " DOT @"  " DOT @"  " DOT;

        if (self.changePin) {
            self.pin.string = @"";
            [self checkLockout];
            self.dotsXCenter.constant = -self.dotsLabel.bounds.size.width/2 - self.view.bounds.size.width/2;
            self.titleXCenter.constant = self.dotsXCenter.constant;

            [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
                [self.view layoutIfNeeded];
            } completion:^(BOOL finished) {
                self.titleLabel.text = NSLocalizedString(@"choose a pin", nil);
                self.dotsLabel.text = CIRCLE @"  " CIRCLE @"  " CIRCLE @"  " CIRCLE;
                self.dotsXCenter.constant = self.dotsLabel.bounds.size.width/2 + self.view.bounds.size.width/2;
                self.titleXCenter.constant = self.dotsXCenter.constant;
                [self.view layoutIfNeeded];
                self.dotsXCenter.constant = self.titleXCenter.constant = 0;

                [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
                 animations:^{ [self.view layoutIfNeeded]; } completion:nil];
            }];
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
            });
        }
    }
    else if (! self.success && m.pin.length == PIN_LENGTH) { // failed pin attempt
        if (! [self.badPins containsObject:self.pin]) {
            BRPeerManager *p = [BRPeerManager sharedInstance];

            [self.badPins addObject:self.pin];
            self.pin = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), PIN_LENGTH));
            m.pinFailCount++;

            if (m.pinFailCount > 3) {
                m.pinFailHeight =
                    (p.estimatedBlockHeight > p.lastBlockHeight && p.estimatedBlockHeight < TX_MAX_LOCK_HEIGHT) ?
                    p.estimatedBlockHeight : p.lastBlockHeight;
            }
            else m.pinFailHeight = [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970;
        }
        else self.pin.string = @"";

        self.fail = YES;
        [self checkLockout];
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
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
        [self checkLockout];
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
        [self checkLockout];
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
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
        m.pinFailCount = 0;
        m.pinFailHeight = 0;
        self.verifyPin = nil;
        self.dotsLabel.text = DOT @"  " DOT @"  " DOT @"  " DOT;

        UIViewController *p = self.navigationController.presentingViewController;

        dispatch_async(dispatch_get_main_queue(), ^{
            [p dismissViewControllerAnimated:YES completion:^{
                if (self.changePin) {
                    [p.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"pin changed", nil)
                                         center:CGPointMake(p.view.bounds.size.width/2, p.view.bounds.size.height/2)]
                                         popIn] popOutAfterDelay:2.0]];
                }
            }];
        });
    }
}

- (IBAction)cancel:(id)sender
{
    if (self.pin.length > 0) {
        [self.pin deleteCharactersInRange:NSMakeRange(self.pin.length - 1, 1)];
        self.dotsLabel.text = (self.pin.length > 0) ? DOT : CIRCLE;

        for (NSUInteger i = 1; i < PIN_LENGTH; i++) {
            self.dotsLabel.text = [self.dotsLabel.text
                                   stringByAppendingString:(i < self.pin.length) ? @"  " DOT : @"  " CIRCLE];
        }
    }

    if (self.pin.length > 0) return;

    if ([[sender currentTitle] isEqual:NSLocalizedString(@"delete", nil)]) {
        [sender setTitle:(self.cancelable && ! self.fail) ? NSLocalizedString(@"cancel", nil) : @""
         forState:UIControlStateNormal];
        [sender setEnabled:(self.cancelable && ! self.fail) ? YES : NO];
    }
    else if ([[sender currentTitle] isEqual:NSLocalizedString(@"reset pin", nil)]) {
        UIViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"PINResetController"];

        [self.navigationController pushViewController:c animated:YES];
    }
    else if (self.cancelable && ! self.fail) {
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

    if (from == self.navigationController) {
        //TODO: XXX try out different animations, maybe something where the numbers pop out one after the next
        to.view.frame = from.view.frame;
        [v insertSubview:to.view belowSubview:from.view];
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
        
        [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            from.view.alpha = 0.0;
            from.view.transform = CGAffineTransformMakeScale(0.75, 0.75);
        } completion:^(BOOL finished) {
            [from.view removeFromSuperview];
            [transitionContext completeTransition:finished];
        }];
    }
    else {
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
