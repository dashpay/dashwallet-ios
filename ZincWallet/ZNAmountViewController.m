//
//  ZNAmountViewController.m
//  ZincWallet
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

#import "ZNAmountViewController.h"
#import "ZNPaymentRequest.h"
#import "ZNWalletManager.h"
#import "ZNWallet.h"
#import "ZNPeerManager.h"
#import "ZNTransaction.h"
#import "ZNButton.h"

@interface ZNAmountViewController ()

@property (nonatomic, strong) IBOutlet UITextField *amountField;
@property (nonatomic, strong) IBOutlet UILabel *addressLabel;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *payButton;
@property (nonatomic, strong) IBOutlet UIButton *delButton;
@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *buttons, *buttonRow1, *buttonRow2, *buttonRow3;
@property (nonatomic, strong) id balanceObserver, syncStartedObserver, syncFinishedObserver, syncFailedObserver;

@end

@implementation ZNAmountViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    ZNWalletManager *m = [ZNWalletManager sharedInstance];
    
    self.amountField.placeholder = [m stringForAmount:0];
    
    for (ZNButton *button in self.buttons) {
        [button setStyle:ZNButtonStyleBlue];
        button.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-UltraLight" size:50];
    }

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];

    if ([[UIScreen mainScreen] bounds].size.height < 500) { // adjust number buttons for 3.5" screen
        for (ZNButton *button in self.buttons) {
            CGFloat y = self.view.frame.size.height - 122;

            if ([self.buttonRow1 containsObject:button]) y = self.view.frame.size.height - 344.0;
            else if ([self.buttonRow2 containsObject:button]) y = self.view.frame.size.height - 270.0;
            else if ([self.buttonRow3 containsObject:button]) y = self.view.frame.size.height - 196.0;

            button.frame = CGRectMake(button.frame.origin.x, y, button.frame.size.width, 66.0);
            button.imageEdgeInsets = UIEdgeInsetsMake(20.0, button.imageEdgeInsets.left,
                                                      20.0, button.imageEdgeInsets.right);
        }
    }
    
    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:ZNWalletBalanceChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if ([[ZNPeerManager sharedInstance] syncProgress] < 1.0) return; // wait for sync before updating balance

            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                         [m localCurrencyStringForAmount:m.wallet.balance]];
        }];
    
    self.syncStartedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:ZNPeerManagerSyncStartedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [UIApplication sharedApplication].idleTimerDisabled = YES;
            
            if (self.navigationItem.rightBarButtonItem == self.payButton) {
                self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
                [self.spinner startAnimating];
            }
        }];
    
    self.syncFinishedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:ZNPeerManagerSyncFinishedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            self.navigationItem.rightBarButtonItem = self.payButton;
            [self.spinner stopAnimating];
            [UIApplication sharedApplication].idleTimerDisabled = NO;
        }];
    
    self.syncFailedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:ZNPeerManagerSyncFailedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            self.navigationItem.rightBarButtonItem = self.payButton;
            [self.spinner stopAnimating];
            [UIApplication sharedApplication].idleTimerDisabled = NO;
        }];
}

- (void)dealloc
{
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    NSString *addr = self.request.paymentAddress;
    
    if (addr) self.addressLabel.text = [@"to: " stringByAppendingString:addr];
    //self.payButton.enabled = self.amountField.text.length ? YES : NO;
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.request.amount = 0;
    
    [super viewWillDisappear:animated];
}

#pragma mark - IBAction

- (IBAction)number:(id)sender
{
    [self textField:self.amountField shouldChangeCharactersInRange:NSMakeRange(self.amountField.text.length, 0)
     replacementString:[(UIButton *)sender titleLabel].text];
}

- (IBAction)del:(id)sender
{
    if (! self.amountField.text.length) return;
    
    [self textField:self.amountField shouldChangeCharactersInRange:NSMakeRange(self.amountField.text.length - 1, 1)
     replacementString:@""];
}

- (IBAction)pay:(id)sender
{
    self.request.amount = [[ZNWalletManager sharedInstance] amountForString:self.amountField.text];

    if (self.request.amount == 0) return;
    
    [self.delegate amountViewController:self selectedAmount:self.request.amount];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    ZNWalletManager *m = [ZNWalletManager sharedInstance];
    NSUInteger point = [textField.text rangeOfString:[m.format decimalSeparator]].location;
    NSString *t = textField.text ? [textField.text stringByReplacingCharactersInRange:range withString:string] : string;

    t = [m.format stringFromNumber:[m.format numberFromString:t]];

    if (! string.length && point != NSNotFound) { // delete trailing char
        t = [textField.text stringByReplacingCharactersInRange:range withString:string];
        if ([t isEqual:[m.format stringFromNumber:@0]]) t = @"";
    }
    else if ((string.length > 0 && textField.text.length > 0 && t == nil) ||
             (point != NSNotFound && textField.text.length - point > m.format.maximumFractionDigits)) {
        return NO; // too many digits
    }
    else if ([string isEqual:[m.format decimalSeparator]] && (! textField.text.length || point == NSNotFound)) {
        if (! textField.text.length) t = [m.format stringFromNumber:@0]; // if first char is '.', prepend a zero
        
        t = [t stringByAppendingString:[m.format decimalSeparator]];
    }
    else if ([string isEqual:@"0"]) {
        if (! textField.text.length) { // if first digit is zero, append a '.'
            t = [[m.format stringFromNumber:@0] stringByAppendingString:[m.format decimalSeparator]];
        }
        else if (point != NSNotFound) { // handle multiple zeros after period....
            t = [textField.text stringByAppendingString:@"0"];
        }
    }

    // don't allow values below TX_MIN_OUTPUT_AMOUNT
    if (t.length > 0 && [t rangeOfString:[m.format decimalSeparator]].location != NSNotFound &&
        [m amountForString:[t stringByAppendingString:@"9"]] < TX_MIN_OUTPUT_AMOUNT) {
        return NO;
    }

    textField.text = t;
    //self.payButton.enabled = t.length ? YES : NO;

    //TODO: XXXX add local currency string
    
    return NO;
}

@end
