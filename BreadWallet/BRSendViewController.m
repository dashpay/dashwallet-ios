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
#import "BRScanViewController.h"
#import "BRAmountViewController.h"
#import "BRSettingsViewController.h"
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

#define SCAN_TIP      NSLocalizedString(@"Scan someone else's QR code to get their bitcoin address. "\
                                         "You can send a payment to anyone with an address.", nil)
#define CLIPBOARD_TIP NSLocalizedString(@"Bitcoin addresses can also be copied to the clipboard. "\
                                         "A bitcoin address always starts with '1'.", nil)

#define LOCK @"\xF0\x9F\x94\x92" // unicode lock symbol U+1F512 (utf-8)
#define REDX @"\xE2\x9D\x8C"     // unicode cross mark U+274C, red x emoji (utf-8)

@interface BRSendViewController ()

@property (nonatomic, assign) BOOL clearClipboard, showTips, didAskFee, removeFee;
@property (nonatomic, strong) BRTransaction *tx, *sweepTx;
@property (nonatomic, strong) BRPaymentRequest *request;
@property (nonatomic, strong) BRPaymentProtocolRequest *protocolRequest;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, strong) BRScanViewController *scanController;

@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *buttons;

@end

@implementation BRSendViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self cancel:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    if (! self.scanController) {
        self.scanController = [self.storyboard instantiateViewControllerWithIdentifier:@"ScanViewController"];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self hideTips];

    [super viewWillDisappear:animated];
}

- (void)handleURL:(NSURL *)url
{
    if ([url.scheme isEqual:@"bitcoin"]) {
        [self confirmRequest:[BRPaymentRequest requestWithURL:url]];
    }
    else {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"unsupported url", nil) message:url.absoluteString
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    }
}

- (void)handleFile:(NSData *)file
{
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
                      message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                      otherButtonTitles:nil] show];
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
            [self.view addSubview:[[[BRBubbleView viewWithText:ack.memo
             center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
             popOutAfterDelay:2.0]];
        }

        return;
    }

    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"unsupported or corrupted document", nil) message:nil
      delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
}

- (void)confirmAmount:(uint64_t)amount fee:(uint64_t)fee address:(NSString *)address name:(NSString *)name
memo:(NSString *)memo isSecure:(BOOL)isSecure
{
    NSMutableString *safeName = [NSMutableString stringWithString:name ? name : @""],
                    *safeMemo = [NSMutableString stringWithString:memo ? memo : @""];

    // sanitize strings before displaying to user
    CFStringTransform((CFMutableStringRef)safeName, NULL, kCFStringTransformToUnicodeName, NO);
    CFStringTransform((CFMutableStringRef)safeMemo, NULL, kCFStringTransformToUnicodeName, NO);
    address = [NSString base58WithData:[address base58ToData]];

    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSString *amountStr = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:amount],
                           [m localCurrencyStringForAmount:amount]];
    NSString *msg = (isSecure && safeName.length > 0) ? LOCK @" " : @"";

    if (! isSecure && self.protocolRequest.errorMessage.length > 0) msg = [msg stringByAppendingString:REDX @" "];
    if (safeName.length > 0) msg = [msg stringByAppendingString:safeName];
    if (! isSecure && msg.length > 0) msg = [msg stringByAppendingString:@"\n"];
    if (! isSecure || msg.length == 0) msg = [msg stringByAppendingString:address];

    msg = [msg stringByAppendingFormat:@"\n%@ (%@)", [m stringForAmount:amount - fee],
           [m localCurrencyStringForAmount:amount - fee]];

    if (fee > 0) {
        msg = [msg stringByAppendingFormat:NSLocalizedString(@"\nbitcoin network fee + %@ (%@)", nil),
               [m stringForAmount:fee], [m localCurrencyStringForAmount:fee]];
    }

    if (safeMemo.length > 0) msg = [[msg stringByAppendingString:@"\n"] stringByAppendingString:safeMemo];

    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"confirm payment", nil) message:msg delegate:self
      cancelButtonTitle:NSLocalizedString(@"cancel", nil) otherButtonTitles:amountStr, nil] show];
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
        self.request = request;
        self.tx = [m.wallet transactionFor:request.amount to:request.paymentAddress withFee:NO];

        uint64_t amount = (! self.tx) ? request.amount :
                          [m.wallet amountSentByTransaction:self.tx] - [m.wallet amountReceivedFromTransaction:self.tx];
        uint64_t fee = 0;

        if (self.tx && [m.wallet blockHeightUntilFree:self.tx] <= [[BRPeerManager sharedInstance] lastBlockHeight] +1 &&
            ! self.didAskFee && [[NSUserDefaults standardUserDefaults] boolForKey:SETTINGS_SKIP_FEE_KEY]) {
            [[[UIAlertView alloc] initWithTitle:nil message:[NSString
             stringWithFormat:NSLocalizedString(@"The standard bitcoin network fee is %@ (%@). "
                                                "Removing this fee may increase confirmation time.", nil),
             [m stringForAmount:self.tx.standardFee], [m localCurrencyStringForAmount:self.tx.standardFee]]
             delegate:self cancelButtonTitle:nil
             otherButtonTitles:NSLocalizedString(@"remove fee", nil), NSLocalizedString(@"continue", nil), nil] show];
            return;
        }

        if (! self.removeFee) {
            fee = self.tx.standardFee;
            amount += fee;
            self.tx = [m.wallet transactionFor:request.amount to:request.paymentAddress withFee:YES];
            if (self.tx) {
                amount = [m.wallet amountSentByTransaction:self.tx] - [m.wallet amountReceivedFromTransaction:self.tx];
                fee = [m.wallet feeForTransaction:self.tx];
            }
        }

        [self confirmAmount:amount fee:fee address:request.paymentAddress name:request.label memo:request.message
         isSecure:NO];
    }
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)protoReq
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    uint64_t amount = 0, fee = 0;
    NSString *address = @"";
    BOOL valid = [protoReq isValid];

    if (! valid && [protoReq.errorMessage isEqual:NSLocalizedString(@"request expired", nil)]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"bad payment request", nil) message:protoReq.errorMessage
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    //TODO: check for duplicates of already paid requests

    //TODO: XXXX handle 0 amounts, amount below tx_min_output_amount, and own address

    self.protocolRequest = protoReq;
    self.tx = [m.wallet transactionForAmounts:protoReq.details.outputAmounts
               toOutputScripts:protoReq.details.outputScripts withFee:NO];

    if (self.tx && [m.wallet blockHeightUntilFree:self.tx] <= [[BRPeerManager sharedInstance] lastBlockHeight] + 1 &&
        ! self.didAskFee && [[NSUserDefaults standardUserDefaults] boolForKey:SETTINGS_SKIP_FEE_KEY]) {
        [[[UIAlertView alloc] initWithTitle:nil message:[NSString
          stringWithFormat:NSLocalizedString(@"The standard bitcoin network fee is %@ (%@). "
                                             "Removing this fee may increase confirmation time.", nil),
          [m stringForAmount:self.tx.standardFee], [m localCurrencyStringForAmount:self.tx.standardFee]]
          delegate:self cancelButtonTitle:nil
          otherButtonTitles:NSLocalizedString(@"remove fee", nil), NSLocalizedString(@"continue", nil), nil] show];
        return;
    }

    if (! self.tx) {
        for (NSNumber *n in protoReq.details.outputAmounts) {
            amount += [n unsignedLongLongValue];
        }
    }
    else amount = [m.wallet amountSentByTransaction:self.tx] - [m.wallet amountReceivedFromTransaction:self.tx];

    if (! self.removeFee) {
        fee = self.tx.standardFee;
        amount += fee;
        self.tx = [m.wallet transactionForAmounts:protoReq.details.outputAmounts
                   toOutputScripts:protoReq.details.outputScripts withFee:YES];
        if (self.tx) {
            amount = [m.wallet amountSentByTransaction:self.tx] - [m.wallet amountReceivedFromTransaction:self.tx];
            fee = [m.wallet feeForTransaction:self.tx];
        }
    }

    for (NSData *script in protoReq.details.outputScripts) {
        NSString *addr = [NSString addressWithScriptPubKey:script];

        address = [address stringByAppendingFormat:@"%@%@", (address.length > 0) ? @", " : @"",
                   (addr) ? addr : NSLocalizedString(@"unrecognized address", nil)];
    }

    [self confirmAmount:amount fee:fee address:address name:protoReq.commonName memo:protoReq.details.memo
     isSecure:(valid && ! [protoReq.pkiType isEqual:@"none"]) ? YES : NO];
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
    
    if ([v.text hasPrefix:SCAN_TIP]) {
        UIButton *b = self.buttons.lastObject;

        self.tipView = [BRBubbleView viewWithText:CLIPBOARD_TIP tipPoint:CGPointMake(b.center.x, b.center.y + 10.0)
                        tipDirection:BRBubbleTipDirectionUp];
        if (self.showTips) self.tipView.text = [self.tipView.text stringByAppendingString:@" (6/6)"];
        self.tipView.backgroundColor = v.backgroundColor;
        self.tipView.font = v.font;
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips && [v.text hasPrefix:CLIPBOARD_TIP]) {
        self.showTips = NO;
        [(id)self.parentViewController.parentViewController tip:self];
    }

    return YES;
}

- (void)resetQRGuide
{
    self.scanController.message.text = nil;
    self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide"];
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
    if (self.showTips) self.tipView.text = [self.tipView.text stringByAppendingString:@" (5/6)"];
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
    self.scanController.delegate = self;
    self.scanController.transitioningDelegate = self;
    [self.navigationController presentViewController:self.scanController animated:YES completion:nil];
}

- (IBAction)payToClipboard:(id)sender
{
    //TODO: add warning about address re-use
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
    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }

    if (self.clearClipboard) [[UIPasteboard generalPasteboard] setString:@""];
    [self cancel:sender];
}

- (IBAction)cancel:(id)sender
{
    self.tx = nil;
    self.sweepTx = nil;
    self.request = nil;
    self.protocolRequest = nil;
    self.clearClipboard = NO;
    self.didAskFee = NO;
    self.removeFee = NO;

    for (UIButton *button in self.buttons) {
        button.enabled = YES;
    }
}

#pragma mark - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount
{
    amountViewController.request.amount = amount;
    [self confirmRequest:amountViewController.request];
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
fromConnection:(AVCaptureConnection *)connection
{
    for (AVMetadataMachineReadableCodeObject *o in metadataObjects) {
        if (! [o.type isEqual:AVMetadataObjectTypeQRCode]) continue;

        NSString *s = o.stringValue;
        BRPaymentRequest *request = [BRPaymentRequest requestWithString:s];

        if (! [request isValid] && ! [s isValidBitcoinPrivateKey] && ! [s isValidBitcoinBIP38Key]) {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetQRGuide) object:nil];
            self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-red"];

            if ([s hasPrefix:@"bitcoin:"] || [request.paymentAddress hasPrefix:@"1"]) {
                self.scanController.message.text = [NSString stringWithFormat:@"%@\n%@",
                                                    NSLocalizedString(@"not a valid bitcoin address", nil),
                                                    request.paymentAddress];
            }
            else self.scanController.message.text = NSLocalizedString(@"not a bitcoin QR code", nil);

            [self performSelector:@selector(resetQRGuide) withObject:nil afterDelay:0.35];
        }
        else {
            self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
            [self.scanController stop];

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
                        [self.navigationController dismissViewControllerAnimated:YES completion:^{
                            [self confirmProtocolRequest:req];
                            [self resetQRGuide];
                        }];
                    });
                }];
            }
            else {
                [self.navigationController dismissViewControllerAnimated:YES completion:^{
                    [self confirmRequest:request];
                    [self resetQRGuide];
                }];
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

    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRPaymentProtocolRequest *protoReq = self.protocolRequest;
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];

    if ([title isEqual:NSLocalizedString(@"remove fee", nil)] || [title isEqual:NSLocalizedString(@"continue", nil)]) {
        self.didAskFee = YES;
        self.removeFee = ([title isEqual:NSLocalizedString(@"remove fee", nil)]) ? YES : NO;
        if (self.protocolRequest) [self confirmProtocolRequest:self.protocolRequest];
        else if (self.request) [self confirmRequest:self.request];
        return;
    }

    if (! self.tx) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"insufficient funds", nil) message:nil delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }
//    else if (self.tx != self.txWithFee && freeHeight > [[BRPeerManager sharedInstance] lastBlockHeight] + 1) {
//        uint64_t txFee = self.txWithFee ? [m.wallet feeForTransaction:self.txWithFee] : self.tx.standardFee;
//        NSString *fee = [m stringForAmount:txFee];
//        NSString *localCurrencyFee = [m localCurrencyStringForAmount:txFee];
//
//        //if (freeHeight != TX_UNCONFIRMED) {
//        //    NSTimeInterval t = (freeHeight - [[BRPeerManager sharedInstance] lastBlockHeight])*600;
//        //    int minutes = t/60, hours = t/(60*60), days = t/(60*60*24);
//        //    NSString *time = [NSString stringWithFormat:@"%d %@%@", days ? days : (hours ? hours : minutes),
//        //                      days ? @"day" : (hours ? @"hour" : @"minutes"),
//        //                      days > 1 ? @"s" : (days == 0 && hours > 1 ? @"s" : @"")];
//        //
//        //    [[[UIAlertView alloc]
//        //      initWithTitle:[NSString stringWithFormat:@"%@ (%@) transaction fee recommended", fee,localCurrencyFee]
//        //      message:[NSString stringWithFormat:@"estimated confirmation time with no fee: %@", time] delegate:self
//        //      cancelButtonTitle:nil otherButtonTitles:@"no fee",
//        //      [NSString stringWithFormat:@"+ %@ (%@)", fee, localCurrencyFee], nil] show];
//        //    return;
//        //}
//
//        [[[UIAlertView alloc] initWithTitle:nil message:[NSString
//          stringWithFormat:NSLocalizedString(@"the bitcoin network will receive a fee of %@ (%@)", nil), fee,
//          localCurrencyFee] delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
//          otherButtonTitles:[NSString stringWithFormat:@"+ %@ (%@)", fee, localCurrencyFee], nil] show];
//        return;
//    }

    //TODO: check for duplicate transactions

    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }

    NSLog(@"signing transaction");

    [(id)self.parentViewController.parentViewController startActivityWithTimeout:30];

    //TODO: don't sign on main thread
    if (! [m.wallet signTransaction:self.tx]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:NSLocalizedString(@"error signing bitcoin transaction", nil) delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    NSLog(@"signed transaction:\n%@", [NSString hexWithData:self.tx.data]);

    [[BRPeerManager sharedInstance] publishTransaction:self.tx completion:^(NSError *error) {
        if (protoReq.details.paymentURL.length > 0) return;
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

    if (protoReq.details.paymentURL.length > 0) {
        uint64_t refundAmount = 0;
        NSMutableData *refundScript = [NSMutableData data];

        // use the payment transaction's change address as the refund address
        [refundScript appendScriptPubKeyForAddress:m.wallet.changeAddress];

        for (NSNumber *amount in protoReq.details.outputAmounts) {
            refundAmount += [amount unsignedLongLongValue];
        }

        // TODO: keep track of commonName/memo to associate them with outputScripts
        BRPaymentProtocolPayment *payment =
            [[BRPaymentProtocolPayment alloc] initWithMerchantData:protoReq.details.merchantData
             transactions:@[self.tx] refundToAmounts:@[@(refundAmount)] refundToScripts:@[refundScript] memo:nil];

        NSLog(@"posting payment to: %@", protoReq.details.paymentURL);

        [BRPaymentRequest postPayment:payment to:protoReq.details.paymentURL
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
                NSLog(@"%@", error.localizedDescription);
//                [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:nil
//                  cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil]
//                  performSelector:@selector(show) withObject:nil afterDelay:2.0];
            }
        }];
    }
}

#pragma mark UIViewControllerAnimatedTransitioning

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
    UIImageView *img = [self.buttons.firstObject imageView];
    UIView *guide = self.scanController.cameraGuide;
    CGPoint p;

    [self.scanController.view layoutIfNeeded];
    p = guide.center;

    if (to == self.scanController) {
        [v addSubview:to.view];
        to.view.frame = from.view.frame;
        to.view.center = CGPointMake(to.view.center.x, v.frame.size.height*3/2);
        guide.center = [v convertPoint:img.center fromView:img.superview];
        guide.transform = CGAffineTransformMakeScale(img.bounds.size.width/guide.bounds.size.width,
                                                     img.bounds.size.height/guide.bounds.size.height);
        guide.alpha = 0;
        [v addSubview:guide];

        [UIView animateWithDuration:0.1 animations:^{
            img.alpha = 0.0;
            guide.alpha = 1.0;
        }];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            to.view.center = from.view.center;
        } completion:^(BOOL finished) {
            img.alpha = 1.0;
            [transitionContext completeTransition:finished];
        }];

        [UIView animateWithDuration:0.8 delay:0.15 usingSpringWithDamping:0.5 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
            guide.center = p;
            guide.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            [to.view addSubview:guide];
        }];
    }
    else {
        [v addSubview:guide];
        [v insertSubview:to.view belowSubview:from.view];
        [self cancel:nil];
        img = [self.buttons.firstObject imageView];
        img.alpha = 0.0;

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
            guide.center = [v convertPoint:img.center fromView:img.superview];
            guide.transform = CGAffineTransformMakeScale(img.bounds.size.width/guide.bounds.size.width,
                                                         img.bounds.size.height/guide.bounds.size.height);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.1 animations:^{
                img.alpha = 1.0;
                guide.alpha = 0.0;
            } completion:^(BOOL finished) {
                guide.transform = CGAffineTransformIdentity;
                guide.center = p;
                guide.alpha = 1.0;
                [from.view addSubview:guide];
            }];
        }];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] - 0.15 delay:0.15
        options:UIViewAnimationOptionCurveEaseIn animations:^{
            from.view.center = CGPointMake(from.view.center.x, v.frame.size.height*3/2);
        } completion:^(BOOL finished) {
            [transitionContext completeTransition:finished];
        }];
    }
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
