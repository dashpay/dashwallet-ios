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
#import "BRPeerManager.h"
#import "BRPaymentRequest.h"
#import "BRPaymentProtocol.h"
#import "BRKey.h"
#import "BRTransaction.h"
#import "NSString+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "NSString+Dash.h"
#import "NSData+Dash.h"
#import "NSData+Bitcoin.h"
#import "BREventManager.h"
#import "FBShimmeringView.h"
#import "MBProgressHUD.h"
#import "DSShapeshiftManager.h"
#import "breadwallet-Swift.h"

#define SCAN_TIP      NSLocalizedString(@"Scan someone else's QR code to get their dash or bitcoin address. "\
"You can send a payment to anyone with an address.", nil)
#define CLIPBOARD_TIP NSLocalizedString(@"Dash addresses can also be copied to the clipboard. "\
"A dash address always starts with 'X' or '7'.", nil)

#define LOCK @"\xF0\x9F\x94\x92" // unicode lock symbol U+1F512 (utf-8)
#define REDX @"\xE2\x9D\x8C"     // unicode cross mark U+274C, red x emoji (utf-8)
#define NBSP @"\xC2\xA0"         // no-break space (utf-8)

static NSString *sanitizeString(NSString *s)
{
    NSMutableString *sane = [NSMutableString stringWithString:(s) ? s : @""];
    
    CFStringTransform((CFMutableStringRef)sane, NULL, kCFStringTransformToUnicodeName, NO);
    return sane;
}

@interface BRSendViewController ()

@property (nonatomic, assign) BOOL clearClipboard, useClipboard, showTips, showBalance, canChangeAmount, sendInstantly;
@property (nonatomic, strong) BRTransaction *sweepTx;
@property (nonatomic, strong) BRPaymentProtocolRequest *request;
@property (nonatomic, strong) NSString *scheme;
@property (nonatomic, strong) DSShapeshiftEntity * associatedShapeshift;
@property (nonatomic, strong) NSURL *url, *callback;
@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, strong) NSString *okAddress, *okIdentity;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, strong) BRScanViewController *scanController;
@property (nonatomic, strong) id clipboardObserver;

@property (nonatomic, strong) IBOutlet UILabel *sendLabel;
@property (nonatomic, strong) IBOutlet UISwitch *instantSwitch;
@property (nonatomic, strong) IBOutlet UIButton *scanButton, *clipboardButton;
@property (nonatomic, strong) IBOutlet UITextView *clipboardText;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *clipboardXLeft;
@property (nonatomic, strong) IBOutlet UIView * shapeshiftView;
@property (nonatomic, strong) IBOutlet UILabel * shapeshiftLabel;

@end

@implementation BRSendViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // TODO: XXX redesign page with round buttons like the iOS power down screen... apple watch also has round buttons
    self.scanButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.clipboardButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.scanButton.titleLabel.adjustsLetterSpacingToFitWidth = YES;
    self.clipboardButton.titleLabel.adjustsLetterSpacingToFitWidth = YES;
#pragma clang diagnostic pop
    
    self.clipboardText.textContainerInset = UIEdgeInsetsMake(8.0, 0.0, 0.0, 0.0);
    
    self.clipboardObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:UIPasteboardChangedNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
                                                      if (self.clipboardText.isFirstResponder) {
                                                          self.useClipboard = YES;
                                                      }
                                                      else [self updateClipboardText];
                                                  }];
    
    FBShimmeringView *shimmeringView = [[FBShimmeringView alloc] initWithFrame:self.shapeshiftView.frame];
    [self.view addSubview:shimmeringView];
    [self.shapeshiftView removeFromSuperview];
    [shimmeringView addSubview:self.shapeshiftView];
    shimmeringView.contentView = self.shapeshiftView;
    // Start shimmering.
    shimmeringView.shimmering = YES;
    shimmeringView.shimmeringSpeed = 5;
    shimmeringView.shimmeringDirection = FBShimmerDirectionUp;
    shimmeringView.shimmeringPauseDuration = 0.0;
    shimmeringView.shimmeringHighlightLength = 1.0f;
    shimmeringView.shimmeringAnimationOpacity = 0.8;
    self.shapeshiftView = shimmeringView;
    
    FBShimmeringView *shimmeringInnerLabelView = [[FBShimmeringView alloc] initWithFrame:self.shapeshiftLabel.frame];
    [self.shapeshiftLabel removeFromSuperview];
    [shimmeringInnerLabelView addSubview:self.shapeshiftLabel];
    shimmeringInnerLabelView.contentView = self.shapeshiftLabel;
    
    shimmeringInnerLabelView.shimmering = YES;
    shimmeringInnerLabelView.shimmeringSpeed = 100;
    shimmeringInnerLabelView.shimmeringPauseDuration = 0.8;
    shimmeringInnerLabelView.shimmeringAnimationOpacity = 0.2;
    [self.shapeshiftView addSubview:shimmeringInnerLabelView];
    NSArray * shapeshiftsInProgress = [DSShapeshiftEntity shapeshiftsInProgress];
    if (![shapeshiftsInProgress count]) {
        
        self.shapeshiftView.hidden = TRUE;
    } else {
        for (DSShapeshiftEntity * shapeshift in shapeshiftsInProgress) {
            [shapeshift transaction];
            [self startObservingShapeshift:shapeshift];
        }
    }
    self.sendInstantly = TRUE;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self cancel:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (! self.scanController) {
        self.scanController = [self.storyboard instantiateViewControllerWithIdentifier:@"ScanViewController"];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self hideTips];
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.clipboardObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.clipboardObserver];
}

- (void)handleURL:(NSURL *)url
{
    [BREventManager saveEvent:@"send:handle_url"
               withAttributes:@{@"scheme": (url.scheme ? url.scheme : @"(null)"),
                                @"host": (url.host ? url.host : @"(null)"),
                                @"path": (url.path ? url.path : @"(null)")}];
    
    //TODO: XXX custom url splash image per: "Providing Launch Images for Custom URL Schemes."
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    if ([url.scheme isEqual:@"dashwallet"]) { // x-callback-url handling: http://x-callback-url.com/specifications/
        NSString *xsource = nil, *xsuccess = nil, *xerror = nil, *uri = nil;
        NSURL *callback = nil;
        
        for (NSString *arg in [url.query componentsSeparatedByString:@"&"]) {
            NSArray *pair = [arg componentsSeparatedByString:@"="]; // if more than one '=', then pair[1] != value
            
            if (pair.count < 2) continue;
            
            NSString *value = [[[arg substringFromIndex:[pair[0] length] + 1]
                                stringByReplacingOccurrencesOfString:@"+" withString:@" "]
                               stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            
            if ([pair[0] isEqual:@"x-source"]) xsource = value;
            else if ([pair[0] isEqual:@"x-success"]) xsuccess = value;
            else if ([pair[0] isEqual:@"x-error"]) xerror = value;
            else if ([pair[0] isEqual:@"uri"]) uri = value;
        }
        
        if ([url.host isEqual:@"scanqr"] || [url.path isEqual:@"/scanqr"]) { // scan qr
            [self scanQR:self.scanButton];
        }
        else if ([url.host isEqual:@"addresslist"] || [url.path isEqual:@"/addresslist"]) { // copy wallet addresses
            if ((manager.didAuthenticate || [manager authenticateWithPrompt:nil andTouchId:YES])
                && ! self.clearClipboard) {
                
                if (! [self.url isEqual:url]) {
                    self.url = url;
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"copy wallet addresses to clipboard?", nil)
                                                message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                                      otherButtonTitles:NSLocalizedString(@"copy", nil), nil] show];
                }
                else {
                    [UIPasteboard generalPasteboard].string =
                    [[[manager.wallet.allReceiveAddresses
                       setByAddingObjectsFromSet:manager.wallet.allChangeAddresses]
                      objectsPassingTest:^BOOL(id obj, BOOL *stop) {
                          return [manager.wallet addressIsUsed:obj];
                      }].allObjects componentsJoinedByString:@"\n"];
                    
                    if (xsuccess) callback = [NSURL URLWithString:xsuccess];
                    self.url = nil;
                }
            }
            else if (xerror || xsuccess) {
                callback = [NSURL URLWithString:(xerror) ? xerror : xsuccess];
                [UIPasteboard generalPasteboard].string = @"";
                [self cancel:nil];
            }
        }
        else if ([url.path isEqual:@"/address"] && xsuccess) { // get receive address
            callback = [NSURL URLWithString:[xsuccess stringByAppendingFormat:@"%@address=%@",
                                             ([NSURL URLWithString:xsuccess].query.length > 0) ? @"&" : @"?",
                                             manager.wallet.receiveAddress]];
        }
        else if (([url.host isEqual:@"bitcoin-uri"] || [url.path isEqual:@"/bitcoin-uri"]) && uri &&
                 [[NSURL URLWithString:uri].scheme isEqual:@"bitcoin"]) {
            if (xsuccess) self.callback = [NSURL URLWithString:xsuccess];
            [self handleURL:[NSURL URLWithString:uri]];
        }
        
        if (callback) [[UIApplication sharedApplication] openURL:callback];
    }
    else if ([url.scheme isEqual:@"bitcoin"]) {
        [self confirmRequest:[BRPaymentRequest requestWithURL:url]];
    } else if ([BRBitID isBitIDURL:url]) {
        [self handleBitIDURL:url];
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
                                         viewWithText:(payment.memo.length > 0 ? payment.memo : NSLocalizedString(@"received", nil))
                                         center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                                       popOutAfterDelay:(payment.memo.length > 0 ? 3.0 : 2.0)]];
            }];
        }
        
        return;
    }
    
    BRPaymentProtocolACK *ack = [BRPaymentProtocolACK ackWithData:file];
    
    if (ack) {
        if (ack.memo.length > 0) {
            [self.view addSubview:[[[BRBubbleView viewWithText:ack.memo
                                                        center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                                   popOutAfterDelay:3.0]];
        }
        
        return;
    }
    
    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"unsupported or corrupted document", nil) message:nil
                               delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
}

- (void)handleBitIDURL:(NSURL *)url
{
    if ([UIAlertController class] == nil) {
        return;
    }
    BRBitID *bitid = [[BRBitID alloc] initWithUrl:url];
    
    void (^actionHandler)(UIAlertAction * _Nonnull) = ^(UIAlertAction * _Nonnull action) {
        [self dismissViewControllerAnimated:YES completion:nil];
        if (action.style == UIAlertActionStyleDefault) {
            BRActivityViewController *activityVC = [[BRActivityViewController alloc] initWithMessage:
                                                    NSLocalizedString(@"Signing...", nil)];
            void (^callbackHandler)(id, id, id) = ^(NSData *data, NSURLResponse *resp, NSError *error) {
                [self.navigationController dismissViewControllerAnimated:YES completion:nil];
                NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
                if (error == nil && (httpResp.statusCode >= 200 && httpResp.statusCode < 300)) {
                    // successfully sent bitid callback request. show a brief success message
                    UIAlertController *successAlert =
                    [UIAlertController alertControllerWithTitle:@"Successfully Authenticated" message:nil
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    [self.navigationController presentViewController:successAlert animated:YES completion:nil];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                                       [self dismissViewControllerAnimated:YES completion:nil];
                                   });
                } else {
                    // show the user an error alert
                    UIAlertController *errorAlert =
                    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Authentication Error", nil)
                                                        message:NSLocalizedString(@"Please check with the service. "
                                                                                  "You may need to try again.", nil)
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                                   style:UIAlertActionStyleCancel
                                                                 handler:^(UIAlertAction * _Nonnull action) {
                                                                     [self dismissViewControllerAnimated:YES
                                                                                              completion:nil];
                                                                 }]];
                    [self.navigationController presentViewController:errorAlert animated:YES completion:nil];
                }
            };
            // attempt to avoid frozen pin input bug
            CFRunLoopPerformBlock([[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopCommonModes, ^{
                [bitid runCallback:callbackHandler];
                [self.navigationController presentViewController:activityVC animated:YES completion:nil];
            });
        }
    };
    
    NSString *message = [NSString stringWithFormat:
                         NSLocalizedString(@"%@ is requesting authentication using your bitcoin wallet.", nil),
                         bitid.siteName];
    UIAlertController *alertController =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"BitID Authentication Request", nil)
                                        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Deny", nil)
                                                        style:UIAlertActionStyleCancel
                                                      handler:actionHandler]];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Approve", nil)
                                                        style:UIAlertActionStyleDefault
                                                      handler:actionHandler]];
    [self.navigationController presentViewController:alertController animated:YES completion:nil];
}


// generate a description of a transaction so the user can review and decide whether to confirm or cancel
- (NSString *)promptForAmount:(uint64_t)amount fee:(uint64_t)fee address:(NSString *)address name:(NSString *)name
                         memo:(NSString *)memo isSecure:(BOOL)isSecure
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSString *prompt = (isSecure && name.length > 0) ? LOCK @" " : @"";
    
    //BUG: XXX limit the length of name and memo to avoid having the amount clipped
    if (! isSecure && self.request.errorMessage.length > 0) prompt = [prompt stringByAppendingString:REDX @" "];
    if (name.length > 0) prompt = [prompt stringByAppendingString:sanitizeString(name)];
    if (! isSecure && prompt.length > 0) prompt = [prompt stringByAppendingString:@"\n"];
    if (! isSecure || prompt.length == 0) prompt = [prompt stringByAppendingString:address];
    if (memo.length > 0) prompt = [prompt stringByAppendingFormat:@"\n\n%@", sanitizeString(memo)];
    prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\n\n     amount %@ (%@)", nil),
              [manager stringForDashAmount:amount - fee], [manager localCurrencyStringForDashAmount:amount - fee]];
    
    if (fee > 0) {
        prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\nnetwork fee +%@ (%@)", nil),
                  [manager stringForDashAmount:fee], [manager localCurrencyStringForDashAmount:fee]];
        prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\n         total %@ (%@)", nil),
                  [manager stringForDashAmount:amount], [manager localCurrencyStringForDashAmount:amount]];
    }
    
    return prompt;
}

- (void)confirmRequest:(BRPaymentRequest *)request
{
    if (! request.isValid) {
        if ([request.paymentAddress isValidDashPrivateKey] || [request.paymentAddress isValidDashBIP38Key]) {
            [self confirmSweep:request.paymentAddress];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"not a valid dash or bitcoin address", nil)
                                        message:request.paymentAddress delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                              otherButtonTitles:nil] show];
            [self cancel:nil];
        }
    }
    else if (request.r.length > 0) { // payment protocol over HTTP
        [(id)self.parentViewController.parentViewController startActivityWithTimeout:20.0];
        
        [BRPaymentRequest fetch:request.r scheme:request.scheme timeout:20.0 completion:^(BRPaymentProtocolRequest *req, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];
                
                if (error && ! ([request.paymentAddress isValidBitcoinAddress] || [request.paymentAddress isValidDashAddress])) {
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                                message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                                      otherButtonTitles:nil] show];
                    [self cancel:nil];
                }
                else [self confirmProtocolRequest:(error) ? request.protocolRequest : req];
            });
        }];
    }
    else [self confirmProtocolRequest:request.protocolRequest currency:request.scheme associatedShapeshift:nil wantsInstant:request.wantsInstant];
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)protoReq {
    [self confirmProtocolRequest:protoReq currency:@"dash" associatedShapeshift:nil];
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)protoReq currency:(NSString*)currency associatedShapeshift:(DSShapeshiftEntity*)shapeshift
{
    [self confirmProtocolRequest:protoReq currency:currency associatedShapeshift:shapeshift wantsInstant:self.sendInstantly];
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)protoReq currency:(NSString*)currency associatedShapeshift:(DSShapeshiftEntity*)shapeshift wantsInstant:(BOOL)wantsInstant
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    BRTransaction *tx = nil;
    uint64_t amount = 0, fee = 0;
    BOOL valid = protoReq.isValid, outputTooSmall = NO;
    
    if (! valid && [protoReq.errorMessage isEqual:NSLocalizedString(@"request expired", nil)]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"bad payment request", nil) message:protoReq.errorMessage
                                   delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }
    
    //TODO: check for duplicates of already paid requests
    
    if (self.amount == 0) {
        for (NSNumber *outputAmount in protoReq.details.outputAmounts) {
            if (outputAmount.unsignedLongLongValue > 0 && outputAmount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) {
                outputTooSmall = YES;
            }
            amount += outputAmount.unsignedLongLongValue;
        }
    }
    else amount = self.amount;
    
    if ([currency isEqualToString:@"dash"]) {
        NSString *address = [NSString addressWithScriptPubKey:protoReq.details.outputScripts.firstObject];
        if ([manager.wallet containsAddress:address]) {
            [[[UIAlertView alloc] initWithTitle:@""
                                        message:NSLocalizedString(@"this payment address is already in your wallet", nil)
                                       delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }
        else if (! [self.okAddress isEqual:address] && [manager.wallet addressIsUsed:address] &&
                 [[UIPasteboard generalPasteboard].string isEqual:address]) {
            self.request = protoReq;
            self.scheme = currency;
            self.okAddress = address;
            self.associatedShapeshift = shapeshift;
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                                        message:NSLocalizedString(@"\nADDRESS ALREADY USED\ndash addresses are intended for single use only\n\n"
                                                                  "re-use reduces privacy for both you and the recipient and can result in loss if "
                                                                  "the recipient doesn't directly control the address", nil)
                                       delegate:self cancelButtonTitle:nil
                              otherButtonTitles:NSLocalizedString(@"ignore", nil), NSLocalizedString(@"cancel", nil), nil] show];
            return;
        } else if (wantsInstant && !self.sendInstantly) {
            self.request = protoReq;
            self.scheme = currency;
            self.associatedShapeshift = shapeshift;
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Instant Payment", nil)
                                        message:NSLocalizedString(@"Request is for an instant payment but you have disabled instant payments",
                                                                                             nil)
                                       delegate:self cancelButtonTitle:nil
                              otherButtonTitles:NSLocalizedString(@"ignore", nil), NSLocalizedString(@"enable", nil), nil] show];
            return;
            
        } else if (wantsInstant && ([manager.wallet maxOutputAmountWithConfirmationCount:IX_PREVIOUS_CONFIRMATIONS_NEEDED usingInstantSend:TRUE] < amount)) {
            self.request = protoReq;
            self.scheme = currency;
            self.associatedShapeshift = shapeshift;
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Instant Payment", nil)
                                        message:NSLocalizedString(@"Instant Send requires enough inputs with 6 confirmations, send anyways as regular transaction?",
                                                                  nil)
                                       delegate:self cancelButtonTitle:nil
                              otherButtonTitles:NSLocalizedString(@"cancel", nil), NSLocalizedString(@"send", nil), nil] show];
            return;
        } else if (protoReq.errorMessage.length > 0 && protoReq.commonName.length > 0 &&
                 ! [self.okIdentity isEqual:protoReq.commonName]) {
            self.request = protoReq;
            self.scheme = currency;
            self.okIdentity = protoReq.commonName;
            self.associatedShapeshift = shapeshift;
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"payee identity isn't certified", nil)
                                        message:protoReq.errorMessage delegate:self cancelButtonTitle:nil
                              otherButtonTitles:NSLocalizedString(@"ignore", nil), NSLocalizedString(@"cancel", nil), nil] show];
            return;
        }
        else if (amount == 0 || amount == UINT64_MAX) {
            BRAmountViewController *amountController = [self.storyboard
                                                        instantiateViewControllerWithIdentifier:@"AmountViewController"];
            
            amountController.delegate = self;
            self.request = protoReq;
            self.scheme = currency;
            self.associatedShapeshift = shapeshift;
            if (protoReq.commonName.length > 0) {
                if (valid && ! [protoReq.pkiType isEqual:@"none"]) {
                    amountController.to = [LOCK @" " stringByAppendingString:sanitizeString(protoReq.commonName)];
                }
                else if (protoReq.errorMessage.length > 0) {
                    amountController.to = [REDX @" " stringByAppendingString:sanitizeString(protoReq.commonName)];
                }
                else amountController.to = sanitizeString(protoReq.commonName);
            }
            else amountController.to = address;
            [self updateTitleView];
            [self.navigationController pushViewController:amountController animated:YES];
            return;
        }
        else if (amount < TX_MIN_OUTPUT_AMOUNT) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                        message:[NSString stringWithFormat:NSLocalizedString(@"dash payments can't be less than %@", nil),
                                                 [manager stringForDashAmount:TX_MIN_OUTPUT_AMOUNT]] delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }
        else if (outputTooSmall) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                        message:[NSString stringWithFormat:NSLocalizedString(@"dash transaction outputs can't be less than %@",
                                                                                             nil), [manager stringForDashAmount:TX_MIN_OUTPUT_AMOUNT]]
                                       delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }
        
        
        
        self.request = protoReq;
        self.scheme = @"dash";
        
        if (self.amount == 0) {
            
            if (shapeshift) {
                tx = [manager.wallet transactionForAmounts:protoReq.details.outputAmounts
                                           toOutputScripts:protoReq.details.outputScripts withFee:YES isInstant:wantsInstant toShapeshiftAddress:shapeshift.withdrawalAddress];
                tx.associatedShapeshift = shapeshift;
            } else {
                tx = [manager.wallet transactionForAmounts:protoReq.details.outputAmounts
                                           toOutputScripts:protoReq.details.outputScripts withFee:YES isInstant:wantsInstant toShapeshiftAddress:nil];
            }
        }
        else {
            if (shapeshift) {
                tx = [manager.wallet transactionForAmounts:@[@(self.amount)]
                                           toOutputScripts:@[protoReq.details.outputScripts.firstObject] withFee:YES isInstant:wantsInstant toShapeshiftAddress:shapeshift.withdrawalAddress];
                tx.associatedShapeshift = shapeshift;
            } else {
                tx = [manager.wallet transactionForAmounts:@[@(self.amount)]
                                           toOutputScripts:@[protoReq.details.outputScripts.firstObject] withFee:YES isInstant:wantsInstant toShapeshiftAddress:nil];
            }
        }
        
        if (tx) {
            amount = [manager.wallet amountSentByTransaction:tx] - [manager.wallet amountReceivedFromTransaction:tx];
            fee = [manager.wallet feeForTransaction:tx];
        }
        else {
            BRTransaction * tempTx = [manager.wallet transactionFor:manager.wallet.balance
                                                                 to:address withFee:NO];
            fee = [manager.wallet feeForTxSize:tempTx.size isInstant:self.sendInstantly inputCount:tempTx.inputHashes.count];
            fee += (manager.wallet.balance - amount) % 100;
            amount += fee;
        }
        
        for (NSData *script in protoReq.details.outputScripts) {
            NSString *addr = [NSString addressWithScriptPubKey:script];
            
            if (! addr) addr = NSLocalizedString(@"unrecognized address", nil);
            if ([address rangeOfString:addr].location != NSNotFound) continue;
            address = [address stringByAppendingFormat:@"%@%@", (address.length > 0) ? @", " : @"", addr];
        }
        
        NSString *prompt = [self promptForAmount:amount fee:fee address:address name:protoReq.commonName
                                            memo:protoReq.details.memo isSecure:(valid && ! [protoReq.pkiType isEqual:@"none"])];
        
        // to avoid the frozen pincode keyboard bug, we need to make sure we're scheduled normally on the main runloop
        // rather than a dispatch_async queue
        CFRunLoopPerformBlock([[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopCommonModes, ^{
            [self confirmTransaction:tx withPrompt:prompt forAmount:amount];
        });
    } else if ([currency isEqualToString:@"bitcoin"]) {
        NSString *address = [NSString bitcoinAddressWithScriptPubKey:protoReq.details.outputScripts.firstObject];
        if (protoReq.errorMessage.length > 0 && protoReq.commonName.length > 0 &&
            ! [self.okIdentity isEqual:protoReq.commonName]) {
            self.request = protoReq;
            self.scheme = currency;
            self.associatedShapeshift = shapeshift;
            self.okIdentity = protoReq.commonName;
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"payee identity isn't certified", nil)
                                        message:protoReq.errorMessage delegate:self cancelButtonTitle:nil
                              otherButtonTitles:NSLocalizedString(@"ignore", nil), NSLocalizedString(@"cancel", nil), nil] show];
            return;
        }
        else if (amount == 0 || amount == UINT64_MAX) {
            BRAmountViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"AmountViewController"];
            self.scheme = currency;
            c.usingShapeshift = TRUE;
            c.delegate = self;
            self.request = protoReq;
            self.associatedShapeshift = shapeshift;
            if (protoReq.commonName.length > 0) {
                if (valid && ! [protoReq.pkiType isEqual:@"none"]) {
                    c.to = [LOCK @" " stringByAppendingString:sanitizeString(shapeshift.withdrawalAddress)];
                }
                else if (protoReq.errorMessage.length > 0) {
                    c.to = [REDX @" " stringByAppendingString:sanitizeString(shapeshift.withdrawalAddress)];
                }
                else c.to = sanitizeString(shapeshift.withdrawalAddress);
            }
            else c.to = address;
            BRWalletManager *manager = [BRWalletManager sharedInstance];
            c.navigationItem.titleView = [self titleLabel];
            [self.navigationController pushViewController:c animated:YES];
            return;
        }
        else if (amount < TX_MIN_OUTPUT_AMOUNT) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                        message:[NSString stringWithFormat:NSLocalizedString(@"dash payments can't be less than %@", nil),
                                                 [manager stringForDashAmount:TX_MIN_OUTPUT_AMOUNT]] delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }
        else if (outputTooSmall) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                        message:[NSString stringWithFormat:NSLocalizedString(@"dash transaction outputs can't be less than %@",
                                                                                             nil), [manager stringForDashAmount:TX_MIN_OUTPUT_AMOUNT]]
                                       delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }
        self.request = protoReq;
        self.scheme = currency;
        [self amountViewController:nil shapeshiftBitcoinAmount:amount approximateDashAmount:1.03*amount/manager.bitcoinDashPrice.doubleValue];
    }
}

- (void)confirmTransaction:(BRTransaction *)tx withPrompt:(NSString *)prompt forAmount:(uint64_t)amount
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    BOOL didAuth = manager.didAuthenticate;
    
    if (! tx) { // tx is nil if there were insufficient wallet funds
        if (! manager.didAuthenticate) [manager seedWithPrompt:prompt forAmount:amount];
        
        if (manager.didAuthenticate) {
            uint64_t fuzz = [manager amountForLocalCurrencyString:[manager localCurrencyStringForDashAmount:1]]*2;
            
            // if user selected an amount equal to or below wallet balance, but the fee will bring the total above the
            // balance, offer to reduce the amount to available funds minus fee
            if (self.amount <= manager.wallet.balance + fuzz && self.amount > 0) {
                int64_t amount = [manager.wallet maxOutputAmountUsingInstantSend:tx.isInstant];
                
                if (amount > 0 && amount < self.amount) {
                    [[[UIAlertView alloc]
                      initWithTitle:NSLocalizedString(@"insufficient funds for dash network fee", nil)
                      message:[NSString stringWithFormat:NSLocalizedString(@"reduce payment amount by\n%@ (%@)?", nil),
                               [manager stringForDashAmount:self.amount - amount],
                               [manager localCurrencyStringForDashAmount:self.amount - amount]] delegate:self
                      cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                      otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)",
                                         [manager stringForDashAmount:amount - self.amount],
                                         [manager localCurrencyStringForDashAmount:amount - self.amount]], nil] show];
                    self.amount = amount;
                }
                else {
                    [[[UIAlertView alloc]
                      initWithTitle:NSLocalizedString(@"insufficient funds for dash network fee", nil) message:nil
                      delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                }
            }
            else {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"insufficient funds", nil) message:nil
                                           delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            }
        }
        else [self cancelOrChangeAmount];
        
        if (! didAuth) manager.didAuthenticate = NO;
        return;
    }
    
    if (! [manager.wallet signTransaction:tx withPrompt:prompt]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                    message:NSLocalizedString(@"error signing dash transaction", nil) delegate:nil
                          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    }
    
    if (! didAuth) manager.didAuthenticate = NO;
    
    if (! tx.isSigned) { // user canceled authentication
        [self cancelOrChangeAmount];
        return;
    }
    
    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
    
    __block BOOL waiting = YES, sent = NO;
    
    [(id)self.parentViewController.parentViewController startActivityWithTimeout:30.0];
    
    [[BRPeerManager sharedInstance] publishTransaction:tx completion:^(NSError *error) {
        if (error) {
            if (! waiting && ! sent) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                            message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                                  otherButtonTitles:nil] show];
                [(id)self.parentViewController.parentViewController stopActivityWithSuccess:NO];
                [self cancel:nil];
            }
        }
        else if (! sent) { //TODO: show full screen sent dialog with tx info, "you sent b10,000 to bob"
            if (tx.associatedShapeshift) {
                [self startObservingShapeshift:tx.associatedShapeshift];
                
            }
            sent = YES;
            tx.timestamp = [NSDate timeIntervalSinceReferenceDate];
            [manager.wallet registerTransaction:tx];
            [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"sent!", nil)
                                                        center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                                   popOutAfterDelay:2.0]];
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:YES];
            [(id)self.parentViewController.parentViewController ping];
            
            if (self.callback) {
                self.callback = [NSURL URLWithString:[self.callback.absoluteString stringByAppendingFormat:@"%@txid=%@",
                                                      (self.callback.query.length > 0) ? @"&" : @"?",
                                                      [NSString hexWithData:[NSData dataWithBytes:tx.txHash.u8
                                                                                           length:sizeof(UInt256)].reverse]]];
                [[UIApplication sharedApplication] openURL:self.callback];
            }
            
            [self reset:nil];
        }
        
        waiting = NO;
    }];
    
    if (self.request.details.paymentURL.length > 0) {
        uint64_t refundAmount = 0;
        NSMutableData *refundScript = [NSMutableData data];
        
        [refundScript appendScriptPubKeyForAddress:manager.wallet.receiveAddress];
        
        for (NSNumber *amt in self.request.details.outputAmounts) {
            refundAmount += amt.unsignedLongLongValue;
        }
        
        // TODO: keep track of commonName/memo to associate them with outputScripts
        BRPaymentProtocolPayment *payment =
        [[BRPaymentProtocolPayment alloc] initWithMerchantData:self.request.details.merchantData
                                                  transactions:@[tx] refundToAmounts:@[@(refundAmount)] refundToScripts:@[refundScript] memo:nil];
        
        NSLog(@"posting payment to: %@", self.request.details.paymentURL);
        
        [BRPaymentRequest postPayment:payment scheme:@"dash" to:self.request.details.paymentURL timeout:20.0
                           completion:^(BRPaymentProtocolACK *ack, NSError *error) {
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];
                                   
                                   if (error) {
                                       if (! waiting && ! sent) {
                                           [[[UIAlertView alloc] initWithTitle:@"" message:error.localizedDescription delegate:nil
                                                             cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                                           [(id)self.parentViewController.parentViewController stopActivityWithSuccess:NO];
                                           [self cancel:nil];
                                       }
                                   }
                                   else if (! sent) {
                                       sent = YES;
                                       tx.timestamp = [NSDate timeIntervalSinceReferenceDate];
                                       [manager.wallet registerTransaction:tx];
                                       [self.view addSubview:[[[BRBubbleView
                                                                viewWithText:(ack.memo.length > 0 ? ack.memo : NSLocalizedString(@"sent!", nil))
                                                                center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                                                              popOutAfterDelay:(ack.memo.length > 0 ? 3.0 : 2.0)]];
                                       [(id)self.parentViewController.parentViewController stopActivityWithSuccess:YES];
                                       [(id)self.parentViewController.parentViewController ping];
                                       
                                       if (self.callback) {
                                           self.callback = [NSURL URLWithString:[self.callback.absoluteString
                                                                                 stringByAppendingFormat:@"%@txid=%@",
                                                                                 (self.callback.query.length > 0) ? @"&" : @"?",
                                                                                 [NSString hexWithData:[NSData dataWithBytes:tx.txHash.u8
                                                                                                                      length:sizeof(UInt256)].reverse]]];
                                           [[UIApplication sharedApplication] openURL:self.callback];
                                       }
                                       
                                       [self reset:nil];
                                   }
                                   
                                   waiting = NO;
                               });
                           }];
    }
    else waiting = NO;
}

- (void)confirmSweep:(NSString *)privKey
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    if (! [privKey isValidDashPrivateKey] && ! [privKey isValidDashBIP38Key]) return;
    
    BRBubbleView *statusView = [BRBubbleView viewWithText:NSLocalizedString(@"checking private key balance...", nil)
                                                   center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
    
    statusView.font = [UIFont systemFontOfSize:15.0];
    statusView.customView = [[UIActivityIndicatorView alloc]
                             initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [(id)statusView.customView startAnimating];
    [self.view addSubview:[statusView popIn]];
    
    [manager sweepPrivateKey:privKey withFee:YES completion:^(BRTransaction *tx, uint64_t fee, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [statusView popOut];
            
            if (error) {
                [[[UIAlertView alloc] initWithTitle:@"" message:error.localizedDescription delegate:self
                                  cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                [self cancel:nil];
            }
            else if (tx) {
                uint64_t amount = fee;
                
                for (NSNumber *amt in tx.outputAmounts) amount += amt.unsignedLongLongValue;
                self.sweepTx = tx;
                
                NSString *alertFmt = NSLocalizedString(@"Send %@ (%@) from this private key into your wallet? "
                                                       "The dash network will receive a fee of %@ (%@).", nil);
                NSString *alertMsg = [NSString stringWithFormat:alertFmt, [manager stringForDashAmount:amount],
                                      [manager localCurrencyStringForDashAmount:amount], [manager stringForDashAmount:fee],
                                      [manager localCurrencyStringForDashAmount:fee]];
                [[[UIAlertView alloc] initWithTitle:@"" message:alertMsg delegate:self
                                  cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                                  otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)", [manager stringForDashAmount:amount],
                                                     [manager localCurrencyStringForDashAmount:amount]], nil] show];
            }
            else [self cancel:nil];
        });
    }];
}

- (void)showBalance:(NSString *)address
{
    if (! [address isValidBitcoinAddress]) return;
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    BRBubbleView *statusView = [BRBubbleView viewWithText:NSLocalizedString(@"checking address balance...", nil)
                                                   center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
    
    statusView.font = [UIFont systemFontOfSize:15.0];
    statusView.customView = [[UIActivityIndicatorView alloc]
                             initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [(id)statusView.customView startAnimating];
    [self.view addSubview:[statusView popIn]];
    
    [manager utxosForAddresses:@[address]
                    completion:^(NSArray *utxos, NSArray *amounts, NSArray *scripts, NSError *error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [statusView popOut];
                            
                            if (error) {
                                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't check address balance", nil)
                                                            message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                                                  otherButtonTitles:nil] show];
                            }
                            else {
                                uint64_t balance = 0;
                                
                                for (NSNumber *amt in amounts) balance += amt.unsignedLongLongValue;
                                
                                NSString *alertMsg = [NSString stringWithFormat:NSLocalizedString(@"%@\n\nbalance: %@ (%@)", nil),
                                                      address, [manager stringForDashAmount:balance],
                                                      [manager localCurrencyStringForDashAmount:balance]];
                                
                                [[[UIAlertView alloc] initWithTitle:@"" message:alertMsg delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                            }
                        });
                    }];
}

- (void)cancelOrChangeAmount
{
    if (self.canChangeAmount && self.request && self.amount == 0) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"change payment amount?", nil)
                                    message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                          otherButtonTitles:NSLocalizedString(@"change", nil), nil] show];
        self.amount = UINT64_MAX;
    }
    else [self cancel:nil];
}

- (void)hideTips
{
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

- (BOOL)nextTip
{
    [self.clipboardText resignFirstResponder];
    if (self.tipView.alpha < 0.5) return [(id)self.parentViewController.parentViewController nextTip];
    
    BRBubbleView *tipView = self.tipView;
    
    self.tipView = nil;
    [tipView popOut];
    
    if ([tipView.text hasPrefix:SCAN_TIP]) {
        self.tipView = [BRBubbleView viewWithText:CLIPBOARD_TIP
                                         tipPoint:CGPointMake(self.clipboardButton.center.x, self.clipboardButton.center.y + 10.0)
                                     tipDirection:BRBubbleTipDirectionUp];
        self.tipView.backgroundColor = tipView.backgroundColor;
        self.tipView.font = tipView.font;
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips && [tipView.text hasPrefix:CLIPBOARD_TIP]) {
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

- (void)updateClipboardText
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *str = [[UIPasteboard generalPasteboard].string
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *text = @"";
        UIImage *img = [UIPasteboard generalPasteboard].image;
        NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
        NSCharacterSet *separators = [NSCharacterSet alphanumericCharacterSet].invertedSet;
        
        if (str) {
            [set addObject:str];
            [set addObjectsFromArray:[str componentsSeparatedByCharactersInSet:separators]];
        }
        
        if (img) {
            @synchronized ([CIContext class]) {
                CIContext *context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@(YES)}];
                
                if (! context) context = [CIContext context];
                
                for (CIQRCodeFeature *qr in [[CIDetector detectorOfType:CIDetectorTypeQRCode context:context
                                                                options:nil] featuresInImage:[CIImage imageWithCGImage:img.CGImage]]) {
                    [set addObject:[qr.messageString
                                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
                }
            }
        }
        
        for (NSString *s in set) {
            BRPaymentRequest *req = [BRPaymentRequest requestWithString:s];
            
            if ([req.paymentAddress isValidBitcoinAddress]) {
                text = (req.label.length > 0) ? sanitizeString(req.label) : req.paymentAddress;
                break;
            }
            else if ([s hasPrefix:@"bitcoin:"]) {
                text = sanitizeString(s);
                break;
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat textWidth = [text sizeWithAttributes:@{NSFontAttributeName:self.clipboardText.font}].width + 12;
            
            self.clipboardText.text = text;
            if (textWidth < self.clipboardButton.bounds.size.width ) textWidth = self.clipboardButton.bounds.size.width;
            if (textWidth > self.view.bounds.size.width - 16.0) textWidth = self.view.bounds.size.width - 16.0;
            self.clipboardXLeft.constant = (self.view.bounds.size.width - textWidth)/2.0;
            [self.clipboardText scrollRangeToVisible:NSMakeRange(0, 0)];
        });
    });
}

- (void)payFirstFromArray:(NSArray *)array
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSUInteger i = 0;
    
    for (NSString *str in array) {
        BRPaymentRequest *req = [BRPaymentRequest requestWithString:str];
        NSData *data = str.hexToData.reverse;
        
        i++;
        
        // if the clipboard contains a known txHash, we know it's not a hex encoded private key
        if (data.length == sizeof(UInt256) && [manager.wallet transactionForHash:*(UInt256 *)data.bytes]) continue;
        
        if ([req.paymentAddress isValidBitcoinAddress] || [req.paymentAddress isValidDashAddress] || [str isValidBitcoinPrivateKey] || [str isValidDashPrivateKey] || [str isValidBitcoinBIP38Key] || [str isValidDashBIP38Key] ||
            (req.r.length > 0 && ([req.scheme isEqual:@"bitcoin:"] || [req.scheme isEqual:@"dash:"]))) {
            [self performSelector:@selector(confirmRequest:) withObject:req afterDelay:0.1];// delayed to show highlight
            return;
        }
        else if (req.r.length > 0) { // may be BIP73 url: https://github.com/bitcoin/bips/blob/master/bip-0073.mediawiki
            [BRPaymentRequest fetch:req.r scheme:req.scheme timeout:5.0 completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) { // don't try any more BIP73 urls
                        [self payFirstFromArray:[array objectsAtIndexes:[array
                                                                         indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                                                                             return (idx >= i && ([obj hasPrefix:@"dash:"] || ! [NSURL URLWithString:obj]));
                                                                         }]]];
                    }
                    else [self confirmProtocolRequest:req];
                });
            }];
            
            return;
        }
    }
    
    [[[UIAlertView alloc] initWithTitle:@""
                                message:NSLocalizedString(@"clipboard doesn't contain a valid dash or bitcoin address", nil) delegate:nil
                      cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    [self performSelector:@selector(cancel:) withObject:self afterDelay:0.1];
}

-(UILabel*)titleLabel {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    UILabel * titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 1, 100)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [titleLabel setBackgroundColor:[UIColor clearColor]];
    NSMutableAttributedString * attributedDashString = [[manager attributedStringForDashAmount:manager.wallet.balance withTintColor:[UIColor whiteColor]] mutableCopy];
    NSString * titleString = [NSString stringWithFormat:@" (%@)",
                              [manager localCurrencyStringForDashAmount:manager.wallet.balance]];
    [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
    titleLabel.attributedText = attributedDashString;
    return titleLabel;
}

-(void)updateTitleView {
    if (self.navigationItem.titleView && [self.navigationItem.titleView isKindOfClass:[UILabel class]]) {
        BRWalletManager *manager = [BRWalletManager sharedInstance];
        NSMutableAttributedString * attributedDashString = [[manager attributedStringForDashAmount:manager.wallet.balance withTintColor:[UIColor whiteColor]] mutableCopy];
        NSString * titleString = [NSString stringWithFormat:@" (%@)",
                                  [manager localCurrencyStringForDashAmount:manager.wallet.balance]];
        [attributedDashString appendAttributedString:[[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}]];
        ((UILabel*)self.navigationItem.titleView).attributedText = attributedDashString;
    } else {
        self.navigationItem.titleView = [self titleLabel];
    }
}

#pragma mark - Shapeshift

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    DSShapeshiftEntity * shapeshift = (DSShapeshiftEntity *)object;
    switch ([shapeshift.shapeshiftStatus integerValue]) {
        case eShapeshiftAddressStatus_Complete:
        {
            NSArray * shapeshiftsInProgress = [DSShapeshiftEntity shapeshiftsInProgress];
            if (![shapeshiftsInProgress count]) {
                self.shapeshiftLabel.text = shapeshift.shapeshiftStatusString;
                self.shapeshiftView.hidden = TRUE;
            }
            [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"shapeshift succeeded", nil)
                                                        center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                                   popOutAfterDelay:2.0]];
            break;
        }
        case eShapeshiftAddressStatus_Received:
            self.shapeshiftLabel.text = shapeshift.shapeshiftStatusString;
        default:
            break;
    }
}


-(void)startObservingShapeshift:(DSShapeshiftEntity*)shapeshift {
    
    [shapeshift addObserver:self forKeyPath:@"shapeshiftStatus" options:NSKeyValueObservingOptionNew context:nil];
    [shapeshift routinelyCheckStatusAtInterval:10];
    self.shapeshiftView.hidden = FALSE;
}


// MARK: - IBAction

- (IBAction)tip:(id)sender
{
    if ([self nextTip]) return;
    
    if (! [sender isKindOfClass:[UIGestureRecognizer class]] || ! [[sender view] isKindOfClass:[UILabel class]]) {
        if (! [sender isKindOfClass:[UIViewController class]]) return;
        self.showTips = YES;
    }
    
    self.tipView = [BRBubbleView viewWithText:SCAN_TIP
                                     tipPoint:CGPointMake(self.scanButton.center.x, self.scanButton.center.y - 10.0)
                                 tipDirection:BRBubbleTipDirectionDown];
    self.tipView.font = [UIFont systemFontOfSize:15.0];
    [self.view addSubview:[self.tipView popIn]];
}

- (IBAction)enableInstantX:(id)sender {
    self.sendInstantly = ((UISwitch*)sender).isOn;
}

- (IBAction)scanQR:(id)sender
{
    if ([self nextTip]) return;
    [BREventManager saveEvent:@"send:scan_qr"];
    if (! [sender isEqual:self.scanButton]) self.showBalance = YES;
    [sender setEnabled:NO];
    self.scanController.delegate = self;
    self.scanController.transitioningDelegate = self;
    [self.navigationController presentViewController:self.scanController animated:YES completion:nil];
}

- (IBAction)payToClipboard:(id)sender
{
    if ([self nextTip]) return;
    [BREventManager saveEvent:@"send:pay_clipboard"];
    
    NSString *str = [[UIPasteboard generalPasteboard].string
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    UIImage *img = [UIPasteboard generalPasteboard].image;
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
    NSCharacterSet *separators = [NSCharacterSet alphanumericCharacterSet].invertedSet;
    
    if (str) {
        [set addObject:str];
        [set addObjectsFromArray:[str componentsSeparatedByCharactersInSet:separators]];
    }
    
    if (img) {
        @synchronized ([CIContext class]) {
            CIContext *context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@(YES)}];
            
            if (! context) context = [CIContext context];
            
            for (CIQRCodeFeature *qr in [[CIDetector detectorOfType:CIDetectorTypeQRCode context:context options:nil]
                                         featuresInImage:[CIImage imageWithCGImage:img.CGImage]]) {
                [set addObject:[qr.messageString
                                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
            }
        }
    }
    
    [sender setEnabled:NO];
    self.clearClipboard = YES;
    [self payFirstFromArray:set.array];
}

- (IBAction)reset:(id)sender
{
    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
    [BREventManager saveEvent:@"send:reset"];
    
    if (self.clearClipboard) [UIPasteboard generalPasteboard].string = @"";
    self.request = nil;
    self.scheme = nil;
    self.associatedShapeshift = nil;
    [self cancel:sender];
    
}

- (IBAction)cancel:(id)sender
{
    [BREventManager saveEvent:@"send:cancel"];
    self.url = self.callback = nil;
    self.sweepTx = nil;
    self.amount = 0;
    self.okAddress = self.okIdentity = nil;
    self.clearClipboard = self.useClipboard = NO;
    self.canChangeAmount = self.showBalance = NO;
    self.scanButton.enabled = self.clipboardButton.enabled = YES;
    [self updateClipboardText];
}

// MARK: - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount
{
    self.amount = amount;
    [self confirmProtocolRequest:self.request];
}


-(void)verifyShapeshiftAmountIsInBounds:(uint64_t)amount completionBlock:(void (^)())completionBlock failureBlock:(void (^)())failureBlock {
    [[DSShapeshiftManager sharedInstance] GET_marketInfo:^(NSDictionary *marketInfo, NSError *error) {
        if (error) {
            failureBlock();
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Shapeshift failed", nil)
                                        message:error.localizedDescription
                                       delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil)
                              otherButtonTitles:nil] show];
        } else {
            BRWalletManager *manager = [BRWalletManager sharedInstance];
            if ([DSShapeshiftManager sharedInstance].min > (amount * .97)) {
                failureBlock();
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Shapeshift failed", nil)
                                            message:[NSString stringWithFormat:NSLocalizedString(@"The amount you wanted to shapeshift is too low, "
                                                                                                 @"please input a value over %@", nil),[manager stringForDashAmount:[DSShapeshiftManager sharedInstance].min / .97]]
                                           delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil)
                                  otherButtonTitles:nil] show];
                return;
            } else if ([DSShapeshiftManager sharedInstance].limit < (amount * 1.03)) {
                failureBlock();
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Shapeshift failed", nil)
                                            message:[NSString stringWithFormat:NSLocalizedString(@"The amount you wanted to shapeshift is too high, "
                                                                                                 @"please input a value under %@", nil),[manager stringForDashAmount:[DSShapeshiftManager sharedInstance].limit / 1.03]]
                                           delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil)
                                  otherButtonTitles:nil] show];
                return;
            }
            completionBlock();
        }
    }];
    
}

- (void)amountViewController:(BRAmountViewController *)amountViewController shapeshiftBitcoinAmount:(uint64_t)amount approximateDashAmount:(uint64_t)dashAmount
{
    MBProgressHUD *hud  = [MBProgressHUD showHUDAddedTo:self.navigationController.topViewController.view animated:YES];
    hud.labelText       = NSLocalizedString(@"Starting Shapeshift!", nil);
    
    [self verifyShapeshiftAmountIsInBounds:dashAmount completionBlock:^{
        //we know the exact amount of bitcoins we want to send
        BRWalletManager *m = [BRWalletManager sharedInstance];
        NSString * address = [NSString bitcoinAddressWithScriptPubKey:self.request.details.outputScripts.firstObject];
        NSString * returnAddress = m.wallet.receiveAddress;
        NSNumber * numberAmount = [m numberForAmount:amount];
        [[DSShapeshiftManager sharedInstance] POST_SendAmount:numberAmount withAddress:address returnAddress:returnAddress completionBlock:^(NSDictionary *shiftInfo, NSError *error) {
            [hud hide:TRUE];
            if (error) {
                NSLog(@"shapeshiftBitcoinAmount Error %@",error);
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Shapeshift failed", nil)
                                            message:error.localizedDescription
                                           delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil)
                                  otherButtonTitles:nil] show];
                return;
            }
            NSString * depositAddress = shiftInfo[@"deposit"];
            NSString * withdrawalAddress = shiftInfo[@"withdrawal"];
            NSNumber * withdrawalAmount = shiftInfo[@"withdrawalAmount"];
            NSNumber * depositAmountNumber = @([shiftInfo[@"depositAmount"] doubleValue]);
            if (depositAmountNumber && [withdrawalAmount floatValue] && [depositAmountNumber floatValue]) {
                uint64_t depositAmount = [[[NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%@",depositAmountNumber]] decimalNumberByMultiplyingByPowerOf10:8]
                                          unsignedLongLongValue];
                self.amount = depositAmount;
                
                DSShapeshiftEntity * shapeshift = [DSShapeshiftEntity registerShapeshiftWithInputAddress:depositAddress andWithdrawalAddress:withdrawalAddress withStatus:eShapeshiftAddressStatus_Unused fixedAmountOut:depositAmountNumber amountIn:depositAmountNumber];
                
                BRPaymentRequest * request = [BRPaymentRequest requestWithString:[NSString stringWithFormat:@"dash:%@?amount=%llu&label=%@&message=Shapeshift to %@",depositAddress,depositAmount,sanitizeString(self.request.commonName),withdrawalAddress]];
                [self confirmProtocolRequest:request.protocolRequest currency:@"dash" associatedShapeshift:shapeshift];
            }
        }];
    } failureBlock:^{
        [hud hide:TRUE];
    }];
}

- (void)amountViewController:(BRAmountViewController *)amountViewController shapeshiftDashAmount:(uint64_t)amount
{
    MBProgressHUD *hud  = [MBProgressHUD showHUDAddedTo:self.navigationController.topViewController.view animated:YES];
    hud.labelText       = NSLocalizedString(@"Starting Shapeshift!", nil);
    [self verifyShapeshiftAmountIsInBounds:amount completionBlock:^{
        //we don't know the exact amount of bitcoins we want to send, we are just sending dash
        BRWalletManager *m = [BRWalletManager sharedInstance];
        NSString * address = [NSString bitcoinAddressWithScriptPubKey:self.request.details.outputScripts.firstObject];
        NSString * returnAddress = m.wallet.receiveAddress;
        self.amount = amount;
        DSShapeshiftEntity * shapeshift = [DSShapeshiftEntity unusedShapeshiftHavingWithdrawalAddress:address];
        NSString * depositAddress = shapeshift.inputAddress;
        
        if (shapeshift) {
            [hud hide:TRUE];
            BRPaymentRequest * request = [BRPaymentRequest requestWithString:[NSString stringWithFormat:@"dash:%@?amount=%llu&label=%@&message=Shapeshift to %@",depositAddress,self.amount,sanitizeString(self.request.commonName),address]];
            [self confirmProtocolRequest:request.protocolRequest currency:@"dash" associatedShapeshift:shapeshift];
        } else {
            [[DSShapeshiftManager sharedInstance] POST_ShiftWithAddress:address returnAddress:returnAddress completionBlock:^(NSDictionary *shiftInfo, NSError *error) {
                [hud hide:TRUE];
                if (error) {
                    NSLog(@"shapeshiftDashAmount Error %@",error);
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Shapeshift failed", nil)
                                                message:error.localizedDescription
                                               delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil)
                                      otherButtonTitles:nil] show];
                    return;
                }
                NSString * depositAddress = shiftInfo[@"deposit"];
                NSString * withdrawalAddress = shiftInfo[@"withdrawal"];
                if (withdrawalAddress && depositAddress) {
                    DSShapeshiftEntity * shapeshift = [DSShapeshiftEntity registerShapeshiftWithInputAddress:depositAddress andWithdrawalAddress:withdrawalAddress withStatus:eShapeshiftAddressStatus_Unused];
                    BRPaymentRequest * request = [BRPaymentRequest requestWithString:[NSString stringWithFormat:@"dash:%@?amount=%llu&label=%@&message=Shapeshift to %@",depositAddress,self.amount,sanitizeString(self.request.commonName),withdrawalAddress]];
                    [self confirmProtocolRequest:request.protocolRequest currency:@"dash" associatedShapeshift:shapeshift];
                }
            }];
        }
    } failureBlock:^{
        [hud hide:TRUE];
    }];
}


// MARK: - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection
{
    for (AVMetadataMachineReadableCodeObject *codeObject in metadataObjects) {
        if (! [codeObject.type isEqual:AVMetadataObjectTypeQRCode]) continue;
        
        [BREventManager saveEvent:@"send:scanned_qr"];
        
        NSString *addr = [codeObject.stringValue stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BRPaymentRequest *request = [BRPaymentRequest requestWithString:addr];
        if (request.url && [BRBitID isBitIDURL:request.url]) {
            [self.scanController stop];
            [self.navigationController dismissViewControllerAnimated:YES completion:^{
                [self handleBitIDURL:request.url];
                [self resetQRGuide];
            }];
        } else if ((request.isValid) || [addr isValidBitcoinPrivateKey] || [addr isValidDashPrivateKey] ||
                   [addr isValidBitcoinBIP38Key] || [addr isValidDashBIP38Key]) {
            self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
            [self.scanController stop];
            [BREventManager saveEvent:@"send:valid_qr_scan"];
            
            if (request.r.length > 0) { // start fetching payment protocol request right away
                [BRPaymentRequest fetch:request.r scheme:request.scheme timeout:5.0
                             completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                                 dispatch_async(dispatch_get_main_queue(), ^{
                                     if (error) request.r = nil;
                                     
                                     if (error && ! request.isValid) {
                                         [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                                                     message:error.localizedDescription delegate:nil
                                                           cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                                         [self cancel:nil];
                                         // continue here and handle the invalid request inside confirmRequest:
                                     }
                                     
                                     [self.navigationController dismissViewControllerAnimated:YES completion:^{
                                         [self resetQRGuide];
                                     }];
                                     
                                     if (error) {
                                         [BREventManager saveEvent:@"send:unsuccessful_qr_payment_protocol_fetch"];
                                         [self confirmRequest:request]; // payment protocol fetch failed, so use standard request
                                     }
                                     else {
                                         [BREventManager saveEvent:@"send:successful_qr_payment_protocol_fetch"];
                                         [self confirmProtocolRequest:req];
                                     }
                                 });
                             }];
            }
            else { // standard non payment protocol request
                [self.navigationController dismissViewControllerAnimated:YES completion:^{
                    [self resetQRGuide];
                    if (request.amount > 0) self.canChangeAmount = YES;
                }];
                
                if (request.isValid && self.showBalance) {
                    [self showBalance:request.paymentAddress];
                    [self cancel:nil];
                }
                else [self confirmRequest:request];
            }
        } else {
            [BRPaymentRequest fetch:request.r scheme:request.scheme timeout:5.0
                         completion:^(BRPaymentProtocolRequest *req, NSError *error) { // check to see if it's a BIP73 url
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetQRGuide) object:nil];
                                 
                                 if (req) {
                                     self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
                                     [self.scanController stop];
                                     
                                     [self.navigationController dismissViewControllerAnimated:YES completion:^{
                                         [self resetQRGuide];
                                     }];
                                     
                                     [BREventManager saveEvent:@"send:successful_bip73"];
                                     [self confirmProtocolRequest:req];
                                 }
                                 else {
                                     self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-red"];
                                     if (([request.scheme isEqual:@"dash"] && request.paymentAddress.length > 1) ||
                                         [request.paymentAddress hasPrefix:@"X"] || [request.paymentAddress hasPrefix:@"7"]) {
                                         self.scanController.message.text = [NSString stringWithFormat:@"%@:\n%@",
                                                                             NSLocalizedString(@"not a valid dash address", nil),
                                                                             request.paymentAddress];
                                     } else if (([request.scheme isEqual:@"bitcoin"] && request.paymentAddress.length > 1) ||
                                         [request.paymentAddress hasPrefix:@"1"] || [request.paymentAddress hasPrefix:@"3"]) {
                                         self.scanController.message.text = [NSString stringWithFormat:@"%@:\n%@",
                                                                             NSLocalizedString(@"not a valid bitcoin address", nil),
                                                                             request.paymentAddress];
                                     }
                                     else self.scanController.message.text = NSLocalizedString(@"not a dash or bitcoin QR code", nil);
                                     
                                     [self performSelector:@selector(resetQRGuide) withObject:nil afterDelay:0.35];
                                     [BREventManager saveEvent:@"send:unsuccessful_bip73"];
                                 }
                             });
                         }];
        }
        
        break;
    }
}

// MARK: - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    
    if (buttonIndex == alertView.cancelButtonIndex || [title isEqual:NSLocalizedString(@"cancel", nil)]) {
        if (self.url) {
            self.clearClipboard = YES;
            [self handleURL:self.url];
        }
        else [self cancelOrChangeAmount];
    }
    else if (self.sweepTx) {
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
    }
    else if (self.request) {
        if ([title isEqual:NSLocalizedString(@"enable", nil)]) {
            self.sendInstantly = TRUE;
            [self.instantSwitch setOn:TRUE animated:TRUE];
            [self confirmProtocolRequest:self.request currency:self.scheme associatedShapeshift:self.associatedShapeshift wantsInstant:TRUE];
        } else if ([title isEqual:NSLocalizedString(@"send", nil)]) {
            [self confirmProtocolRequest:self.request currency:self.scheme associatedShapeshift:self.associatedShapeshift wantsInstant:FALSE];
        } else {
            [self confirmProtocolRequest:self.request currency:self.scheme associatedShapeshift:self.associatedShapeshift];
        }
    }
    else if (self.url) [self handleURL:self.url];
}

// MARK: UITextViewDelegate

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView
{
    if ([self nextTip]) return NO;
    return YES;
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    //BUG: XXX this needs to take keyboard size into account
    self.useClipboard = NO;
    self.clipboardText.text = [UIPasteboard generalPasteboard].string;
    [textView scrollRangeToVisible:textView.selectedRange];
    
    [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.center = CGPointMake(self.view.center.x, self.view.bounds.size.height/2.0 - 100.0);
        self.sendLabel.alpha = 0.0;
    } completion:nil];
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.view.center = CGPointMake(self.view.center.x, self.view.bounds.size.height/2.0);
        self.sendLabel.alpha = 1.0;
    } completion:nil];
    
    if (! self.useClipboard) [UIPasteboard generalPasteboard].string = textView.text;
    [self updateClipboardText];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqual:@"\n"]) {
        [textView resignFirstResponder];
        return NO;
    }
    
    if (text.length > 0 || range.length > 0) self.useClipboard = NO;
    return YES;
}

// MARK: UIViewControllerAnimatedTransitioning

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
    UIImageView *img = self.scanButton.imageView;
    UIView *guide = self.scanController.cameraGuide;
    
    [self.scanController.view layoutIfNeeded];
    
    if (to == self.scanController) {
        [containerView addSubview:to.view];
        to.view.frame = from.view.frame;
        to.view.center = CGPointMake(to.view.center.x, containerView.frame.size.height*3/2);
        guide.transform = CGAffineTransformMakeScale(img.bounds.size.width/guide.bounds.size.width,
                                                     img.bounds.size.height/guide.bounds.size.height);
        guide.alpha = 0;
        
        [UIView animateWithDuration:0.1 animations:^{
            img.alpha = 0.0;
            guide.alpha = 1.0;
        }];
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0 usingSpringWithDamping:0.8
              initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
                  to.view.center = from.view.center;
              } completion:^(BOOL finished) {
                  img.alpha = 1.0;
                  [transitionContext completeTransition:YES];
              }];
        
        [UIView animateWithDuration:0.8 delay:0.15 usingSpringWithDamping:0.5 initialSpringVelocity:0
                            options:UIViewAnimationOptionCurveEaseOut animations:^{
                                guide.transform = CGAffineTransformIdentity;
                            } completion:^(BOOL finished) {
                                [to.view addSubview:guide];
                            }];
    }
    else {
        [containerView insertSubview:to.view belowSubview:from.view];
        [self cancel:nil];
        
        [UIView animateWithDuration:0.8 delay:0.0 usingSpringWithDamping:0.5 initialSpringVelocity:0
                            options:UIViewAnimationOptionCurveEaseIn animations:^{
                                guide.transform = CGAffineTransformMakeScale(img.bounds.size.width/guide.bounds.size.width,
                                                                             img.bounds.size.height/guide.bounds.size.height);
                                guide.alpha = 0.0;
                            } completion:^(BOOL finished) {
                                guide.transform = CGAffineTransformIdentity;
                                guide.alpha = 1.0;
                            }];
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext] - 0.15 delay:0.15
                            options:UIViewAnimationOptionCurveEaseIn animations:^{
                                from.view.center = CGPointMake(from.view.center.x, containerView.frame.size.height*3/2);
                            } completion:^(BOOL finished) {
                                [transitionContext completeTransition:YES];
                            }];
    }
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
