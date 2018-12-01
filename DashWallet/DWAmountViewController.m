//
//  DWAmountViewController.m
//  DashWallet
//
//  Created by Aaron Voisine for BreadWallet on 6/4/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Copyright (c) 2018 Dash Core Group <contact@dash.org>
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

#import "DWAmountViewController.h"
#import "BRBubbleView.h"

#define GRAY80_COLOR [UIColor colorWithWhite:0.80 alpha:1.0]
#define OFFWHITE_COLOR [UIColor colorWithWhite:0.95 alpha:1.0]
#define OFFBLUE_COLOR [UIColor colorWithRed:25.0f/255.0f green:96.0f/255.0f blue:165.0f/255.0f alpha:1.0f]

@interface DWAmountViewController ()

@property (nonatomic, strong) IBOutlet UILabel *localCurrencyLabel, *shapeshiftLocalCurrencyLabel, *addressLabel, *amountLabel;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *payButton, *lock;
@property (nonatomic, strong) IBOutlet UIButton *delButton, *decimalButton,*bottomButton;
@property (nonatomic, strong) IBOutlet UIView *logo;


@property (nonatomic, strong) BRBubbleView * tipView;

@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, strong) NSCharacterSet *charset;
@property (nonatomic, strong) UILabel *swapLeftLabel, *swapRightLabel;
@property (nonatomic, assign) BOOL swapped;
@property (nonatomic, assign) BOOL amountLabelIsEmpty;
@property (nonatomic, strong) id balanceObserver, backgroundObserver;

@end

@implementation DWAmountViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    NSMutableCharacterSet *charset = [NSMutableCharacterSet decimalDigitCharacterSet];
    
    [charset addCharactersInString:priceManager.dashFormat.currencyDecimalSeparator];
    self.charset = charset;
    
    self.payButton = [[UIBarButtonItem alloc] initWithTitle:self.usingShapeshift?NSLocalizedString(@"Shapeshift!",nil):NSLocalizedString(@"Pay", nil)
                                                      style:UIBarButtonItemStylePlain target:self action:@selector(pay:)];
    self.payButton.tintColor = [UIColor colorWithRed:168.0/255.0 green:230.0/255.0 blue:1.0 alpha:1.0];
    self.amountLabel.attributedText = [priceManager attributedStringForDashAmount:0 withTintColor:OFFBLUE_COLOR dashSymbolSize:CGSizeMake(15, 16)];
    self.amountLabel.textColor = OFFBLUE_COLOR;
    [self.decimalButton setTitle:priceManager.dashFormat.currencyDecimalSeparator forState:UIControlStateNormal];
    
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

-(BOOL)prefersStatusBarHidden {
    return NO;
}

-(UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
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
    
    if (!self.requestingAmount) {
        if ([[DSAuthenticationManager sharedInstance] didAuthenticate]) [self unlock:nil];
    }
    else {
        self.payButton.title = NSLocalizedString(@"Request", nil);
        self.payButton.tintColor = [UIColor whiteColor];
        self.navigationItem.rightBarButtonItem = self.payButton;
    }
    
    self.balanceObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:DSWalletBalanceDidChangeNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
                                                      if ([DWEnvironment sharedInstance].currentChainManager.syncProgress < 1.0) return; // wait for sync before updating balance
                                                      if ([[DSAuthenticationManager sharedInstance] didAuthenticate]) {
                                                          [self updateTitleView];
                                                      }
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
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    self.balanceObserver = nil;
    self.backgroundObserver = nil;
    [super viewWillDisappear:animated];
}

- (void)updateLocalCurrencyLabel
{
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    uint64_t amount = 0;
    if (self.usingShapeshift) {
#if SHAPESHIFT_ENABLED
        amount = (self.swapped) ? [priceManager amountForBitcoinCurrencyString:self.amountLabel.text] * 1.02:
        [priceManager amountForDashString:self.amountLabel.text] * .98;
        if (amount) amount += (self.swapped) ?1.0/[[priceManager localCurrencyDashPrice] floatValue] * pow(10.0, priceManager.dashFormat.maximumFractionDigits):1.0/[[priceManager localCurrencyBitcoinPrice] floatValue] * pow(10.0, priceManager.bitcoinFormat.maximumFractionDigits);
#endif
    } else {
        amount = (self.swapped) ? [priceManager amountForLocalCurrencyString:self.amountLabel.text] :
        [priceManager amountForDashString:self.amountLabel.text];
    }
    
    self.swapLeftLabel.hidden = YES;
    self.localCurrencyLabel.hidden = NO;
    if (self.usingShapeshift) {
#if SHAPESHIFT_ENABLED
        NSMutableAttributedString * attributedString = [[NSMutableAttributedString alloc] initWithString:@"(~"];
        if (self.swapped) {
            [attributedString appendAttributedString:[priceManager attributedStringForDashAmount:amount withTintColor:(amount > 0) ? GRAY80_COLOR : OFFBLUE_COLOR dashSymbolSize:CGSizeMake(11, 12)]];
        } else {
            [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[priceManager bitcoinCurrencyStringForAmount:amount]]];
        }
        [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@")"]];
        self.localCurrencyLabel.attributedText = attributedString;
#endif
    } else {
        NSMutableAttributedString * attributedString = [[NSMutableAttributedString alloc] initWithString:@"("];
        if (self.swapped) {
            [attributedString appendAttributedString:[priceManager attributedStringForDashAmount:amount withTintColor:(amount > 0) ? GRAY80_COLOR : OFFBLUE_COLOR dashSymbolSize:CGSizeMake(11, 12)]];
        } else {
            [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[priceManager localCurrencyStringForDashAmount:amount]]];
        }
        [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@")"]];
        self.localCurrencyLabel.attributedText = attributedString;
    }
    self.localCurrencyLabel.textColor = (amount > 0) ? GRAY80_COLOR : OFFBLUE_COLOR;
    
    if (self.usingShapeshift) {
        self.shapeshiftLocalCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",[priceManager localCurrencyStringForDashAmount:amount]];
    }
}

-(UIButton*)titleButton {
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
    UIButton * titleButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 1, 200)];
    titleButton.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [titleButton setBackgroundColor:[UIColor clearColor]];
    NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:wallet.balance withTintColor:[UIColor whiteColor] useSignificantDigits:TRUE] mutableCopy];
    NSString * titleString = [NSString stringWithFormat:@" (%@)",
                              [priceManager localCurrencyStringForDashAmount:wallet.balance]];
    [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
    [titleButton setAdjustsImageWhenHighlighted:NO];
    [titleButton setAttributedTitle:attributedDashString forState:UIControlStateNormal];
    [titleButton addTarget:self action:@selector(chooseToSendAllFunds:) forControlEvents:UIControlEventTouchUpInside];
    return titleButton;
}

-(void)updateTitleView {
    if (self.navigationItem.titleView && [self.navigationItem.titleView isKindOfClass:[UIButton class]]) {
        DSPriceManager * priceManager = [DSPriceManager sharedInstance];
        DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
        NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:wallet.balance withTintColor:[UIColor whiteColor]] mutableCopy];
        NSString * titleString = [NSString stringWithFormat:@" (%@)",
                                  [priceManager localCurrencyStringForDashAmount:wallet.balance]];
        [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
        [((UIButton*)self.navigationItem.titleView) setAttributedTitle:attributedDashString forState:UIControlStateNormal];
        [((UIButton*)self.navigationItem.titleView) sizeToFit];
    } else {
        self.navigationItem.titleView = [self titleButton];
    }
}

// MARK: - IBAction

- (void)chooseToSendAllFunds:(id)sender {
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
    if (self.amountLabelIsEmpty) {
        NSString * amountString = [priceManager stringForDashAmount:wallet.balance];
        [self updateAmountLabel:self.amountLabel shouldChangeCharactersInRange:NSMakeRange(1, 0)
          replacementString:amountString];
    }
}

- (IBAction)unlock:(id)sender
{
    if (self.tipView) {
        [self.tipView popOut];
        self.tipView = nil;
    }
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    [DSEventManager saveEvent:@"amount:unlock"];
    
    if (sender && ! authenticationManager.didAuthenticate) {
        [authenticationManager authenticateWithPrompt:nil andTouchId:YES alertIfLockout:YES completion:^(BOOL authenticated,BOOL cancelled) {
            if (authenticated) {
                [DSEventManager saveEvent:@"amount:successful_unlock"];
                
                [self updateTitleView];
                [self.navigationItem setRightBarButtonItem:self.payButton animated:(sender) ? YES : NO];
            }
        }];
    } else if (authenticationManager.didAuthenticate) {
        [self updateTitleView];
        [self.navigationItem setRightBarButtonItem:self.payButton animated:(sender) ? YES : NO];
    }

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
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    if (self.usingShapeshift) {
#if SHAPESHIFT_ENABLED
        self.amount = (self.swapped) ? [priceManager amountForBitcoinString:self.amountLabel.text]:
        [priceManager amountForDashString:self.amountLabel.text];
        
        if (self.amount == 0){
            [DSEventManager saveEvent:@"amount:pay_zero"];
            return;
        }
        
        [DSEventManager saveEvent:@"amount:pay_using_shapeshift"];
        
        if (self.swapped) {
            [self.delegate amountViewController:self shapeshiftBitcoinAmount:self.amount approximateDashAmount:self.amount/priceManager.bitcoinDashPrice.doubleValue];
        } else
            [self.delegate amountViewController:self shapeshiftDashAmount:self.amount];
#endif
    }else {
        self.amount = (self.swapped) ? [priceManager amountForLocalCurrencyString:self.amountLabel.text] :
        [priceManager amountForDashString:self.amountLabel.text];
        
        if (self.amount == 0){
            [DSEventManager saveEvent:@"amount:pay_zero"];
            return;
        }
        
        [DSEventManager saveEvent:@"amount:pay"];
        
        [self.delegate amountViewController:self selectedAmount:self.amount];
    }
}

- (IBAction)done:(id)sender
{
    [DSEventManager saveEvent:@"amount:dismiss"];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)swapCurrency:(id)sender
{
    self.swapped = ! self.swapped;
    [DSEventManager saveEvent:@"amount:swap_currency"];
    
    if (self.swapLeftLabel.hidden) {
        self.swapLeftLabel.text = self.localCurrencyLabel.text;
        self.swapLeftLabel.textColor = (self.amountLabel.text.length > 0) ? self.amountLabel.textColor :
        OFFBLUE_COLOR;
        self.swapLeftLabel.frame = self.localCurrencyLabel.frame;
        [self.localCurrencyLabel.superview addSubview:self.swapLeftLabel];
        self.swapLeftLabel.hidden = NO;
        self.localCurrencyLabel.hidden = YES;
    }
    
    if (self.swapRightLabel.hidden) {
        self.swapRightLabel.attributedText = self.amountLabel.attributedText;
        self.swapRightLabel.textColor = (self.amountLabel.text.length > 0) ? self.amountLabel.textColor :
        OFFBLUE_COLOR;
        self.swapRightLabel.frame = self.amountLabel.frame;
        [self.amountLabel.superview addSubview:self.swapRightLabel];
        self.swapRightLabel.hidden = NO;
        self.amountLabel.hidden = YES;
    }
    
    CGFloat scale = self.swapRightLabel.font.pointSize/self.swapLeftLabel.font.pointSize;
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    NSString *s = (self.swapped) ? self.localCurrencyLabel.text : self.amountLabel.text;
    uint64_t amount =
    [priceManager amountForLocalCurrencyString:(self.swapped) ? [s substringWithRange:NSMakeRange(1, s.length - 2)] : s];
    if (self.usingShapeshift) {
#if SHAPESHIFT_ENABLED
        NSMutableAttributedString * attributedString = [[NSMutableAttributedString alloc] initWithString:@"(~"];
        if (self.swapped) {
            [attributedString appendAttributedString:[priceManager attributedStringForDashAmount:amount withTintColor:self.localCurrencyLabel.textColor dashSymbolSize:CGSizeMake(11, 12)]];
        } else {
            [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[priceManager bitcoinCurrencyStringForAmount:amount]]];
        }
        [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@")"]];
        self.localCurrencyLabel.attributedText = attributedString;
        self.amountLabel.attributedText = (self.swapped) ? [[NSAttributedString alloc] initWithString:[priceManager bitcoinCurrencyStringForAmount:amount]]:[priceManager attributedStringForDashAmount:amount withTintColor:self.amountLabel.textColor dashSymbolSize:CGSizeMake(15, 16)];
#endif
    } else {
        NSMutableAttributedString * attributedString = [[NSMutableAttributedString alloc] initWithString:@"("];
        if (self.swapped) {
            [attributedString appendAttributedString:[priceManager attributedStringForDashAmount:amount withTintColor:self.localCurrencyLabel.textColor dashSymbolSize:CGSizeMake(11, 12)]];
        } else {
            [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[priceManager localCurrencyStringForDashAmount:amount]]];
        }
        [attributedString appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@")"]];
        self.localCurrencyLabel.attributedText = attributedString;
        self.amountLabel.attributedText = (self.swapped) ? [[NSAttributedString alloc] initWithString:[priceManager localCurrencyStringForDashAmount:amount]]:[priceManager attributedStringForDashAmount:amount withTintColor:self.amountLabel.textColor dashSymbolSize:CGSizeMake(15, 16)];
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
        OFFBLUE_COLOR;
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
        self.shapeshiftLocalCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",[priceManager localCurrencyStringForDashAmount:0]];
    }
}

- (IBAction)releaseSwapButton:(id)sender
{
    [DSEventManager saveEvent:@"amount:release_swap"];
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
        tipView.font = [UIFont systemFontOfSize:14.0];
        tipView.userInteractionEnabled = YES;
        [self.view addSubview:[tipView popIn]];
        self.tipView = tipView;
    }
}

// MARK: - UITextFieldDelegate

-(void)updateAmountLabel:(UILabel *)amountLabel shouldChangeCharactersInRange:(NSRange)range
       replacementString:(NSString *)string
{
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    NSNumberFormatter *formatter;
    if (self.usingShapeshift) {
        formatter = (self.swapped) ? priceManager.bitcoinFormat:priceManager.dashFormat;
    } else {
        formatter = (self.swapped) ? priceManager.localFormat:priceManager.dashFormat;
    }
    NSNumberFormatter *basicFormatter = priceManager.unknownFormat;
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
#if SHAPESHIFT_ENABLED
            amountLabel.attributedText = (self.swapped) ? [[NSAttributedString alloc] initWithString:[priceManager bitcoinCurrencyStringForAmount:0]]:[priceManager attributedStringForDashAmount:0 withTintColor:OFFBLUE_COLOR dashSymbolSize:CGSizeMake(15, 16)];
#endif
        } else {
            amountLabel.attributedText = (self.swapped) ? [[NSAttributedString alloc] initWithString:[priceManager localCurrencyStringForDashAmount:0]]:[priceManager attributedStringForDashAmount:0 withTintColor:OFFBLUE_COLOR dashSymbolSize:CGSizeMake(15, 16)];
        }
        amountLabel.textColor = OFFBLUE_COLOR;
    } else {
        amountLabel.textColor = OFFWHITE_COLOR;
        if (!self.swapped) {
            amountLabel.attributedText = [formattedAmount attributedStringForDashSymbolWithTintColor:self.amountLabel.textColor dashSymbolSize:CGSizeMake(15, 16)];
        } else {
            
            amountLabel.text = formattedAmount;
        }
    }
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    if (!self.requestingAmount) {
        if (! authenticationManager.didAuthenticate && (formattedAmount.length == 0 || self.amountLabelIsEmpty || ![number floatValue]) && self.navigationItem.rightBarButtonItem != self.lock) {
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
