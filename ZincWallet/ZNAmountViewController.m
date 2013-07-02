//
//  ZNAmountViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/4/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNAmountViewController.h"
#import "ZNPaymentRequest.h"
#import "ZNWallet.h"
#import "ZNTransaction.h"
#import "NSData+Hash.h"

@interface ZNAmountViewController ()

@property (nonatomic, strong) IBOutlet UITextField *amountField;
@property (nonatomic, strong) IBOutlet UILabel *addressLabel;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *payButton;
@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *buttons, *buttonRow1, *buttonRow2, *buttonRow3;

@property (nonatomic, strong) ZNTransaction *tx, *txWithFee;
@property (nonatomic, strong) id balanceObserver;

@end

@implementation ZNAmountViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self.buttons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [obj titleLabel].font = [UIFont fontWithName:@"HelveticaNeue-Light" size:24];
        [obj setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    }];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    CGRect f = self.spinner.frame;
    f.size.width = 33;
    self.spinner.frame = f;

    if ([[UIScreen mainScreen] bounds].size.height < 500) { // adjust number buttons for 3.5" screen
        [self.buttons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            CGFloat y = self.view.frame.size.height - 122;

            if ([self.buttonRow1 containsObject:obj]) y = self.view.frame.size.height - 344.0;
            else if ([self.buttonRow2 containsObject:obj]) y = self.view.frame.size.height - 270.0;
            else if ([self.buttonRow3 containsObject:obj]) y = self.view.frame.size.height - 196.0;

            [obj setFrame:CGRectMake([obj frame].origin.x, y, [obj frame].size.width, 66.0)];
            [obj setImageEdgeInsets:UIEdgeInsetsMake(20.0, [obj imageEdgeInsets].left,
                                                     20.0, [obj imageEdgeInsets].right)];
        }];
    }

    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:walletBalanceNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            self.navigationItem.title = [[ZNWallet sharedInstance] stringForAmount:[[ZNWallet sharedInstance] balance]];
        }];
}

- (void)viewWillUnload
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];

    [super viewWillUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.addressLabel.text = [@"to: " stringByAppendingString:self.request.paymentAddress];
    //self.payButton.enabled = self.amountField.text.length ? YES : NO;
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
    ZNWallet *w = [ZNWallet sharedInstance];

    self.request.amount = [w amountForString:self.amountField.text];

    if (self.request.isValid) {
        if (self.request.amount < TX_MIN_OUTPUT_AMOUNT) {
            [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment"
              message:[@"Bitcoin payments can't be less than "
                       stringByAppendingString:[[ZNWallet sharedInstance] stringForAmount:TX_MIN_OUTPUT_AMOUNT]]
              delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            
            return;
        }

        self.tx = [w transactionFor:self.request.amount to:self.request.paymentAddress withFee:NO];
        self.txWithFee = [w transactionFor:self.request.amount to:self.request.paymentAddress withFee:YES];

        NSString *fee = [w stringForAmount:[w transactionFee:self.txWithFee]];
        NSTimeInterval t = [w timeUntilFree:self.tx];
        
        if (! self.tx || (t > DBL_EPSILON && ! self.txWithFee)) {
            [[[UIAlertView alloc] initWithTitle:@"Insuficient Funds" message:nil delegate:nil cancelButtonTitle:@"OK"
              otherButtonTitles:nil] show];
        }
        else if (t > DBL_MAX - DBL_EPSILON) {
            [[[UIAlertView alloc] initWithTitle:@"transaction fee needed"
              message:[NSString stringWithFormat:@"the bitcoin network needs a fee of %@ to send this payment", fee]
              delegate:self cancelButtonTitle:@"cancel" otherButtonTitles:[NSString stringWithFormat:@"+ %@", fee], nil]
             show];
        }
        else if (t > DBL_EPSILON) {
            NSUInteger minutes = t/60, hours = t/(60*60);
            NSString *time = [NSString stringWithFormat:@"%d %@%@", hours ? hours : minutes,
                              hours ? @"hour" : @"minutes", hours > 1 ? @"s" : @""];
        
            [[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ transaction fee recommended", fee]
              message:[NSString stringWithFormat:@"estimated confirmation time with no fee: %@", time] delegate:self
              cancelButtonTitle:nil otherButtonTitles:@"no fee", [NSString stringWithFormat:@"+ %@", fee], nil] show];
        }
        else {
            w.format.minimumFractionDigits = w.format.maximumFractionDigits;
            [[[UIAlertView alloc] initWithTitle:@"Confirm Payment"
              message:self.request.message ? self.request.message : self.request.paymentAddress delegate:self
              cancelButtonTitle:@"cancel" otherButtonTitles:[w stringForAmount:self.request.amount], nil] show];
            w.format.minimumFractionDigits = 0;
        }
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    ZNWallet *w = [ZNWallet sharedInstance];
    NSUInteger point = [textField.text rangeOfString:@"."].location;
    NSString *t = textField.text ? [textField.text stringByReplacingCharactersInRange:range withString:string] : string;

    t = [w.format stringFromNumber:[w.format numberFromString:t]];

    if (! string.length && point != NSNotFound) { // delete trailing char
        t = [textField.text stringByReplacingCharactersInRange:range withString:string];
        if ([t isEqual:[w.format stringFromNumber:@0]]) t = @"";
    }
    else if ((string.length && textField.text.length && t == nil) ||
             (point != NSNotFound && textField.text.length - point > 5)) {
        return NO;
    }
    else if ([string isEqual:@"."] && (! textField.text.length || point == NSNotFound)) {
        if (! textField.text.length) {
            t = [w.format stringFromNumber:@0];
        }
        
        t = [t stringByAppendingString:@"."];
    }
    else if ([string isEqual:@"0"]) {
        if (! textField.text.length) {
            t = [[w.format stringFromNumber:@0] stringByAppendingString:@"."];
        }
        else if (point != NSNotFound) { // handle multiple zeros after period....
            t = [textField.text stringByAppendingString:@"0"];
        }
    }

    textField.text = t;
    //self.payButton.enabled = t.length ? YES : NO;

    return NO;
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        return;
    }
    
    ZNWallet *w = [ZNWallet sharedInstance];
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    
    if ([title hasPrefix:@"+ "]) self.tx = self.txWithFee;
    
    if ([title hasPrefix:@"+ "] || [title isEqual:@"no fee"]) {
        w.format.minimumFractionDigits = w.format.maximumFractionDigits;
        [[[UIAlertView alloc] initWithTitle:@"Confirm Payment"
          message:self.request.message ? self.request.message : self.request.paymentAddress delegate:self
          cancelButtonTitle:@"cancel"
          otherButtonTitles:[w stringForAmount:self.request.amount + [w transactionFee:self.tx]], nil] show];
        w.format.minimumFractionDigits = 0;
    }
    else {
        NSLog(@"signing transaction");
        [w signTransaction:self.tx];
        
        if (! [self.tx isSigned]) {
            [[[UIAlertView alloc] initWithTitle:@"couldn't send payment" message:@"error signing bitcoin transaction"
              delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
        else {
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
            [self.spinner startAnimating];
        
            NSLog(@"signed transaction:\n%@", [self.tx toHex]);

            [w publishTransaction:self.tx completion:^(NSError *error) {
                [self.spinner stopAnimating];
                self.navigationItem.rightBarButtonItem = self.payButton;
            
                if (error) {
                    [[[UIAlertView alloc] initWithTitle:@"couldn't send payment" message:error.localizedDescription
                      delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];

                    return;
                }

                if (self.navigationController.topViewController == self) {
                    [self.navigationController popViewControllerAnimated:YES];
                }
                
                //XXXX should use something like MBProgressHUD instead of alert
                [[[UIAlertView alloc] initWithTitle:@"sent!"
                  message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }];
        }
    }
}

@end
