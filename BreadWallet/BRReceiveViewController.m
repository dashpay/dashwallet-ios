//
//  BRReceiveViewController.m
//  BreadWallet
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

#import "BRReceiveViewController.h"
#import "BRRootViewController.h"
#import "BRPaymentRequest.h"
#import "BRWalletManager.h"
#import "BRTransaction.h"
#import "BRBubbleView.h"
#import "BRAppGroupConstants.h"
#import "UIImage+Utility.h"
#import <MobileCoreServices/UTCoreTypes.h>

#define QR_TIP      NSLocalizedString(@"Let others scan this QR code to get your bitcoin address. Anyone can send "\
                    "bitcoins to your wallet by transferring them to your address.", nil)
#define ADDRESS_TIP NSLocalizedString(@"This is your bitcoin address. Tap to copy it or send it by email or sms. The "\
                    "address will change each time you receive funds, but old addresses always work.", nil)

@interface BRReceiveViewController ()

@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, assign) BOOL showTips;

@property (nonatomic, strong) IBOutlet UILabel *label;
@property (nonatomic, strong) IBOutlet UIButton *addressButton;
@property (nonatomic, strong) IBOutlet UIImageView *qrView;

@end

@implementation BRReceiveViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.addressButton setTitle:nil forState:UIControlStateNormal];
    self.addressButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    [self updateAddress];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self hideTips];
    
    [super viewWillDisappear:animated];
}

- (void)updateAddress
{
    static NSUserDefaults *groupDefs = nil;
    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRPaymentRequest *req = self.paymentRequest;

    if ([self.paymentAddress isEqual:self.addressButton.currentTitle]) return;
    self.qrView.image = [UIImage imageWithQRCodeData:req.data size:self.qrView.bounds.size
                         color:[CIColor colorWithRed:0.0 green:0.0 blue:0.0]];
    [self.addressButton setTitle:self.paymentAddress forState:UIControlStateNormal];
    if (! groupDefs) groupDefs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
    
    if (req.amount > 0) {
        self.label.text = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:req.amount],
                           [m localCurrencyStringForAmount:req.amount]];
    }
    else if (req.isValid) {
        [groupDefs setObject:req.data forKey:APP_GROUP_REQUEST_DATA_KEY];
        [groupDefs setObject:self.paymentAddress forKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
        [groupDefs synchronize];
    }
    else {
        [groupDefs removeObjectForKey:APP_GROUP_REQUEST_DATA_KEY];
        [groupDefs removeObjectForKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
        [groupDefs synchronize];
    }
}

- (BRPaymentRequest *)paymentRequest
{
    if (_paymentRequest) return _paymentRequest;
    return [BRPaymentRequest requestWithString:self.paymentAddress];
}

- (NSString *)paymentAddress
{
    if (_paymentRequest) return _paymentRequest.paymentAddress;
    return [BRWalletManager sharedInstance].wallet.receiveAddress;
}

- (BOOL)nextTip
{
    if (self.tipView.alpha < 0.5) return [(id)self.parentViewController.parentViewController nextTip];

    BRBubbleView *v = self.tipView;

    self.tipView = nil;
    [v popOut];

    if ([v.text hasPrefix:QR_TIP]) {
        self.tipView = [BRBubbleView viewWithText:ADDRESS_TIP tipPoint:[self.addressButton.superview
                        convertPoint:CGPointMake(self.addressButton.center.x, self.addressButton.center.y - 10.0)
                        toView:self.view] tipDirection:BRBubbleTipDirectionDown];
        self.tipView.backgroundColor = v.backgroundColor;
        self.tipView.font = v.font;
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips && [v.text hasPrefix:ADDRESS_TIP]) {
        self.showTips = NO;
        [(id)self.parentViewController.parentViewController tip:self];
    }

    return YES;
}

- (void)hideTips
{
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

#pragma mark - IBAction

- (IBAction)done:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)tip:(id)sender
{
    if ([self nextTip]) return;

    if (! [sender isKindOfClass:[UIGestureRecognizer class]] ||
        ([sender view] != self.qrView && ! [[sender view] isKindOfClass:[UILabel class]])) {
        if (! [sender isKindOfClass:[UIViewController class]]) return;
        self.showTips = YES;
    }

    self.tipView = [BRBubbleView viewWithText:QR_TIP
                    tipPoint:[self.qrView.superview convertPoint:self.qrView.center toView:self.view]
                    tipDirection:BRBubbleTipDirectionUp];
    self.tipView.backgroundColor = [UIColor orangeColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    [self.view addSubview:[self.tipView popIn]];
}

- (IBAction)address:(id)sender
{
    if ([self nextTip]) return;

    BOOL req = (_paymentRequest) ? YES : NO;
    UIActionSheet *a = [UIActionSheet new];

    a.title = [NSString stringWithFormat:NSLocalizedString(@"Receive bitcoins at this address: %@", nil),
               self.paymentAddress];
    a.delegate = self;
    [a addButtonWithTitle:(req) ? NSLocalizedString(@"copy request to clipboard", nil) :
     NSLocalizedString(@"copy address to clipboard", nil)];

    if ([MFMailComposeViewController canSendMail]) {
        [a addButtonWithTitle:(req) ? NSLocalizedString(@"send request as email", nil) :
         NSLocalizedString(@"send address as email", nil)];
    }

#if ! TARGET_IPHONE_SIMULATOR
    if ([MFMessageComposeViewController canSendText]) {
        [a addButtonWithTitle:(req) ? NSLocalizedString(@"send request as message", nil) :
         NSLocalizedString(@"send address as message", nil)];
    }
#endif

    if (! req) [a addButtonWithTitle:NSLocalizedString(@"request an amount", nil)];
    [a addButtonWithTitle:NSLocalizedString(@"cancel", nil)];
    a.cancelButtonIndex = a.numberOfButtons - 1;
    
    [a showInView:[UIApplication sharedApplication].keyWindow];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];

    //TODO: allow user to create a payment protocol request object, and use merge avoidance techniques:
    // https://medium.com/@octskyward/merge-avoidance-7f95a386692f
    if ([title isEqual:NSLocalizedString(@"copy address to clipboard", nil)] ||
        [title isEqual:NSLocalizedString(@"copy request to clipboard", nil)]) {
        [UIPasteboard generalPasteboard].string =
            (self.paymentRequest.amount > 0) ? self.paymentRequest.string : self.paymentAddress;

        [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"copied", nil)
         center:CGPointMake(self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0 - 130.0)] popIn]
         popOutAfterDelay:2.0]];
    }
    else if ([title isEqual:NSLocalizedString(@"send address as email", nil)] ||
             [title isEqual:NSLocalizedString(@"send request as email", nil)]) {
        //TODO: implement BIP71 payment protocol mime attachement
        // https://github.com/bitcoin/bips/blob/master/bip-0071.mediawiki
        
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *c = [MFMailComposeViewController new];
            
            c.subject = NSLocalizedString(@"Bitcoin address", nil);
            [c setMessageBody:self.paymentRequest.string isHTML:NO];
            [c addAttachmentData:UIImagePNGRepresentation(self.qrView.image) mimeType:@"image/png" fileName:@"qr.png"];
            c.mailComposeDelegate = self;
            [self.navigationController presentViewController:c animated:YES completion:nil];
            c.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default"]];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:@"" message:NSLocalizedString(@"email not configured", nil) delegate:nil
              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        }
    }
    else if ([title isEqual:NSLocalizedString(@"send address as message", nil)] ||
             [title isEqual:NSLocalizedString(@"send request as message", nil)]) {
        if ([MFMessageComposeViewController canSendText]) {
            MFMessageComposeViewController *c = [MFMessageComposeViewController new];

            if ([MFMessageComposeViewController canSendSubject]) c.subject = NSLocalizedString(@"Bitcoin address", nil);
            c.body = self.paymentRequest.string;
            
            if ([MFMessageComposeViewController canSendAttachments]) {
                [c addAttachmentData:UIImagePNGRepresentation(self.qrView.image) typeIdentifier:(NSString *)kUTTypePNG
                 filename:@"qr.png"];
            }
            
            c.messageComposeDelegate = self;
            [self.navigationController presentViewController:c animated:YES completion:nil];
            c.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default"]];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:@"" message:NSLocalizedString(@"sms not currently available", nil)
              delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        }
    }
    else if ([title isEqual:NSLocalizedString(@"request an amount", nil)]) {
        UINavigationController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"AmountNav"];
        
        ((BRAmountViewController *)c.topViewController).delegate = self;
        [self.navigationController presentViewController:c animated:YES completion:nil];
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

#pragma mark - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount
{
    if (amount < TX_MIN_OUTPUT_AMOUNT) {
        BRWalletManager *m = [BRWalletManager sharedInstance];
    
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"amount too small", nil)
          message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin payments can't be less than %@", nil),
                   [m stringForAmount:TX_MIN_OUTPUT_AMOUNT]] delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        return;
    }

    BRReceiveViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"RequestViewController"];
    
    c.paymentRequest = self.paymentRequest;
    c.paymentRequest.amount = amount;
    ((UINavigationController *)self.navigationController.presentedViewController).delegate = c;
    [(UINavigationController *)self.navigationController.presentedViewController pushViewController:c animated:YES];
}

#pragma mark - UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return 0.35;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    UIView *v = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];

    [v addSubview:to.view];
    
    [UIView transitionFromView:from.view toView:to.view duration:[self transitionDuration:transitionContext]
    options:UIViewAnimationOptionTransitionFlipFromLeft completion:^(BOOL finished) {
        [from.view removeFromSuperview];
        [transitionContext completeTransition:YES];
    }];
}

#pragma mark - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC
toViewController:(UIViewController *)toVC
{
    return self;
}

#pragma mark - UIViewControllerTransitioningDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
{
    return self;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    return self;
}

@end
