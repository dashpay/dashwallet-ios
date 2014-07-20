//
//  BRAmountViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 6/4/13.
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

#import "BRAmountViewController.h"
#import "BRPaymentRequest.h"
#import "BRWalletManager.h"
#import "BRWallet.h"
#import "BRPeerManager.h"
#import "BRTransaction.h"

@interface BRAmountViewController ()

@property (nonatomic, strong) IBOutlet UITextField *amountField;
@property (nonatomic, strong) IBOutlet UILabel *localCurrencyLabel, *addressLabel;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *payButton;
@property (nonatomic, strong) IBOutlet UIButton *delButton, *decimalButton;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;
@property (nonatomic, strong) id balanceObserver;
@property (nonatomic, strong) NSCharacterSet *charset;
@property (nonatomic, strong) UILabel *swapLeftLabel, *swapRightLabel;

@end

@implementation BRAmountViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSMutableCharacterSet *charset = [NSMutableCharacterSet decimalDigitCharacterSet];

    [charset addCharactersInString:m.format.currencyDecimalSeparator];
    self.charset = charset;

    self.amountField.placeholder = [m stringForAmount:0];
    [self.decimalButton setTitle:m.format.currencyDecimalSeparator forState:UIControlStateNormal];

    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if ([[BRPeerManager sharedInstance] syncProgress] < 1.0) return; // wait for sync before updating balance

            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                         [m localCurrencyStringForAmount:m.wallet.balance]];
        }];
}

- (void)dealloc
{
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    NSString *addr = self.request.paymentAddress;
    
    if (addr) self.addressLabel.text = [NSString stringWithFormat:NSLocalizedString(@"to: %@", nil), addr];
    self.wallpaper.hidden = NO;

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.request.amount = 0;
    self.wallpaper.hidden = animated;

    [super viewWillDisappear:animated];
}

- (UILabel *)swapLeftLabel
{
    if (! _swapLeftLabel) {
        _swapLeftLabel = [[UILabel alloc] initWithFrame:self.localCurrencyLabel.frame];
        _swapLeftLabel.text = self.localCurrencyLabel.text;
        _swapLeftLabel.textAlignment = NSTextAlignmentRight;
        _swapLeftLabel.lineBreakMode = NSLineBreakByClipping;
        _swapLeftLabel.font = self.localCurrencyLabel.font;
        _swapLeftLabel.textColor = self.localCurrencyLabel.textColor;
    }

    return _swapLeftLabel;
}

- (UILabel *)swapRightLabel
{
    if (! _swapRightLabel) {
        _swapRightLabel = [[UILabel alloc] initWithFrame:self.amountField.frame];
        _swapRightLabel.text = (self.amountField.text.length > 0) ? self.amountField.text : self.amountField.placeholder;
        _swapRightLabel.textAlignment = NSTextAlignmentLeft;
        _swapRightLabel.lineBreakMode = NSLineBreakByClipping;
        _swapRightLabel.font = self.amountField.font;
        _swapRightLabel.textColor = (self.amountField.text.length > 0) ? self.amountField.textColor :
                                 [UIColor colorWithWhite:0.75 alpha:1.0];
    }

    return _swapRightLabel;
}

- (void)updateLocalCurrencyLabel
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    uint64_t amount = [m amountForString:self.amountField.text];

    //self.localCurrencyLabel.hidden = (amount == 0) ? YES : NO;
    self.localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)", [m localCurrencyStringForAmount:amount]];
}

#pragma mark - IBAction

- (IBAction)number:(id)sender
{
    NSUInteger l = [self.amountField.text rangeOfCharacterFromSet:self.charset options:NSBackwardsSearch].location;

    l = (l < self.amountField.text.length) ? l + 1 : self.amountField.text.length;
    [self textField:self.amountField shouldChangeCharactersInRange:NSMakeRange(l, 0)
     replacementString:[(UIButton *)sender titleLabel].text];
}

- (IBAction)del:(id)sender
{
    NSUInteger l = [self.amountField.text rangeOfCharacterFromSet:self.charset options:NSBackwardsSearch].location;

    if (l < self.amountField.text.length) {
        [self textField:self.amountField shouldChangeCharactersInRange:NSMakeRange(l, 1) replacementString:@""];
    }
}

- (IBAction)pay:(id)sender
{
    self.request.amount = [[BRWalletManager sharedInstance] amountForString:self.amountField.text];

    if (self.request.amount == 0) return;
    
    [self.delegate amountViewController:self selectedAmount:self.request.amount];
}

- (IBAction)swapCurrency:(id)sender
{
    self.swapRightLabel.center = self.amountField.center;
    [self.amountField.superview addSubview:self.swapRightLabel];
    self.amountField.hidden = YES;

    self.swapLeftLabel.center = self.localCurrencyLabel.center;
    [self.localCurrencyLabel.superview addSubview:self.swapLeftLabel];
    self.localCurrencyLabel.hidden = YES;

    CGFloat scale = self.swapRightLabel.font.pointSize/self.swapLeftLabel.font.pointSize;
    CGPoint l = self.swapLeftLabel.center, r = self.swapRightLabel.center, c = CGPointMake(l.x/2 + r.x/2, l.y/2 + r.y/2);
    BRWalletManager *m = [BRWalletManager sharedInstance];
    uint64_t amount = [m amountForString:self.amountField.text];

    [UIView animateWithDuration:0.05 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.swapLeftLabel.transform = CGAffineTransformMakeScale(scale*1.25, scale*1.25);
        self.swapRightLabel.transform = CGAffineTransformMakeScale(0.75/scale, 0.75/scale);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.8 delay:0.0 usingSpringWithDamping:0.3 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseIn animations:^{
            self.swapLeftLabel.transform = CGAffineTransformMakeScale(scale, scale);
            self.swapRightLabel.transform = CGAffineTransformMakeScale(1.0/scale, 1.0/scale);
        } completion:nil];
    }];

    [UIView animateWithDuration:0.05 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.swapLeftLabel.center = self.swapRightLabel.center = c;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.8 delay:0.0 usingSpringWithDamping:0.3 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.swapLeftLabel.text = [m localCurrencyStringForAmount:amount];
            self.swapRightLabel.text = [NSString stringWithFormat:@"(%@)", [m stringForAmount:amount]];
            [self.swapLeftLabel sizeToFit];
            [self.swapRightLabel sizeToFit];

            self.swapLeftLabel.center = r;
            self.swapRightLabel.center = l;
        } completion:nil];
    }];
}

- (IBAction)pressSwapButton:(id)sender
{
    self.swapLeftLabel.center = self.localCurrencyLabel.center;
    [self.localCurrencyLabel.superview addSubview:self.swapLeftLabel];
    self.localCurrencyLabel.hidden = YES;

    [UIView animateWithDuration:0.1 animations:^{
        self.swapLeftLabel.transform = CGAffineTransformMakeScale(0.85, 0.85);
    }];
}

- (IBAction)releaseSwapButton:(id)sender
{
    [UIView animateWithDuration:0.1 animations:^{
        self.swapLeftLabel.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.swapLeftLabel.hidden = YES;
        self.localCurrencyLabel.hidden = NO;
    }];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSUInteger point = [textField.text rangeOfString:m.format.currencyDecimalSeparator].location, l;
    NSString *t = textField.text ? [textField.text stringByReplacingCharactersInRange:range withString:string] : string;

    t = [m.format stringFromNumber:[m.format numberFromString:t]];
    l = [textField.text rangeOfCharacterFromSet:self.charset options:NSBackwardsSearch].location;
    l = (l < textField.text.length) ? l + 1 : textField.text.length;

    if (! string.length && point != NSNotFound) { // delete trailing char
        t = [textField.text stringByReplacingCharactersInRange:range withString:string];
        if ([t isEqual:[m.format stringFromNumber:@0]]) t = @"";
    }
    else if ((string.length > 0 && textField.text.length > 0 && t == nil) ||
             (point != NSNotFound && l - point > m.format.maximumFractionDigits)) {
        return NO; // too many digits
    }
    else if ([string isEqual:m.format.currencyDecimalSeparator] && (! textField.text.length || point == NSNotFound)) {
        if (! textField.text.length) t = [m.format stringFromNumber:@0]; // if first char is '.', prepend a zero
        l = [t rangeOfCharacterFromSet:self.charset options:NSBackwardsSearch].location;
        l = (l < t.length) ? l + 1 : t.length;
        t = [t stringByReplacingCharactersInRange:NSMakeRange(l, 0) withString:m.format.currencyDecimalSeparator];
    }
    else if ([string isEqual:@"0"]) {
        if (! textField.text.length) { // if first digit is zero, append a '.'
            t = [m.format stringFromNumber:@0];
            l = [t rangeOfCharacterFromSet:self.charset options:NSBackwardsSearch].location;
            l = (l < t.length) ? l + 1 : t.length;
            t = [t stringByReplacingCharactersInRange:NSMakeRange(l, 0) withString:m.format.currencyDecimalSeparator];
        }
        else if (point != NSNotFound) { // handle multiple zeros after '.'
            t = [textField.text stringByReplacingCharactersInRange:NSMakeRange(l, 0) withString:@"0"];
        }
    }

    l = [t rangeOfCharacterFromSet:self.charset options:NSBackwardsSearch].location;
    l = (l < t.length) ? l + 1 : t.length;

    // don't allow values below TX_MIN_OUTPUT_AMOUNT
    if (t.length > 0 && [t rangeOfString:m.format.currencyDecimalSeparator].location != NSNotFound &&
        [m amountForString:[t stringByReplacingCharactersInRange:NSMakeRange(l, 0) withString:@"9"]] <
        TX_MIN_OUTPUT_AMOUNT) {
        return NO;
    }

    textField.text = t;
    if (t.length > 0 && textField.placeholder.length > 0) textField.placeholder = nil;
    if (t.length == 0 && textField.placeholder.length == 0) textField.placeholder = [m stringForAmount:0];
    //self.payButton.enabled = t.length ? YES : NO;
    [self updateLocalCurrencyLabel];

    return NO;
}

@end
