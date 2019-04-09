//
//  DWReceiveViewController.m
//  DashWallet
//
//  Created by Aaron Voisine for BreadWallet on 5/8/13.
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

#import "DWReceiveViewController.h"
#import "DWRootViewController.h"
#import "BRBubbleView.h"
#import "DWAppGroupConstants.h"
#import "UIImage+Utils.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <DashSync/DashSync.h>
#import "DWAmountNavigationController.h"
#import "DWAmountViewController.h"

#define QR_TIP      NSLocalizedString(@"Let others scan this QR code to get your dash address. Anyone can send "\
                    "dash to your wallet by transferring them to your address.", nil)
#define ADDRESS_TIP NSLocalizedString(@"This is your dash address. Tap to copy it or send it by email or sms. The "\
                    "address will change each time you receive funds, but old addresses always work.", nil)

//#define QR_IMAGE_FILE [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject\
//                       stringByAppendingPathComponent:@"qr.png"]

@interface DWReceiveViewController () <DWAmountViewControllerDelegate>

@property (nonatomic, strong) UIImage *qrImage;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, assign) BOOL showTips;
@property (nonatomic, strong) NSUserDefaults *groupDefs;
@property (nonatomic, strong) id balanceObserver, txStatusObserver, txReceivedObserver;

@property (nonatomic, strong) IBOutlet UILabel *label;
@property (nonatomic, strong) IBOutlet UIButton *addressButton;
@property (nonatomic, strong) IBOutlet UIImageView *qrView;

@end

@implementation DWReceiveViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    DSWallet * wallet = [[DWEnvironment sharedInstance] currentWallet];
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSPaymentRequest *req;

    self.groupDefs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
    req = (_paymentRequest) ? _paymentRequest :
          [DSPaymentRequest requestWithString:[self.groupDefs stringForKey:APP_GROUP_RECEIVE_ADDRESS_KEY] onChain:wallet.chain];

    if (req.isValid) {
        if (! _qrImage) {
            _qrImage = [[UIImage imageWithData:[self.groupDefs objectForKey:APP_GROUP_QR_IMAGE_KEY]]
                        dw_resize:self.qrView.bounds.size withInterpolationQuality:kCGInterpolationNone];
        }
        
        self.qrView.image = _qrImage;
        [self.addressButton setTitle:req.paymentAddress forState:UIControlStateNormal];
    }
    else [self.addressButton setTitle:nil forState:UIControlStateNormal];
    
    if (req.amount > 0) {
        NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:req.amount withTintColor:[UIColor darkTextColor] useSignificantDigits:FALSE] mutableCopy];
        NSString * titleString = [NSString stringWithFormat:@" (%@)",
                                  [priceManager localCurrencyStringForDashAmount:req.amount]];
        [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor darkTextColor]}]];
        self.label.attributedText = attributedDashString;
    }

    self.addressButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    [self updateAddress];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self hideTips];
    
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.txReceivedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txReceivedObserver];
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (void)updateAddress
{
    //small hack to deal with bounds
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateAddress];
        });
        return;
    }
    CGSize qrViewBounds = (self.qrView ? self.qrView.bounds.size : CGSizeMake(250.0, 250.0));
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DSPaymentRequest *req = self.paymentRequest;
        UIImage *image = nil;
        
        if ([req.data isEqual:[self.groupDefs objectForKey:APP_GROUP_REQUEST_DATA_KEY]]) {
            image = [UIImage imageWithData:[self.groupDefs objectForKey:APP_GROUP_QR_IMAGE_KEY]];
        }
        
        if (! image && req.data) {
            image = [UIImage dw_imageWithQRCodeData:req.data color:[CIColor colorWithRed:0.0 green:141.0/255.0 blue:228.0/255.0]];
        }
        
        UIImage *overlayLogo = [UIImage imageNamed:@"dashQROverlay"];
        UIImage *resizedImage = [image dw_resize:qrViewBounds withInterpolationQuality:kCGInterpolationNone];
        
        CGSize holeSize = CGSizeMake(67.0, 67.0);
        resizedImage = [resizedImage dw_imageByCuttingHoleInCenterWithSize:holeSize];

        self.qrImage = [resizedImage dw_imageByMergingWithImage:overlayLogo];
        
        if (req.amount == 0) {
            if (req.isValid) {
                [self.groupDefs setObject:UIImagePNGRepresentation(image) forKey:APP_GROUP_QR_IMAGE_KEY];
                [self.groupDefs setObject:self.paymentAddress forKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
                [self.groupDefs setObject:req.data forKey:APP_GROUP_REQUEST_DATA_KEY];
            }
            else {
                [self.groupDefs removeObjectForKey:APP_GROUP_REQUEST_DATA_KEY];
                [self.groupDefs removeObjectForKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
                [self.groupDefs removeObjectForKey:APP_GROUP_QR_IMAGE_KEY];
            }

            [self.groupDefs synchronize];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.qrView.image = self.qrImage;
            [self.addressButton setTitle:self.paymentAddress forState:UIControlStateNormal];
            
            if (req.amount > 0) {
                DSPriceManager * priceManager = [DSPriceManager sharedInstance];
                NSMutableAttributedString * attributedDashString = [[priceManager attributedStringForDashAmount:req.amount withTintColor:[UIColor darkTextColor] useSignificantDigits:FALSE] mutableCopy];
                NSString * titleString = [NSString stringWithFormat:@" (%@)",
                                          [priceManager localCurrencyStringForDashAmount:req.amount]];
                [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor darkTextColor]}]];
                self.label.attributedText = attributedDashString;
                
                if (! self.balanceObserver) {
                    self.balanceObserver =
                    [[NSNotificationCenter defaultCenter] addObserverForName:DSWalletBalanceDidChangeNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
                            [self checkRequestStatus];
                        }];
                }
                
                if (! self.txStatusObserver) {
                    self.txStatusObserver =
                    [[NSNotificationCenter defaultCenter] addObserverForName:DSTransactionManagerTransactionStatusDidChangeNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
                            [self checkRequestStatus];
                        }];
                }
                
                if (! self.txReceivedObserver) {
                    self.txReceivedObserver =
                    [[NSNotificationCenter defaultCenter] addObserverForName:DSTransactionManagerTransactionReceivedNotification
                                                                      object:nil queue:nil usingBlock:^(NSNotification *note) {
                                                                          [self updateAddress];
                                                                      }];
                }
                
                
            }
        });
    });
}

- (void)checkRequestStatus
{
    DSPriceManager * priceManager = [DSPriceManager sharedInstance];
    DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
    DSChainManager * chainManager = [DWEnvironment sharedInstance].currentChainManager;
    DSPaymentRequest *req = self.paymentRequest;
    uint64_t total = 0, fuzz = [priceManager amountForLocalCurrencyString:[priceManager localCurrencyStringForDashAmount:1]]*2;
    
    if (! [wallet addressIsUsed:self.paymentAddress]) return;

    for (DSTransaction *tx in wallet.allTransactions) {
        if ([tx.outputAddresses containsObject:self.paymentAddress]) continue;
        if (tx.blockHeight == TX_UNCONFIRMED &&
            [chainManager.transactionManager relayCountForTransaction:tx.txHash] < PEER_MAX_CONNECTIONS) continue;
        total += [wallet amountReceivedFromTransaction:tx];
                 
        if (total + fuzz >= req.amount) {
            UIView *view = self.navigationController.presentingViewController.view;

            [self done:nil];
            [view addSubview:[[[BRBubbleView viewWithText:[NSString
             stringWithFormat:NSLocalizedString(@"received %@ (%@)", nil), [priceManager stringForDashAmount:total],
             [priceManager localCurrencyStringForDashAmount:total]]
             center:CGPointMake(view.bounds.size.width/2, view.bounds.size.height/2)] popIn] popOutAfterDelay:3.0]];
            break;
        }
    }
}

- (DSPaymentRequest *)paymentRequest
{
    if (_paymentRequest) return _paymentRequest;
    return [DSPaymentRequest requestWithString:self.paymentAddress onChain:[DWEnvironment sharedInstance].currentChain];
}

- (NSString *)paymentAddress
{
    if (_paymentRequest) return _paymentRequest.paymentAddress;
    return [DWEnvironment sharedInstance].currentAccount.receiveAddress;
}

- (BOOL)nextTip
{
    if (self.tipView.alpha < 0.5) return [(id)self.parentViewController.parentViewController nextTip];

    BRBubbleView *tipView = self.tipView;

    self.tipView = nil;
    [tipView popOut];

    if ([tipView.text hasPrefix:QR_TIP]) {
        self.tipView = [BRBubbleView viewWithText:ADDRESS_TIP tipPoint:[self.addressButton.superview
                        convertPoint:CGPointMake(self.addressButton.center.x, self.addressButton.center.y - 10.0)
                        toView:self.view] tipDirection:BRBubbleTipDirectionDown];
        self.tipView.backgroundColor = tipView.backgroundColor;
        self.tipView.font = tipView.font;
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips && [tipView.text hasPrefix:ADDRESS_TIP]) {
        self.showTips = NO;
        [(id)self.parentViewController.parentViewController tip:self];
    }

    return YES;
}

- (void)hideTips
{
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

// MARK: - IBAction

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
    self.tipView.font = [UIFont systemFontOfSize:14.0];
    [self.view addSubview:[self.tipView popIn]];
}

- (IBAction)address:(id)sender
{
    if ([self nextTip]) return;
    [DSEventManager saveEvent:@"receive:address"];

    BOOL req = (_paymentRequest) ? YES : NO;

    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Receive dash at this address: %@", nil),
                                                                                  self.paymentAddress] message:@"" preferredStyle:UIAlertControllerStyleActionSheet];
    [actionSheet addAction:[UIAlertAction actionWithTitle:(req) ? NSLocalizedString(@"copy request to clipboard", nil) :
                            NSLocalizedString(@"copy address to clipboard", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                [UIPasteboard generalPasteboard].string = (self.paymentRequest.amount > 0) ? self.paymentRequest.string :
                                self.paymentAddress;
                                NSLog(@"\n\nCOPIED PAYMENT REQUEST/ADDRESS:\n\n%@", [UIPasteboard generalPasteboard].string);
                                
                                [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"copied", nil)
                                                                            center:CGPointMake(self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0 - 130.0)] popIn]
                                                       popOutAfterDelay:2.0]];
                                [DSEventManager saveEvent:@"receive:copy_address"];
    }]];

    if ([MFMailComposeViewController canSendMail]) {
        [actionSheet addAction:[UIAlertAction actionWithTitle:(req) ? NSLocalizedString(@"send request as email", nil) :
                                NSLocalizedString(@"send address as email", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                    if ([MFMailComposeViewController canSendMail]) {
                                        MFMailComposeViewController *composeController = [MFMailComposeViewController new];
                                        
                                        composeController.subject = NSLocalizedString(@"Dash address", nil);
                                        [composeController setMessageBody:self.paymentRequest.string isHTML:NO];
                                        [composeController addAttachmentData:UIImagePNGRepresentation(self.qrView.image) mimeType:@"image/png"
                                                                    fileName:@"qr.png"];
                                        composeController.mailComposeDelegate = self;
                                        [self.navigationController presentViewController:composeController animated:YES completion:nil];
                                        composeController.view.backgroundColor =
                                        [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default"]];
                                        [DSEventManager saveEvent:@"receive:send_email"];
                                    }
                                    else {
                                        [DSEventManager saveEvent:@"receive:email_not_configured"];
                                        UIAlertController * alert = [UIAlertController
                                                                     alertControllerWithTitle:@""
                                                                     message:NSLocalizedString(@"email not configured", nil)
                                                                     preferredStyle:UIAlertControllerStyleAlert];
                                        UIAlertAction* okButton = [UIAlertAction
                                                                   actionWithTitle:NSLocalizedString(@"ok", nil)
                                                                   style:UIAlertActionStyleCancel
                                                                   handler:^(UIAlertAction * action) {
                                                                   }];
                                        [alert addAction:okButton];
                                        [self presentViewController:alert animated:YES completion:nil];
                                        
                                    }
                                }]];
    }

#if ! TARGET_IPHONE_SIMULATOR
    if ([MFMessageComposeViewController canSendText]) {
        [actionSheet addAction:[UIAlertAction actionWithTitle:(req) ? NSLocalizedString(@"send request as message", nil) :
                                NSLocalizedString(@"send address as message", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                    if ([MFMessageComposeViewController canSendText]) {
                                        MFMessageComposeViewController *composeController = [MFMessageComposeViewController new];
                                        
                                        if ([MFMessageComposeViewController canSendSubject]) {
                                            composeController.subject = NSLocalizedString(@"Dash address", nil);
                                        }
                                        
                                        composeController.body = self.paymentRequest.string;
                                        
                                        if ([MFMessageComposeViewController canSendAttachments]) {
                                            [composeController addAttachmentData:UIImagePNGRepresentation(self.qrView.image)
                                                                  typeIdentifier:(NSString *)kUTTypePNG filename:@"qr.png"];
                                        }
                                        
                                        composeController.messageComposeDelegate = self;
                                        [self.navigationController presentViewController:composeController animated:YES completion:nil];
                                        composeController.view.backgroundColor = [UIColor colorWithPatternImage:
                                                                                  [UIImage imageNamed:@"wallpaper-default"]];
                                        [DSEventManager saveEvent:@"receive:send_message"];
                                    }
                                    else {
                                        [DSEventManager saveEvent:@"receive:message_not_configured"];
                                        UIAlertController * alert = [UIAlertController
                                                                     alertControllerWithTitle:@""
                                                                     message:NSLocalizedString(@"sms not currently available", nil)
                                                                     preferredStyle:UIAlertControllerStyleAlert];
                                        UIAlertAction* okButton = [UIAlertAction
                                                                   actionWithTitle:NSLocalizedString(@"ok", nil)
                                                                   style:UIAlertActionStyleCancel
                                                                   handler:^(UIAlertAction * action) {
                                                                   }];
                                        [alert addAction:okButton];
                                        [self presentViewController:alert animated:YES completion:nil];
                                    }
                                }]];
    }
#endif

    if (! req) {
        [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"request an amount", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            DWAmountViewController *amountController = [DWAmountViewController requestController];
            amountController.delegate = self;
            DWAmountNavigationController *amountNavigationController = [[DWAmountNavigationController alloc] initWithRootViewController:amountController];
            [self.navigationController presentViewController:amountNavigationController animated:YES completion:nil];
            [DSEventManager saveEvent:@"receive:request_amount"];
        }]];
    }
    [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        
    }]];
    if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
    {
        [actionSheet setModalPresentationStyle:UIModalPresentationPopover];
        actionSheet.popoverPresentationController.sourceView = sender;
        actionSheet.popoverPresentationController.sourceRect = ((UIButton*)sender).bounds;
        actionSheet.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    
    [actionSheet addAction:(id)[NSDictionary new]];

    // Present action sheet.
    [self presentViewController:actionSheet animated:YES completion:nil];
}

// MARK: - MFMessageComposeViewControllerDelegate

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
didFinishWithResult:(MessageComposeResult)result
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

// MARK: - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result
error:(NSError *)error
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

// MARK: - DWAmountViewControllerDelegate

- (void)amountViewControllerDidCancel:(DWAmountViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)amountViewController:(DWAmountViewController *)controller didInputAmount:(uint64_t)amount {
    [DSEventManager saveEvent:@"receive:show_request"];
    UINavigationController *navController = (UINavigationController *)self.navigationController.presentedViewController;
    DWReceiveViewController *receiveController = [self.storyboard
                                                  instantiateViewControllerWithIdentifier:@"RequestViewController"];
    
    receiveController.paymentRequest = self.paymentRequest;
    receiveController.paymentRequest.amount = amount;
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSNumber *number = [priceManager localCurrencyNumberForDashAmount:amount];
    if (number) {
        receiveController.paymentRequest.requestedFiatCurrencyAmount = number.floatValue;
    }
    receiveController.paymentRequest.requestedFiatCurrencyCode = priceManager.localCurrencyCode;
    receiveController.view.backgroundColor = self.parentViewController.parentViewController.view.backgroundColor;
    navController.delegate = receiveController;
    [navController pushViewController:receiveController animated:YES];
}

// MARK: - UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return 0.35;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    UIView *containerView = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];

    [containerView addSubview:to.view];
    
    [UIView transitionFromView:from.view toView:to.view duration:[self transitionDuration:transitionContext]
    options:UIViewAnimationOptionTransitionFlipFromLeft completion:^(BOOL finished) {
        [from.view removeFromSuperview];
        [transitionContext completeTransition:YES];
    }];
}

// MARK: - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC
toViewController:(UIViewController *)toVC
{
    return self;
}

// MARK: - UIViewControllerTransitioningDelegate

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
