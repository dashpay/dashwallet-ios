//
//  ZNSecondViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
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

#import "ZNReceiveViewController.h"
#import "ZNPaymentRequest.h"
#import "ZNWallet.h"
#import "ZNButton.h"
#import "QREncoder.h"
#import "MBProgressHUD.h"

@interface ZNReceiveViewController ()

@property (nonatomic, strong) IBOutlet UILabel *label;
@property (nonatomic, strong) IBOutlet UIButton *infoButton;
@property (nonatomic, strong) IBOutlet UIImageView *qrView;
@property (nonatomic, strong) IBOutlet ZNButton *addressButton;

@end

@implementation ZNReceiveViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.addressButton.style = ZNButtonStyleNone;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (! [[self paymentRequest] isValid]) return;
    
    NSString *s = [[NSString alloc] initWithData:self.paymentRequest.data encoding:NSUTF8StringEncoding];
    
    self.qrView.image = [QREncoder renderDataMatrix:[QREncoder encodeWithECLevel:1 version:1 string:s]
                         imageDimension:self.qrView.frame.size.width];
    
    [self.addressButton setTitle:self.paymentAddress forState:UIControlStateNormal];
}

- (ZNPaymentRequest *)paymentRequest
{
    return [ZNPaymentRequest requestWithString:self.paymentAddress];
}

- (NSString *)paymentAddress
{
    return [[ZNWallet sharedInstance] receiveAddress];
}

#pragma mark - IBAction

- (IBAction)info:(id)sender
{
    
}

- (IBAction)address:(id)sender
{
    UIActionSheet *a = [UIActionSheet new];
    
    a.title = [@"Receive bitcoins at this address: " stringByAppendingString:self.paymentAddress];
    a.delegate = self;
    [a addButtonWithTitle:@"copy"];
    if ([MFMailComposeViewController canSendMail]) [a addButtonWithTitle:@"email"];
#if ! TARGET_IPHONE_SIMULATOR
    if ([MFMessageComposeViewController canSendText]) [a addButtonWithTitle:@"sms"];
#endif
    [a addButtonWithTitle:@"cancel"];
    a.cancelButtonIndex = a.numberOfButtons - 1;
    
    [a showInView:[[UIApplication sharedApplication] keyWindow]];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    
    if ([title isEqual:@"copy"]) {
        _copiedAddress = [self paymentAddress];
        [[UIPasteboard generalPasteboard] setString:[self paymentAddress]];
        
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        
        hud.yOffset = -130;
        hud.mode = MBProgressHUDModeText;
        hud.labelText = @"coppied";
        hud.labelFont = [UIFont fontWithName:@"HelveticaNeue-Medium" size:17.0];
        [hud hide:YES afterDelay:1.0];
    }
    else if ([title isEqual:@"email"]) {
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *c = [MFMailComposeViewController new];
            
            [c setSubject:@"Bitcoin address"];
            [c setMessageBody:[@"bitcoin:" stringByAppendingString:[self paymentAddress]] isHTML:NO];
            c.mailComposeDelegate = self;
            //[self.navController presentViewController:c animated:YES completion:nil];
            [self.navigationController presentViewController:c animated:YES completion:nil];
            c.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default.png"]];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:nil message:@"email not configured on this device" delegate:nil
              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
    }
    else if ([title isEqual:@"sms"]) {
        if ([MFMessageComposeViewController canSendText]) {
            MFMessageComposeViewController *c = [MFMessageComposeViewController new];
            
            c.body = [@"bitcoin:" stringByAppendingString:[self paymentAddress]];
            c.messageComposeDelegate = self;
            //[self.navController presentViewController:c animated:YES completion:nil];
            [self.navigationController presentViewController:c animated:YES completion:nil];
            c.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default.png"]];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:nil message:@"sms not currently available on this device" delegate:nil
              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
    }    
}

#pragma mark - MFMessageComposeViewControllerDelegate

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
didFinishWithResult:(MessageComposeResult)result
{
    //[self.navController dismissViewControllerAnimated:YES completion:nil];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result
error:(NSError *)error
{
    //[self.navController dismissViewControllerAnimated:YES completion:nil];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
