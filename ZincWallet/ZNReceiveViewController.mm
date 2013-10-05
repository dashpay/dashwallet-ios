//
//  ZNReceiveViewController.m
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
@property (nonatomic, strong) IBOutlet UIView *qrTipView, *addressTipView, *pageTipView, *balanceTipView;
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
    
//#warning remove this
//    ZNPaymentRequest *r = self.paymentRequest;
//    r.amount = 1;
//    NSString *s = [[NSString alloc] initWithData:r.data encoding:NSUTF8StringEncoding];
    NSString *s = [[NSString alloc] initWithData:self.paymentRequest.data encoding:NSUTF8StringEncoding];
    
    self.qrView.image = [QREncoder renderDataMatrix:[QREncoder encodeWithECLevel:1 version:1 string:s]
                         imageDimension:self.qrView.frame.size.width];
    
    [self.addressButton setTitle:self.paymentAddress forState:UIControlStateNormal];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self hideTips];
    
    [super viewWillDisappear:animated];
}

- (ZNPaymentRequest *)paymentRequest
{
    return [ZNPaymentRequest requestWithString:self.paymentAddress];
}

- (NSString *)paymentAddress
{
    return [[ZNWallet sharedInstance] receiveAddress];
}

- (BOOL)nextTip
{
    if (self.qrTipView.alpha < 0.5 && self.addressTipView.alpha < 0.5 && self.balanceTipView.alpha < 0.5 &&
        self.pageTipView.alpha < 0.5) return NO;

    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
        if (self.balanceTipView.alpha > 0.5) {
            self.balanceTipView.alpha = 0.0;
            self.qrTipView.alpha = 1.0;
        }
        else if (self.qrTipView.alpha > 0.5) {
            self.qrTipView.alpha = 0.0;
            self.addressTipView.alpha = 1.0;
        }
        else if (self.addressTipView.alpha > 0.5) {
            self.addressTipView.alpha = 0.0;
            self.pageTipView.alpha = 1.0;
        }
        else if (self.pageTipView.alpha > 0.5) self.pageTipView.alpha = 0.0;
    }];
    
    return YES;
}

- (BOOL)hideTips
{
    if (self.qrTipView.alpha < 0.5 && self.addressTipView.alpha < 0.5 && self.balanceTipView.alpha < 0.5 &&
        self.pageTipView.alpha < 0.5) return NO;
    
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
        self.qrTipView.alpha = self.addressTipView.alpha = self.balanceTipView.alpha = self.pageTipView.alpha = 0.0;
    }];
    
    return YES;
}

#pragma mark - IBAction

- (IBAction)swipeRight:(id)sender
{
    [self.parentViewController performSelector:@selector(page:) withObject:nil];
}

- (IBAction)info:(id)sender
{
    if ([self nextTip]) return;

    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
        self.balanceTipView.alpha = 1.0;
    }];
}

- (IBAction)next:(id)sender
{
    [self nextTip];
}

- (IBAction)address:(id)sender
{
    if ([self nextTip]) return;

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
            [self.navigationController presentViewController:c animated:YES completion:nil];
            c.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default.png"]];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:nil message:@"email not configured on this device" delegate:nil
              cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
        }
    }
    else if ([title isEqual:@"sms"]) {
        if ([MFMessageComposeViewController canSendText]) {
            MFMessageComposeViewController *c = [MFMessageComposeViewController new];
            
            c.body = [@"bitcoin:" stringByAppendingString:[self paymentAddress]];
            c.messageComposeDelegate = self;
            [self.navigationController presentViewController:c animated:YES completion:nil];
            c.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default.png"]];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:nil message:@"sms not currently available on this device" delegate:nil
              cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
        }
    }    
}

#pragma mark - MFMessageComposeViewControllerDelegate

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
didFinishWithResult:(MessageComposeResult)result
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result
error:(NSError *)error
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
