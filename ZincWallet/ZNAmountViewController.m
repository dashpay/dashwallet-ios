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
#import "NSData+Hash.h"

@interface ZNAmountViewController ()

@property (nonatomic, strong) IBOutlet UITextField *amountField;
@property (nonatomic, strong) IBOutlet UILabel *addressLabel;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *payButton;
@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *buttons, *buttonRow1, *buttonRow2, *buttonRow3;

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

    if ([[UIScreen mainScreen]bounds].size.height < 500) { // 3.5" screen
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
    double factor = pow(10, (double)w.format.maximumFractionDigits);

    self.request.amount =
        [[w.format numberFromString:self.amountField.text] doubleValue]*factor;

    if (self.request.isValid) {
        w.format.minimumFractionDigits = w.format.maximumFractionDigits;
        [[[UIAlertView alloc] initWithTitle:@"Confirm Payment"
          message:self.request.message ? self.request.message : self.request.paymentAddress delegate:self
          cancelButtonTitle:@"cancel"
          otherButtonTitles:[w.format stringFromNumber:@((double)self.request.amount/factor)], nil] show];
        w.format.minimumFractionDigits = 0;
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
    
    NSData *signedTx = [self.request signedTransaction];
    
    NSLog(@"signed transaction:\n%@", [signedTx toHex]);
}

@end
