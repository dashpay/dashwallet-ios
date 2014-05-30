//
//  BRSendViewController.m
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

#import "BRSendViewController.h"
#import "BRRootViewController.h"
#import "BRAmountViewController.h"
#import "BRBubbleView.h"
#import "BRWalletManager.h"
#import "BRWallet.h"
#import "BRPeerManager.h"
#import "BRPaymentRequest.h"
#import "BRPaymentProtocol.h"
#import "BRKey.h"
#import "BRTransaction.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import <AVFoundation/AVFoundation.h>

#define SCAN_TIP      NSLocalizedString(@"Scan someone else's QR code to get their bitcoin address. "\
                                         "You can send a payment to anyone with an address.", nil)
#define CLIPBOARD_TIP NSLocalizedString(@"Bitcoin addresses can also be copied to the clipboard. "\
                                         "A bitcoin address always starts with '1'.", nil)

#define LOCK @"\xF0\x9F\x94\x92" // unicode lock symbol U+1F512 (utf-8)
#define REDX @"\xE2\x9D\x8C"     // unicode cross mark U+274C, red x emoji (utf-8)

@interface BRSendViewController ()

@property (nonatomic, strong) NSString *addressInWallet, *txName, *txMemo;
@property (nonatomic, assign) BOOL txSecure, clearClipboard, showTips;
@property (nonatomic, strong) id urlObserver, fileObserver;
@property (nonatomic, strong) BRTransaction *sweepTx, *tx, *txWithFee;
@property (nonatomic, strong) BRPaymentProtocolRequest *protocolRequest;
@property (nonatomic, strong) ZBarReaderViewController *zbarController;
@property (nonatomic, strong) BRBubbleView *tipView;

@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *buttons;

@end

@implementation BRSendViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    //TODO: add a field for manually entering a payment address

    self.urlObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRURLNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            NSURL *url = note.userInfo[@"url"];
            
            if ([url.scheme isEqual:@"bitcoin"]) {
                [self confirmRequest:[BRPaymentRequest requestWithURL:url]];
                return;
            }

            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"unsupported url", nil) message:url.absoluteString
              delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self reset:nil];
        }];

    self.fileObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRFileNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            NSData *file = note.userInfo[@"file"];
            BRPaymentProtocolRequest *request = [BRPaymentProtocolRequest requestWithData:file];
            
            if (request) {
                [self confirmProtocolRequest:request];
                return;
            }

            // TODO: reject payments that don't match requested amounts/scripts, implement refunds
            BRPaymentProtocolPayment *payment = [BRPaymentProtocolPayment paymentWithData:file];
            
            if (payment.transactions.count > 0) {
                for (BRTransaction *tx in payment.transactions) {
                    [(id)self.parentViewController.parentViewController startActivityWithTimeout:30];

                    [[BRPeerManager sharedInstance] publishTransaction:tx completion:^(NSError *error) {
                        [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

                        if (error) {
                            [[[UIAlertView alloc]
                              initWithTitle:NSLocalizedString(@"couldn't transmit payment to bitcoin network", nil)
                              message:error.localizedDescription delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                        }

                        [self.view addSubview:[[[BRBubbleView
                         viewWithText:(payment.memo.length > 0 ? payment.memo : NSLocalizedString(@"recieved", nil))
                         center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                         popOutAfterDelay:(payment.memo.length > 10 ? 3.0 : 2.0)]];
                    }];
                }

                return;
            }
            
            BRPaymentProtocolACK *ack = [BRPaymentProtocolACK ackWithData:file];
            
            if (ack) {
                if (ack.memo.length > 0) {
                    [self.view
                     addSubview:[[[BRBubbleView viewWithText:ack.memo
                                   center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)]
                                  popIn] popOutAfterDelay:2.0]];
                }

                return;
            }
            
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"unsupported or corrupted document", nil) message:nil
              delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        }];

}

- (void)dealloc
{
    if (self.urlObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    if (self.fileObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.fileObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self cancel:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self zbarController]; // pre-load zbarController
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self hideTips];

    [super viewWillDisappear:animated];
}

- (ZBarReaderViewController *)zbarController
{
    if (! _zbarController) {
        _zbarController = [ZBarReaderViewController new];
        _zbarController.readerDelegate = self;
        _zbarController.cameraOverlayView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"cameraguide.png"]];
        _zbarController.cameraOverlayView.center = CGPointMake(_zbarController.view.center.x,
                                                               _zbarController.view.center.y - 10.0);
    }

    return _zbarController;
}

- (void)confirmTransaction:(BRTransaction *)tx name:(NSString *)name memo:(NSString *)memo isSecure:(BOOL)isSecure
{
    if (! tx) {
        [self cancel:nil];
        return;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];
    uint64_t txAmount = [m.wallet amountSentByTransaction:tx] - [m.wallet amountReceivedFromTransaction:tx];
    NSString *amount = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:txAmount],
                        [m localCurrencyStringForAmount:txAmount]];
    NSString *msg = (isSecure && name.length > 0) ? LOCK @" " : @"";

    if (! isSecure && self.protocolRequest.errorMessage.length > 0) msg = [msg stringByAppendingString:REDX @" "];
    if (name.length > 0) msg = [msg stringByAppendingString:name];
    if (! isSecure && msg.length > 0) msg = [msg stringByAppendingString:@"\n"];
    if (! isSecure || msg.length == 0) msg = [msg stringByAppendingString:[m.wallet addressForTransaction:tx]];
    if (memo.length > 0) msg = [[msg stringByAppendingString:@"\n"] stringByAppendingString:memo];

    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"confirm payment", nil) message:msg delegate:self
      cancelButtonTitle:NSLocalizedString(@"cancel", nil) otherButtonTitles:amount, nil] show];
}

- (void)confirmRequest:(BRPaymentRequest *)request
{
    if (! [request isValid]) {
        if ([request.paymentAddress isValidBitcoinPrivateKey] || [request.paymentAddress isValidBitcoinBIP38Key]) {
            [self confirmSweep:request.paymentAddress];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"not a valid bitcoin address", nil)
              message:request.paymentAddress delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
              otherButtonTitles:nil] show];
            [self cancel:nil];
        }

        return;
    }

    if (request.r.length > 0) { // payment protocol over HTTP
        [(id)self.parentViewController.parentViewController startActivityWithTimeout:20];

        [BRPaymentRequest fetch:request.r completion:^(BRPaymentProtocolRequest *req, NSError *error) {
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

            if (error) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                  message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                  otherButtonTitles:nil] show];
                [self cancel:nil];
            }
            else [self confirmProtocolRequest:req];
        }];

        return;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];

    if ([m.wallet containsAddress:request.paymentAddress]) {
        [[[UIAlertView alloc] initWithTitle:nil
          message:NSLocalizedString(@"this payment address is already in your wallet", nil)
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];

        self.addressInWallet = request.paymentAddress;
        [self cancel:nil];
    }
    else if (request.amount == 0) {
        BRAmountViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"AmountViewController"];

        c.delegate = self;
        c.request = request;
        c.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                  [m localCurrencyStringForAmount:m.wallet.balance]];
        [self.navigationController pushViewController:c animated:YES];
    }
    else if (request.amount < TX_MIN_OUTPUT_AMOUNT) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin payments can't be less than %@", nil),
                   [m stringForAmount:TX_MIN_OUTPUT_AMOUNT]] delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
    }
    else {
        self.tx = [m.wallet transactionFor:request.amount to:request.paymentAddress withFee:NO];
        self.txWithFee = [m.wallet transactionFor:request.amount to:request.paymentAddress withFee:YES];

        if (! self.tx) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"insufficient funds", nil) message:nil delegate:nil
              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self cancel:nil];
        }

        [self confirmTransaction:self.tx name:request.label memo:request.message isSecure:NO];
    }
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)request
{
    BOOL valid = [request isValid];

    if (! valid && [request.errorMessage isEqual:NSLocalizedString(@"request expired", nil)]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"bad payment request", nil) message:request.errorMessage
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];

    self.tx = [m.wallet transactionForAmounts:request.details.outputAmounts
               toOutputScripts:request.details.outputScripts withFee:NO];
    self.txWithFee = [m.wallet transactionForAmounts:request.details.outputAmounts
                      toOutputScripts:request.details.outputScripts withFee:YES];
    self.protocolRequest = request;

    if (! self.tx) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"insufficient funds", nil) message:nil delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
    }

    [self confirmTransaction:self.tx name:request.commonName memo:request.details.memo
     isSecure:(valid && ! [request.pkiType isEqual:@"none"]) ? YES : NO];
}

- (void)confirmSweep:(NSString *)privKey
{
    if (! [privKey isValidBitcoinPrivateKey] && ! [privKey isValidBitcoinBIP38Key]) return;

    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRBubbleView *v = [BRBubbleView viewWithText:NSLocalizedString(@"checking private key balance...", nil)
                       center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];

    v.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    v.customView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [(id)v.customView startAnimating];
    [self.view addSubview:[v popIn]];

    [m sweepPrivateKey:privKey withFee:YES completion:^(BRTransaction *tx, NSError *error) {
        [v popOut];

        if (error) {
            [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:self
              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self cancel:nil];
        }
        else if (tx) {
            uint64_t fee = tx.standardFee, amount = fee;

            for (NSNumber *amt in tx.outputAmounts) {
                amount += amt.unsignedLongLongValue;
            }

            self.sweepTx = tx;

            [[[UIAlertView alloc] initWithTitle:nil message:[NSString
              stringWithFormat:NSLocalizedString(@"Send %@ (%@) from this private key into your wallet? "
                                                 "The bitcoin network will receive a fee of %@ (%@).", nil),
              [m stringForAmount:amount], [m localCurrencyStringForAmount:amount], [m stringForAmount:fee],
              [m localCurrencyStringForAmount:fee]] delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
              otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:amount],
                                 [m localCurrencyStringForAmount:amount]], nil] show];
        }
        else [self cancel:nil];
    }];
}

- (void)hideTips
{
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

- (BOOL)nextTip
{
    if (self.tipView.alpha < 0.5) return [(id)self.parentViewController.parentViewController nextTip];

    BRBubbleView *v = self.tipView;

    self.tipView = nil;
    [v popOut];
    
    if ([v.text isEqual:SCAN_TIP]) {
        UIButton *b = self.buttons.lastObject;

        self.tipView = [BRBubbleView viewWithText:CLIPBOARD_TIP tipPoint:CGPointMake(b.center.x, b.center.y + 10.0)
                        tipDirection:BRBubbleTipDirectionUp];
        self.tipView.backgroundColor = v.backgroundColor;
        self.tipView.font = v.font;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips && [v.text isEqual:CLIPBOARD_TIP]) {
        self.showTips = NO;
        [(id)self.parentViewController.parentViewController tip:self];
    }

    return YES;
}

#pragma mark - IBAction

- (IBAction)tip:(id)sender
{
    if ([self nextTip]) return;

    if (! [sender isKindOfClass:[UIGestureRecognizer class]] || ! [[sender view] isKindOfClass:[UILabel class]]) {
        if (! [sender isKindOfClass:[UIViewController class]]) return;
        self.showTips = YES;
    }

    UIButton *b = self.buttons.firstObject;

    self.tipView = [BRBubbleView viewWithText:SCAN_TIP tipPoint:CGPointMake(b.center.x, b.center.y - 10.0)
                    tipDirection:BRBubbleTipDirectionDown];


    self.tipView.backgroundColor = [UIColor orangeColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    [self.view addSubview:[self.tipView popIn]];
}

- (IBAction)swipeLeft:(id)sender
{
    // the following is a hack to avoid triggering a crash bug in UIQueuingScrollView described here:
    // http://stackoverflow.com/questions/19939030/how-to-solve-failed-to-determine-navigation-direction-for-scroll-bug
    // we do the animated scroll manually and call pageviewcontroller setviewcontrollers without animation afterward

    for (UIView *view in self.parentViewController.view.subviews) {
        if (! [view isKindOfClass:[UIScrollView class]]) continue;
        [(id)view setContentOffset:CGPointMake([(id)view contentOffset].x + view.frame.size.width,
                                               [(id)view contentOffset].y) animated:YES];
        break;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [(id)self.parentViewController
         setViewControllers:@[[(id)self.parentViewController.parentViewController receiveViewController]]
         direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    });
}

- (IBAction)scanQR:(id)sender
{
    if ([self nextTip]) return;

    [sender setEnabled:NO];

    [self.navigationController presentViewController:self.zbarController animated:YES completion:^{
        NSLog(@"present qr reader complete");
    }];

    BOOL hasFlash = [[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] hasTorch];
    UIBarButtonItem *flashButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"flash.png"]
                                    style:UIBarButtonItemStylePlain target:self action:@selector(flash:)];

    // replace zbarController.view info button with flash toggle
    for (UIView *v in self.zbarController.view.subviews) {
        for (id t in v.subviews) {
            if ([t isKindOfClass:[UIToolbar class]] && [[t items] count] > 1) {
                UIBarButtonItem *cancelButton =
                    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                     target:[(UIBarButtonItem *)[t items][0] target] action:[(UIBarButtonItem *)[t items][0] action]];

                [t setItems:hasFlash ? @[cancelButton, [t items][1], flashButton] : @[cancelButton, [t items][1]]];
            }
        }
    }
}

- (IBAction)payToClipboard:(id)sender
{
    if ([self nextTip]) return;

    NSString *s = [[[UIPasteboard generalPasteboard] string]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BRPaymentRequest *req = [BRPaymentRequest requestWithString:s];

    [sender setEnabled:NO];
    self.clearClipboard = YES;

    if (! [req isValid] && ! [s isValidBitcoinPrivateKey] && ! [s isValidBitcoinBIP38Key]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"clipboard doesn't contain a valid bitcoin address", nil)
          message:nil delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
    }
    else [self confirmRequest:req];
}

- (IBAction)reset:(id)sender
{
    if (self.navigationController.topViewController != self.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }

    if (self.clearClipboard) [[UIPasteboard generalPasteboard] setString:@""];
    [self cancel:sender];
}

- (IBAction)cancel:(id)sender
{
    self.tx = self.txWithFee = self.sweepTx = nil;
    self.protocolRequest = nil;
    self.txName = self.txMemo = nil;
    self.txSecure = self.clearClipboard = NO;

    for (UIButton *button in self.buttons) {
        button.enabled = YES;
    }
}

- (IBAction)flash:(id)sender
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];

    device.torchMode = device.torchActive ? AVCaptureTorchModeOff : AVCaptureTorchModeOn;
}

#pragma mark - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount
{
    amountViewController.request.amount = amount;
    [self confirmRequest:amountViewController.request];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)reader didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    // ignore additonal qr codes while we're still giving visual feedback about the current one
    if ([[(id)self.zbarController.cameraOverlayView image] isEqual:[UIImage imageNamed:@"cameraguide-green.png"]]) {
        return;
    }

    for (id result in info[ZBarReaderControllerResults]) {
        NSString *s = (id)[result data];
        BRPaymentRequest *request = [BRPaymentRequest requestWithString:s];

        if (! [request isValid] && ! [s isValidBitcoinPrivateKey] && ! [s isValidBitcoinBIP38Key]) {
            [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide-red.png"]];

            // display red camera guide for 0.5 seconds
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide.png"]];

                if ([s hasPrefix:@"bitcoin:"] || [request.paymentAddress hasPrefix:@"1"]) {
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"not a valid bitcoin address", nil)
                      message:request.paymentAddress delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                      otherButtonTitles:nil] show];
                }
                else {
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"not a bitcoin QR code", nil) message:nil
                      delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                }
            });
        }
        else {
            [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide-green.png"]];

            if (request.r.length > 0) { // start fetching payment protocol request right away
                [BRPaymentRequest fetch:request.r completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                    if (error) {
                        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                          message:error.localizedDescription delegate:nil
                          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                        [self cancel:nil];
                        return;
                    }

                    dispatch_async(dispatch_get_main_queue(), ^{
                        [reader dismissViewControllerAnimated:YES completion:^{
                            [(id)self.zbarController.cameraOverlayView
                             setImage:[UIImage imageNamed:@"cameraguide.png"]];
                        }];

                        [self confirmProtocolRequest:req];
                    });
                }];
            }
            else {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [reader dismissViewControllerAnimated:YES completion:^{
                        [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide.png"]];
                    }];

                    [self confirmRequest:request];
                });
            }
        }

        break;
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self cancel:nil];
        return;
    }

    if (self.sweepTx) {
        [(id)self.parentViewController.parentViewController startActivityWithTimeout:30];

        [[BRPeerManager sharedInstance] publishTransaction:self.sweepTx completion:^(NSError *error) {
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

            if (error) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't sweep balance", nil)
                  message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                  otherButtonTitles:nil] show];
                [self cancel:nil];
                return;
            }

            [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"swept!", nil)
                                     center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)]
                                    popIn] popOutAfterDelay:2.0]];
            [self reset:nil];
        }];

        return;
    }
    else if (! self.tx) return;

    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRPaymentProtocolRequest *request = self.protocolRequest;
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    uint32_t freeHeight = [m.wallet blockHeightUntilFree:self.tx];

    if ([title hasPrefix:@"+ "] || [title isEqual:NSLocalizedString(@"no fee", nil)]) {
        if ([title hasPrefix:@"+ "]) self.tx = self.txWithFee;

        if (! self.tx) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"insufficient funds", nil) message:nil delegate:nil
              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }
    }
    else if (self.tx != self.txWithFee && freeHeight > [[BRPeerManager sharedInstance] lastBlockHeight] + 1) {
        uint64_t txFee = self.txWithFee ? [m.wallet feeForTransaction:self.txWithFee] : self.tx.standardFee;
        NSString *fee = [m stringForAmount:txFee];
        NSString *localCurrencyFee = [m localCurrencyStringForAmount:txFee];

        //if (freeHeight != TX_UNCONFIRMED) {
        //    NSTimeInterval t = (freeHeight - [[BRPeerManager sharedInstance] lastBlockHeight])*600;
        //    int minutes = t/60, hours = t/(60*60), days = t/(60*60*24);
        //    NSString *time = [NSString stringWithFormat:@"%d %@%@", days ? days : (hours ? hours : minutes),
        //                      days ? @"day" : (hours ? @"hour" : @"minutes"),
        //                      days > 1 ? @"s" : (days == 0 && hours > 1 ? @"s" : @"")];
        //
        //    [[[UIAlertView alloc]
        //      initWithTitle:[NSString stringWithFormat:@"%@ (%@) transaction fee recommended", fee, localCurrencyFee]
        //      message:[NSString stringWithFormat:@"estimated confirmation time with no fee: %@", time] delegate:self
        //      cancelButtonTitle:nil otherButtonTitles:@"no fee",
        //      [NSString stringWithFormat:@"+ %@ (%@)", fee, localCurrencyFee], nil] show];
        //    return;
        //}

        [[[UIAlertView alloc] initWithTitle:nil message:[NSString
          stringWithFormat:NSLocalizedString(@"the bitcoin network will receive a fee of %@ (%@)", nil), fee,
          localCurrencyFee] delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
          otherButtonTitles:[NSString stringWithFormat:@"+ %@ (%@)", fee, localCurrencyFee], nil] show];
        return;
    }

    //TODO: check for duplicate transactions

    NSLog(@"signing transaction");
    [m.wallet signTransaction:self.tx];

    if (! [self.tx isSigned]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:NSLocalizedString(@"error signing bitcoin transaction", nil) delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    NSLog(@"signed transaction:\n%@", [NSString hexWithData:self.tx.data]);

    [(id)self.parentViewController.parentViewController startActivityWithTimeout:30];

    [[BRPeerManager sharedInstance] publishTransaction:self.tx completion:^(NSError *error) {
        if (request.details.paymentURL.length > 0) return;
        [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

        if (error) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
              message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
              otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }

        [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"sent!", nil)
                                 center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)]
                                popIn] popOutAfterDelay:2.0]];
        [self reset:nil];
    }];

    if (request.details.paymentURL.length > 0) {
        uint64_t refundAmount = 0;
        NSMutableData *refundScript = [NSMutableData data];

        // use the payment transaction's change address as the refund address
        [refundScript appendScriptPubKeyForAddress:m.wallet.changeAddress];

        for (NSNumber *amount in request.details.outputAmounts) {
            refundAmount += [amount unsignedLongLongValue];
        }

        // TODO: XXXX keep track of commonName/memo to associate them with outputScripts
        BRPaymentProtocolPayment *payment =
            [[BRPaymentProtocolPayment alloc] initWithMerchantData:request.details.merchantData
             transactions:@[self.tx] refundToAmounts:@[@(refundAmount)] refundToScripts:@[refundScript] memo:nil];
        
        [BRPaymentRequest postPayment:payment to:request.details.paymentURL
        completion:^(BRPaymentProtocolACK *ack, NSError *error) {
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

            if (error && ! [m.wallet transactionIsRegistered:self.tx.txHash]) {
                [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:nil
                  cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                [self cancel:nil];
                return;
            }
            
            [self.view addSubview:[[[BRBubbleView
             viewWithText:(ack.memo.length > 0 ? ack.memo : NSLocalizedString(@"sent!", nil))
             center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
             popOutAfterDelay:(ack.memo.length > 10 ? 3.0 : 2.0)]];
            [self reset:nil];
            
            if (error) { // transaction was sent despite payment protocol error
                [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:nil
                  cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] performSelector:@selector(show)
                 withObject:nil afterDelay:2.0];
            }
        }];
    }
}

@end
