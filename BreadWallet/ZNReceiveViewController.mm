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
#import "ZNWalletManager.h"
#import "ZNWallet.h"
#import "ZNButton.h"
#import "ZNBubbleView.h"
#import "QREncoder.h"

#define BALANCE_TIP @"This is your bitcoin balance. Bitcoin is a currency. The exchange rate changes with the market."
#define QR_TIP      @"Let others scan this QR code to get your bitcoin address. "\
                     "Anyone can send bitcoins to your wallet by transferring them to your address."
#define ADDRESS_TIP @"This is your bitcoin address. Tap to copy it or send it by email or sms. "\
                     "The address will change each time you receive funds, but old addresses always work."
#define PAGE_TIP    @"Tap or swipe left to send money."

@interface ZNReceiveViewController ()

@property (nonatomic, strong) ZNBubbleView *tipView;

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
    
    if (! [self.paymentRequest isValid]) return;
    
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
    return [[[ZNWalletManager sharedInstance] wallet] receiveAddress];
}

- (BOOL)nextTip
{
    ZNBubbleView *v = self.tipView;

    if (v.alpha < 0.5) return NO;

    if ([v.text isEqual:BALANCE_TIP]) {
        self.tipView = [ZNBubbleView viewWithText:QR_TIP
                        tipPoint:[self.qrView.superview convertPoint:self.qrView.center toView:self.view]
                        tipDirection:ZNBubbleTipDirectionUp];
    }
    else if ([v.text isEqual:QR_TIP]) {
        self.tipView = [ZNBubbleView viewWithText:ADDRESS_TIP
                        tipPoint:[self.addressButton.superview convertPoint:self.addressButton.center toView:self.view]
                        tipDirection:ZNBubbleTipDirectionDown];
    }
    else if ([v.text isEqual:ADDRESS_TIP]) {
        self.tipView = [ZNBubbleView viewWithText:PAGE_TIP
                        tipPoint:CGPointMake(self.view.bounds.size.width/2.0, self.view.superview.bounds.size.height)
                        tipDirection:ZNBubbleTipDirectionDown];
    }
    else self.tipView = nil;

    self.tipView.backgroundColor = v.backgroundColor;
    self.tipView.font = v.font;
    if (self.tipView) [self.view addSubview:[self.tipView fadeIn]];
    [v fadeOut];
    
    return YES;
}

- (BOOL)hideTips
{
    if (self.tipView.alpha < 0.5) return NO;
    [self.tipView fadeOut];
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

    self.tipView = [ZNBubbleView viewWithText:BALANCE_TIP tipPoint:CGPointMake(self.view.bounds.size.width/2.0, 0.0)
                    tipDirection:ZNBubbleTipDirectionUp];
    self.tipView.backgroundColor = [UIColor orangeColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    [self.view addSubview:[self.tipView fadeIn]];
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

    //TODO: XXXX allow user to specify a request amount
    if ([title isEqual:@"copy"]) {
        [[UIPasteboard generalPasteboard] setString:self.paymentAddress];        
        [self.view addSubview:[[[ZNBubbleView viewWithText:@"copied"
                                center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)]
                                fadeIn] fadeOutAfterDelay:2.0]];
    }
    else if ([title isEqual:@"email"]) {
        //TODO: XXXX implement BIP71 payment protocol mime attachement
        // https://github.com/bitcoin/bips/blob/master/bip-0071.mediawiki
        
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *c = [MFMailComposeViewController new];
            
            [c setSubject:@"Bitcoin address"];
            [c setMessageBody:[@"bitcoin:" stringByAppendingString:self.paymentAddress] isHTML:NO];
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
            
            c.body = [@"bitcoin:" stringByAppendingString:self.paymentAddress];
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
