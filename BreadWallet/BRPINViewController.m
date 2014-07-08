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
#import "NSString+Base58.h"

#define PIN_LENGTH 4
#define CIRCLE     @"\xE2\x97\x8B" // white (empty) circle, unicode U+25CB (utf-8)
#define DOT        @"\xE2\x97\x8F" // black (filled) circle, uincode U+25CF (utf-8)

@interface BRPINViewController ()

@property (nonatomic, strong) IBOutlet UILabel *titleLabel, *dotsLabel, *dipsLabel;
@property (nonatomic, strong) IBOutlet UIButton *cancelButton;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *logoXCenter, *titleXCenter, *dotsXCenter, *padXCenter,
                                                          *wallpaperX;

@property (nonatomic, strong) NSMutableString *pin;

@end

@implementation BRPINViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    if (! self.appeared) {
        self.titleXCenter.constant = self.dotsXCenter.constant = self.padXCenter.constant = self.view.bounds.size.width;
    }
    else {
        self.logoXCenter.constant = self.view.bounds.size.width;
        self.wallpaperX.constant = self.view.bounds.size.width*PARALAX_RATIO;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.pin = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), PIN_LENGTH));

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:NO];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (self.appeared) return;
    self.appeared = YES;

    dispatch_async(dispatch_get_main_queue(), ^{ // animation sometimes doesn't work if run directly in viewDidAppear
        [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];

        self.titleXCenter.constant = self.dotsXCenter.constant = self.padXCenter.constant = 0.0;
        self.logoXCenter.constant = self.view.bounds.size.width;
        self.wallpaperX.constant = self.view.bounds.size.width*PARALAX_RATIO;

        [UIView animateWithDuration:0.35 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
        animations:^{ [self.view layoutIfNeeded]; } completion:nil];
    });
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.pin = nil;

    [super viewWillDisappear:animated];
}

#pragma mark - IBAction

- (IBAction)number:(id)sender
{
    [sender setAlpha:0.15];
    [UIView animateWithDuration:0.35 animations:^{ [sender setAlpha:1.0]; }];

    if (self.pin.length >= PIN_LENGTH) return;
    [self.pin appendFormat:@"%C", [[sender currentAttributedTitle].string characterAtIndex:0]];

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

    if ([self.cancelButton.currentTitle isEqual:NSLocalizedString(@"cancel", nil)]) {
        [UIView animateWithDuration:0.15 animations:^{
            self.cancelButton.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self.cancelButton setTitle:NSLocalizedString(@"delete", nil) forState:UIControlStateNormal];
            [UIView animateWithDuration:0.15 animations:^{ self.cancelButton.alpha = 1.0; }];
        }];
    }

    if (self.pin.length == PIN_LENGTH) {
        // try pin
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
            [sender setTitle:NSLocalizedString(@"cancel", nil) forState:UIControlStateNormal];
            [UIView animateWithDuration:0.15 animations:^{ [sender setAlpha:1.0]; }];
        }];
    }
    else [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
