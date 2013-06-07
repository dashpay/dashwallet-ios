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

@end

@implementation ZNAmountViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.addressLabel.text = [@"pay to: " stringByAppendingString:self.request.paymentAddress];
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
    if (! textField.text.length && string.length) {
        textField.text = [NSString stringWithFormat:@"m%@ %@%@%@", BTC, [string isEqual:@"."] ? @"0" : @"", string,
                          [string isEqual:@"0"] ? @"." : @""];
    }
    else if (! string.length && ((textField.text.length == 5 && [textField.text hasSuffix:@"0."]) ||
             textField.text.length <= 4)) {
        textField.text = @"";
    }
    else if (! [string isEqual:@"."] || [textField.text rangeOfString:@"."].location == NSNotFound) {
        textField.text = [textField.text stringByReplacingCharactersInRange:range withString:string];
    }

    return NO;
}

@end
