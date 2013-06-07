//
//  ZNAmountViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/4/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNAmountViewController.h"
#import "ZNPaymentRequest.h"

@interface ZNAmountViewController ()

@property (nonatomic, strong) IBOutlet UITextField *amountField;
@property (nonatomic, strong) IBOutlet UILabel *addressLabel;
@property (nonatomic, strong) NSNumberFormatter *format;

@end

@implementation ZNAmountViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    self.format = [NSNumberFormatter new];
    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
    self.format.currencySymbol = @"m"BTC@" ";
    self.format.minimumFractionDigits = 0;
    self.format.maximumFractionDigits = 5;
    self.format.maximum = @21000000000.0;
    [self.format setLenient:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.addressLabel.text = [@"to: " stringByAppendingString:self.request.paymentAddress];
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


#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    NSUInteger point = [textField.text rangeOfString:@"."].location;
    NSString *t = textField.text ? [textField.text stringByReplacingCharactersInRange:range withString:string] : string;

    t = [self.format stringFromNumber:[self.format numberFromString:t]];

    if (! string.length && point != NSNotFound) {
        t = [textField.text stringByReplacingCharactersInRange:range withString:string];
        if ([t isEqual:[self.format stringFromNumber:@0]]) t = @"";
    }
    else if ((string.length && textField.text.length && t == nil) ||
             (point != NSNotFound && textField.text.length - point > 5)) {
        return NO;
    }
    else if ([string isEqual:@"."] && (! textField.text.length || point == NSNotFound)) {
        if (! textField.text.length) {
            t = [self.format stringFromNumber:@1];
            t = [[t substringToIndex:t.length - 1] stringByAppendingString:@"0"];
        }
        
        t = [t stringByAppendingString:@"."];
    }
    else if ([string isEqual:@"0"]) {
        if (! textField.text.length) {
            t = [self.format stringFromNumber:@1];
            t = [[t substringToIndex:t.length - 1] stringByAppendingString:@"0."];            
        }
        else if (point != NSNotFound) { // handle multiple zeros after period....
            t = [textField.text stringByAppendingString:@"0"];
        }
    }

    textField.text = t;

    return NO;
}

@end
