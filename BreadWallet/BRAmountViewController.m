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
#import "BRPeerManager.h"
#import "BRTransaction.h"
#import "BREventManager.h"
#import "NSString+Dash.h"
#import "BRBubbleView.h"

@interface BRAmountViewController ()

@property (nonatomic, strong) IBOutlet UILabel *localCurrencyLabel, *shapeshiftLocalCurrencyLabel, *addressLabel, *amountLabel;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *payButton, *lock;
@property (nonatomic, strong) IBOutlet UIButton *delButton, *decimalButton,*bottomButton;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;
@property (nonatomic, strong) IBOutlet UIView *logo;


@property (nonatomic, strong) BRBubbleView * tipView;

@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, strong) NSCharacterSet *charset;
@property (nonatomic, strong) UILabel *swapLeftLabel, *swapRightLabel;
@property (nonatomic, assign) BOOL swapped;
@property (nonatomic, assign) BOOL amountLabelIsEmpty;
@property (nonatomic, strong) id balanceObserver, backgroundObserver;

@end

@implementation BRAmountViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSMutableCharacterSet *charset = [NSMutableCharacterSet decimalDigitCharacterSet];
    
    [charset addCharactersInString:manager.dashFormat.currencyDecimalSeparator];
    self.charset = charset;
    
    self.payButton = [[UIBarButtonItem alloc] initWithTitle:self.usingShapeshift?@"Shapeshift!":NSLocalizedString(@"pay", nil)
                                                      style:UIBarButtonItemStylePlain target:self action:@selector(pay:)];
    self.payButton.tintColor = [UIColor colorWithRed:168.0/255.0 green:230.0/255.0 blue:1.0 alpha:1.0];
    self.amountLabel.attributedText = [manager attributedStringForDashAmount:0 withTintColor:[UIColor colorWithRed:25.0f/255.0f green:96.0f/255.0f blue:165.0f/255.0f alpha:1.0f] dashSymbolSize:CGSizeMake(15, 16)];
    self.amountLabel.textColor = [UIColor colorWithRed:25.0f/255.0f green:96.0f/255.0f blue:165.0f/255.0f alpha:1.0f];
    [self.decimalButton setTitle:manager.dashFormat.currencyDecimalSeparator forState:UIControlStateNormal];
    
    self.swapLeftLabel = [UILabel new];
    self.swapLeftLabel.font = self.localCurrencyLabel.font;
    self.swapLeftLabel.alpha = self.localCurrencyLabel.alpha;
    self.swapLeftLabel.textAlignment = self.localCurrencyLabel.textAlignment;
    self.swapLeftLabel.hidden = YES;
    
    self.swapRightLabel = [UILabel new];
    self.swapRightLabel.font = self.amountLabel.font;
    self.swapRightLabel.alpha = self.amountLabel.alpha;
    self.swapRightLabel.textAlignment = self.amountLabel.textAlignment;
    self.swapRightLabel.hidden = YES;
    
    self.amountLabelIsEmpty = TRUE;
    
    [self updateLocalCurrencyLabel];
    
    if (self.usingShapeshift) {
        [self swapCurrency:self];
    } else {
        self.shapeshiftLocalCurrencyLabel.text = @"";
    }
    self.shapeshiftLocalCurrencyLabel.hidden = !self.usingShapeshift;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.usingShapeshift) {
        self.addressLabel.text = (self.to.length > 0) ?
        [NSString stringWithFormat:NSLocalizedString(@"to: %@ (via Shapeshift)", nil), self.to] : nil;
    } else {
        self.addressLabel.text = (self.to.length > 0) ?
        [NSString stringWithFormat:NSLocalizedString(@"to: %@", nil), self.to] : nil;
    }
    self.wallpaper.hidden = NO;
    
    if (self.navigationController.viewControllers.firstObject != self) {
        self.navigationItem.leftBarButtonItem = nil;
        if ([[BRWalletManager sharedInstance] didAuthenticate]) [self unlock:nil];
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
        [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    }
    else {
        self.payButton.title = NSLocalizedString(@"request", nil);
        self.payButton.tintColor = [UIColor colorWithRed:0.0 green:96.0/255.0 blue:1.0 alpha:1.0];
        self.navigationItem.rightBarButtonItem = self.payButton;
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault];
        [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    }
    
    self.balanceObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
                                                      if ([BRPeerManager sharedInstance].syncProgress < 1.0) return; // wait for sync before updating balance
                                                      
                                                      [self updateTitleView];
                                                  }];
    
    self.backgroundObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           self.navigationItem.titleView = self.logo;
                                                           [self.navigationItem setRightBarButtonItem:self.lock animated:NO];
                                                       }];
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.amount = 0;
    if (self.navigationController.viewControllers.firstObject != self) self.wallpaper.hidden = animated;
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    self.balanceObserver = nil;
    self.backgroundObserver = nil;
    [super viewWillDisappear:animated];
}

- (void)updateLocalCurrencyLabel
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    uint64_t amount;
    if (self.usingShapeshift) {
        amount = (self.swapped) ? [manager amountForBitcoinCurrencyString:self.amountLabel.text] * 1.02:
        [manager amountForDashString:self.amountLabel.text] * .98;
        if (amount) amount += (self.swapped) ?1.0/[[manager localCurrencyDashPrice] floatValue] * pow(10.0, manager.dashFormat.maximumFractionDigits):1.0/[[manager localCurrencyBitcoinPrice] floatValue] * pow(10.0, manager.bitcoinFormat.maximumFractionDigits);
    } else {
        amount = (self.swapped) ? [manager amountForLocalCurrencyString:self.amountLabel.text] :
        [manager amountForDashString:self.amountLabel.text];
    }
    
    self.swapLeftLabel.hidden = YES;
    self.localCurrencyLabel.hidden = NO;
    if (self.usingShapeshift) {
        
        NSMutableAttributedString * attributedString = [[NSMutableAttributedString alloc] initWithString:@"(~"];
        if (self.swapped) {
            [attributedString appendAttributedString:[manager attributedStringForDashAmount:amount withTintColor:(amount > 0) ? [UIColor grayColor] : [UIColor colorWithWhite:0.75 alpha:1.0] dashSymbolSize:CGSizeMake(11, 12)]];
        } else {
            [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[manager bitcoinCurrencyStringForAmount:amount]]];
        }
        [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@")"]];
        self.localCurrencyLabel.attributedText = attributedString;
    } else {
        NSMutableAttributedString * attributedString = [[NSMutableAttributedString alloc] initWithString:@"("];
        if (self.swapped) {
            [attributedString appendAttributedString:[manager attributedStringForDashAmount:amount withTintColor:(amount > 0) ? [UIColor grayColor] : [UIColor colorWithWhite:0.75 alpha:1.0] dashSymbolSize:CGSizeMake(11, 12)]];
        } else {
            [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[manager localCurrencyStringForDashAmount:amount]]];
        }
        [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@")"]];
        self.localCurrencyLabel.attributedText = attributedString;
    }
    self.localCurrencyLabel.textColor = (amount > 0) ? [UIColor grayColor] : [UIColor colorWithWhite:0.75 alpha:1.0];
    
    if (self.usingShapeshift) {
        self.shapeshiftLocalCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",[manager localCurrencyStringForDashAmount:amount]];
    }
}

-(UILabel*)titleLabel {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    UILabel * titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 1, 200)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [titleLabel setBackgroundColor:[UIColor clearColor]];
    NSMutableAttributedString * attributedDashString = [[manager attributedStringForDashAmount:manager.wallet.balance withTintColor:[UIColor whiteColor] useSignificantDigits:TRUE] mutableCopy];
    NSString * titleString = [NSString stringWithFormat:@" (%@)",
                              [manager localCurrencyStringForDashAmount:manager.wallet.balance]];
    [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
    titleLabel.attributedText = attributedDashString;
    return titleLabel;
}

-(void)updateTitleView {
    if (self.navigationItem.titleView && [self.navigationItem.titleView isKindOfClass:[UILabel class]]) {
        BRWalletManager *manager = [BRWalletManager sharedInstance];
        NSMutableAttributedString * attributedDashString = [[manager attributedStringForDashAmount:manager.wallet.balance withTintColor:[UIColor whiteColor]] mutableCopy];
        NSString * titleString = [NSString stringWithFormat:@" (%@)",
                                  [manager localCurrencyStringForDashAmount:manager.wallet.balance]];
        [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
        ((UILabel*)self.navigationItem.titleView).attributedText = attributedDashString;
        [((UILabel*)self.navigationItem.titleView) sizeToFit];
    } else {
        self.navigationItem.titleView = [self titleLabel];
    }
}

// MARK: - IBAction

- (IBAction)unlock:(id)sender
{
    if (self.tipView) {
        [self.tipView popOut];
        self.tipView = nil;
    }
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    [BREventManager saveEvent:@"amount:unlock"];
    
    if (sender && ! manager.didAuthenticate && ! [manager authenticateWithPrompt:nil andTouchId:YES]) return;
    [BREventManager saveEvent:@"amount:successful_unlock"];
    
    [self updateTitleView];
    [self.navigationItem setRightBarButtonItem:self.payButton animated:(sender) ? YES : NO];
}

- (IBAction)number:(id)sender
{
    if (self.tipView) {
        [self.tipView popOut];
        self.tipView = nil;
    }
    NSUInteger l = [self.amountLabel.text rangeOfCharacterFromSet:self.charset options:NSBackwardsSearch].location;
    
    l = (l < self.amountLabel.text.length) ? l + 1 : self.amountLabel.text.length;
    [self updateAmountLabel:self.amountLabel shouldChangeCharactersInRange:NSMakeRange(l, 0)
          replacementString:[(UIButton *)sender titleLabel].text];
}

- (IBAction)del:(id)sender
{
    if (self.tipView) {
        [self.tipView popOut];
        self.tipView = nil;
    }
    NSUInteger l = [self.amountLabel.text rangeOfCharacterFromSet:self.charset options:NSBackwardsSearch].location;
    
    if (l < self.amountLabel.text.length) {
        [self updateAmountLabel:self.amountLabel shouldChangeCharactersInRange:NSMakeRange(l, 1) replacementString:@""];
    }
}

- (IBAction)pay:(id)sender
{
    if (self.tipView) {
        [self.tipView popOut];
        self.tipView = nil;
    }
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    if (self.usingShapeshift) {
        
        self.amount = (self.swapped) ? [manager amountForBitcoinString:self.amountLabel.text]:
        [manager amountForDashString:self.amountLabel.text];
        
        if (self.amount == 0){
            [BREventManager saveEvent:@"amount:pay_zero"];
            return;
        }
        
        [BREventManager saveEvent:@"amount:pay_using_shapeshift"];
        
        if (self.swapped) {
            [self.delegate amountViewController:self shapeshiftBitcoinAmount:self.amount approximateDashAmount:self.amount/manager.bitcoinDashPrice.doubleValue];
        } else
            [self.delegate amountViewController:self shapeshiftDashAmount:self.amount];
    }else {
        self.amount = (self.swapped) ? [manager amountForLocalCurrencyString:self.amountLabel.text] :
        [manager amountForDashString:self.amountLabel.text];
        
        if (self.amount == 0){
            [BREventManager saveEvent:@"amount:pay_zero"];
            return;
        }
        
        [BREventManager saveEvent:@"amount:pay"];
        
        [self.delegate amountViewController:self selectedAmount:self.amount];
    }
}

- (IBAction)done:(id)sender
{
    [BREventManager saveEvent:@"amount:dismiss"];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)swapCurrency:(id)sender
{
    self.swapped = ! self.swapped;
    [BREventManager saveEvent:@"amount:swap_currency"];
    
    if (self.swapLeftLabel.hidden) {
        self.swapLeftLabel.text = self.localCurrencyLabel.text;
        self.swapLeftLabel.textColor = (self.amountLabel.text.length > 0) ? self.amountLabel.textColor :
        [UIColor colorWithWhite:0.75 alpha:1.0];
        self.swapLeftLabel.frame = self.localCurrencyLabel.frame;
        [self.localCurrencyLabel.superview addSubview:self.swapLeftLabel];
        self.swapLeftLabel.hidden = NO;
        self.localCurrencyLabel.hidden = YES;
    }
    
    if (self.swapRightLabel.hidden) {
        self.swapRightLabel.attributedText = self.amountLabel.attributedText;
        self.swapRightLabel.textColor = (self.amountLabel.text.length > 0) ? self.amountLabel.textColor :
        [UIColor colorWithWhite:0.75 alpha:1.0];
        self.swapRightLabel.frame = self.amountLabel.frame;
        [self.amountLabel.superview addSubview:self.swapRightLabel];
        self.swapRightLabel.hidden = NO;
        self.amountLabel.hidden = YES;
    }
    
    CGFloat scale = self.swapRightLabel.font.pointSize/self.swapLeftLabel.font.pointSize;
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSString *s = (self.swapped) ? self.localCurrencyLabel.text : self.amountLabel.text;
    uint64_t amount =
    [manager amountForLocalCurrencyString:(self.swapped) ? [s substringWithRange:NSMakeRange(1, s.length - 2)] : s];
    if (self.usingShapeshift) {
        
        NSMutableAttributedString * attributedString = [[NSMutableAttributedString alloc] initWithString:@"(~"];
        if (self.swapped) {
            [attributedString appendAttributedString:[manager attributedStringForDashAmount:amount withTintColor:self.localCurrencyLabel.textColor dashSymbolSize:CGSizeMake(11, 12)]];
        } else {
            [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[manager bitcoinCurrencyStringForAmount:amount]]];
        }
        [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@")"]];
        self.localCurrencyLabel.attributedText = attributedString;
        self.amountLabel.attributedText = (self.swapped) ? [[NSAttributedString alloc] initWithString:[manager bitcoinCurrencyStringForAmount:amount]]:[manager attributedStringForDashAmount:amount withTintColor:self.amountLabel.textColor dashSymbolSize:CGSizeMake(15, 16)];
    } else {
        NSMutableAttributedString * attributedString = [[NSMutableAttributedString alloc] initWithString:@"("];
        if (self.swapped) {
            [attributedString appendAttributedString:[manager attributedStringForDashAmount:amount withTintColor:self.localCurrencyLabel.textColor dashSymbolSize:CGSizeMake(11, 12)]];
        } else {
            [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[manager localCurrencyStringForDashAmount:amount]]];
        }
        [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@")"]];
        self.localCurrencyLabel.attributedText = attributedString;
        self.amountLabel.attributedText = (self.swapped) ? [[NSAttributedString alloc] initWithString:[manager localCurrencyStringForDashAmount:amount]]:[manager attributedStringForDashAmount:amount withTintColor:self.amountLabel.textColor dashSymbolSize:CGSizeMake(15, 16)];
    }
    
    [self.view layoutIfNeeded];
    
    CGPoint p = CGPointMake(self.localCurrencyLabel.frame.origin.x + self.localCurrencyLabel.bounds.size.width/2.0 +
                            self.amountLabel.bounds.size.width/2.0,
                            self.localCurrencyLabel.center.y/2.0 + self.amountLabel.center.y/2.0);
    
    [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.swapLeftLabel.transform = CGAffineTransformMakeScale(scale/0.85, scale/0.85);
        self.swapRightLabel.transform = CGAffineTransformMakeScale(0.85/scale, 0.85/scale);
    } completion:nil];
    
    [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.swapLeftLabel.center = self.swapRightLabel.center = p;
    } completion:^(BOOL finished) {
        self.swapLeftLabel.transform = CGAffineTransformMakeScale(0.85, 0.85);
        self.swapRightLabel.transform = CGAffineTransformMakeScale(1.0/0.85, 1.0/0.85);
        self.swapLeftLabel.attributedText = self.localCurrencyLabel.attributedText;
        self.swapRightLabel.attributedText = self.amountLabel.attributedText;
        self.swapLeftLabel.textColor = self.localCurrencyLabel.textColor;
        self.swapRightLabel.textColor = (self.amountLabel.text.length > 0) ? self.amountLabel.textColor :
        [UIColor colorWithWhite:0.75 alpha:1.0];
        [self.swapLeftLabel sizeToFit];
        [self.swapRightLabel sizeToFit];
        self.swapLeftLabel.center = self.swapRightLabel.center = p;
        
        [UIView animateWithDuration:0.7 delay:0.0 usingSpringWithDamping:0.5 initialSpringVelocity:0.0
                            options:UIViewAnimationOptionCurveEaseIn animations:^{
                                self.swapLeftLabel.transform = CGAffineTransformIdentity;
                                self.swapRightLabel.transform = CGAffineTransformIdentity;
                            } completion:nil];
        
        [UIView animateWithDuration:0.7 delay:0.0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0
                            options:UIViewAnimationOptionCurveEaseOut animations:^{
                                self.swapLeftLabel.frame = self.localCurrencyLabel.frame;
                                self.swapRightLabel.frame = self.amountLabel.frame;
                            } completion:nil];
    }];
    
    if (self.usingShapeshift) {
        self.shapeshiftLocalCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",[manager localCurrencyStringForDashAmount:0]];
    }
}

- (IBAction)releaseSwapButton:(id)sender
{
    [BREventManager saveEvent:@"amount:release_swap"];
    [UIView animateWithDuration:0.1 animations:^{
        //self.swapLeftLabel.transform = CGAffineTransformIdentity;
        self.swapLeftLabel.textColor = self.localCurrencyLabel.textColor;
    } completion:^(BOOL finished) {
        self.swapLeftLabel.hidden = self.swapRightLabel.hidden = YES;
        self.localCurrencyLabel.hidden = self.amountLabel.hidden = NO;
    }];
}

-(IBAction)clickedBottomBar:(id)sender
{
    if (self.tipView) {
        [self.tipView popOut];
        self.tipView = nil;
    } else {
        BRBubbleView * tipView = [BRBubbleView viewWithText:self.to
                                                   tipPoint:CGPointMake(self.bottomButton.center.x, self.bottomButton.center.y - 10.0)
                                               tipDirection:BRBubbleTipDirectionDown];
        tipView.font = [UIFont systemFontOfSize:15.0];
        tipView.userInteractionEnabled = YES;
        [self.view addSubview:[tipView popIn]];
        self.tipView = tipView;
    }
}

// MARK: - UITextFieldDelegate

-(void)updateAmountLabel:(UILabel *)amountLabel shouldChangeCharactersInRange:(NSRange)range
       replacementString:(NSString *)string
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSNumberFormatter *formatter;
    if (self.usingShapeshift) {
        formatter = (self.swapped) ? m.bitcoinFormat:m.dashFormat;
    } else {
        formatter = (self.swapped) ? m.localFormat:m.dashFormat;
    }
    NSNumberFormatter *basicFormatter = m.unknownFormat;
    NSUInteger minDigits = formatter.minimumFractionDigits;
    
    formatter.minimumFractionDigits = 0;
    
    NSString * previousString = amountLabel.text;
    if (!self.swapped) {
        NSInteger dashCharPos = [previousString indexOfCharacter:NSAttachmentCharacter];
        if (dashCharPos != NSNotFound) {
            previousString = [previousString stringByReplacingCharactersInRange:NSMakeRange(dashCharPos, 1) withString:DASH];
        }
        
    }
    
    NSUInteger digitLocationOld = [previousString rangeOfString:formatter.currencyDecimalSeparator].location;
    
    NSNumber * inputNumber = [formatter numberFromString:string];
    
    NSNumber * previousNumber = [formatter numberFromString:previousString];
    NSString *formattedAmount;
    NSString *formattedAmountForDigit;
    
    if (!self.amountLabelIsEmpty) {
        if (![previousNumber floatValue] && digitLocationOld == NSNotFound && !([formatter.currencyDecimalSeparator isEqualToString:string])) {
            formattedAmount = [formatter stringFromNumber:inputNumber];
        } else {
            formattedAmount = [amountLabel.text stringByReplacingCharactersInRange:range withString:string];
            formattedAmountForDigit = [amountLabel.text stringByReplacingCharactersInRange:range withString:@"1"];
        }
    } else {
        if ([formatter.currencyDecimalSeparator isEqualToString:string]) {
            if (digitLocationOld != NSNotFound) { //0,00 Euros
                NSUInteger locationOfCurrencySymbol = [previousString rangeOfString:formatter.currencySymbol].location;
                if (locationOfCurrencySymbol > digitLocationOld) {
                    formattedAmount = [NSString stringWithFormat:@"0%@ %@",formatter.currencyDecimalSeparator,formatter.currencySymbol];
                } else {
                    formattedAmount = [NSString stringWithFormat:@"%@ 0%@",formatter.currencySymbol,formatter.currencyDecimalSeparator];
                }
            } else {
                formattedAmount = [amountLabel.text stringByReplacingCharactersInRange:range withString:string];
            }
        } else {
            formattedAmount = [formatter stringFromNumber:inputNumber];
        }
    }
    if (!self.swapped) {
        NSInteger dashCharPos = [formattedAmount indexOfCharacter:NSAttachmentCharacter];
        if (dashCharPos != NSNotFound) {
            formattedAmount = [formattedAmount stringByReplacingCharactersInRange:NSMakeRange(dashCharPos, 1) withString:DASH];
        }
        if (formattedAmountForDigit) {
            NSInteger dashCharPosForDigit = [formattedAmountForDigit indexOfCharacter:NSAttachmentCharacter];
            if (dashCharPosForDigit != NSNotFound) {
                formattedAmountForDigit = [formattedAmountForDigit stringByReplacingCharactersInRange:NSMakeRange(dashCharPosForDigit, 1) withString:DASH];
            }
        }
    }
    NSNumber * currentNumber = [formatter numberFromString:formattedAmount];
    if (!formattedAmountForDigit) formattedAmountForDigit = formattedAmount;
    NSNumber * epsilonNumber = [formatter numberFromString:formattedAmountForDigit];
    basicFormatter.maximumFractionDigits++;
    NSString * basicFormattedAmount = [basicFormatter stringFromNumber:epsilonNumber]; //without the DASH symbol
    NSUInteger digitLocationNewBasicFormatted = [basicFormattedAmount rangeOfString:basicFormatter.currencyDecimalSeparator].location;
    basicFormatter.maximumFractionDigits--;
    NSUInteger digits = 0;
    
    if (digitLocationNewBasicFormatted != NSNotFound) {
        digits = basicFormattedAmount.length - digitLocationNewBasicFormatted - 1;
    }
    NSNumber * number = [formatter numberFromString:formattedAmount];
    
    formatter.minimumFractionDigits = minDigits;
    
    
    NSUInteger digitLocationNew = [formattedAmount rangeOfString:formatter.currencyDecimalSeparator].location;
    
    //special cases
    if (! string.length) { // delete trailing char
        if (![number floatValue] && (!formattedAmount || digitLocationNew == NSNotFound)) { // there is no decimal
            self.amountLabelIsEmpty = TRUE;
            formattedAmount = [formatter stringFromNumber:@0];
        }
    }
    else if (digits > formatter.maximumFractionDigits) { //can't send too small a value
        return; // too many digits
    } else if (currentNumber && ![currentNumber floatValue] && inputNumber && ![inputNumber floatValue] && digitLocationNew && ([[formattedAmount componentsSeparatedByString:@"0"] count] > formatter.maximumFractionDigits + 2)) { //current number is 0, inputing a 0
        return;
    }
    else if (!self.amountLabelIsEmpty && [string isEqualToString:formatter.currencyDecimalSeparator]) {  //adding a digit
        if (digitLocationOld != NSNotFound) {
            return;
        }
        self.amountLabelIsEmpty = FALSE;
    } else {
        self.amountLabelIsEmpty = FALSE;
    }
    
    if (!self.amountLabelIsEmpty) {
        if (![formatter numberFromString:formattedAmount]) return;
    }
    
    if (formattedAmount.length == 0 || self.amountLabelIsEmpty) { // ""
        if (self.usingShapeshift) {
            amountLabel.attributedText = (self.swapped) ? [[NSAttributedString alloc] initWithString:[m bitcoinCurrencyStringForAmount:0]]:[m attributedStringForDashAmount:0 withTintColor:[UIColor colorWithRed:25.0f/255.0f green:96.0f/255.0f blue:165.0f/255.0f alpha:1.0f] dashSymbolSize:CGSizeMake(15, 16)];
        } else {
            amountLabel.attributedText = (self.swapped) ? [[NSAttributedString alloc] initWithString:[m localCurrencyStringForDashAmount:0]]:[m attributedStringForDashAmount:0 withTintColor:[UIColor colorWithRed:25.0f/255.0f green:96.0f/255.0f blue:165.0f/255.0f alpha:1.0f] dashSymbolSize:CGSizeMake(15, 16)];
        }
        amountLabel.textColor = [UIColor colorWithRed:25.0f/255.0f green:96.0f/255.0f blue:165.0f/255.0f alpha:1.0f];
    } else {
        if (!self.swapped) {
            amountLabel.textColor = [UIColor blackColor];
            amountLabel.attributedText = [formattedAmount attributedStringForDashSymbolWithTintColor:self.amountLabel.textColor dashSymbolSize:CGSizeMake(15, 16)];
        } else {
            amountLabel.textColor = [UIColor blackColor];
            amountLabel.text = formattedAmount;
        }
    }
    
    if (self.navigationController.viewControllers.firstObject != self) {
        if (! m.didAuthenticate && (formattedAmount.length == 0 || self.amountLabelIsEmpty || ![number floatValue]) && self.navigationItem.rightBarButtonItem != self.lock) {
            [self.navigationItem setRightBarButtonItem:self.lock animated:YES];
        }
        else if ((formattedAmount.length > 0 && !self.amountLabelIsEmpty && [number floatValue]) && self.navigationItem.rightBarButtonItem != self.payButton) {
            [self.navigationItem setRightBarButtonItem:self.payButton animated:YES];
        }
    }
    
    self.swapRightLabel.hidden = YES;
    amountLabel.hidden = NO;
    [self updateLocalCurrencyLabel];
}

@end
