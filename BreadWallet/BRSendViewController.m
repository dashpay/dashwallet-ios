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
#import "NSData+Bitcoin.h"

#define SCAN_TIP      NSLocalizedString(@"Scan someone else's QR code to get their bitcoin address. "\
                                         "You can send a payment to anyone with an address.", nil)
#define CLIPBOARD_TIP NSLocalizedString(@"Bitcoin addresses can also be copied to the clipboard. "\
                                         "A bitcoin address always starts with '1' or '3'.", nil)

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

@property (nonatomic, assign) BOOL clearClipboard, useClipboard, showTips, showBalance, canChangeAmount;
@property (nonatomic, strong) BRTransaction *sweepTx;
@property (nonatomic, strong) BRPaymentProtocolRequest *request;
@property (nonatomic, strong) NSURL *url, *callback;
@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, strong) NSString *okAddress, *okIdentity;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, strong) BRScanViewController *scanController;
@property (nonatomic, strong) id clipboardObserver;

@property (nonatomic, strong) IBOutlet UILabel *sendLabel;
@property (nonatomic, strong) IBOutlet UIButton *scanButton, *clipboardButton;
@property (nonatomic, strong) IBOutlet UITextView *clipboardText;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *clipboardXLeft;

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
    //TODO: XXX custom url splash image per: "Providing Launch Images for Custom URL Schemes."
    BRWalletManager *m = [BRWalletManager sharedInstance];
    
    if ([url.scheme isEqual:@"bread"]) { // x-callback-url handling: http://x-callback-url.com/specifications/
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
            if ((m.didAuthenticate || [m authenticateWithPrompt:nil andTouchId:YES]) && ! self.clearClipboard) {
                if (! [self.url isEqual:url]) {
                    self.url = url;
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"copy wallet addresses to clipboard?", nil)
                      message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                      otherButtonTitles:NSLocalizedString(@"copy", nil), nil] show];
                }
                else {
                    [UIPasteboard generalPasteboard].string =
                        [[m.wallet.addresses objectsPassingTest:^BOOL(id obj, BOOL *stop) {
                            return [m.wallet addressIsUsed:obj];
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
                                             m.wallet.receiveAddress]];
        }
        else if (([url.host isEqual:@"bitcoin-uri"] || [url.path isEqual:@"/bitcoin-uri"]) && uri &&
                 [[NSURL URLWithString:uri].scheme isEqual:@"bitcoin"]) {
            if (xsuccess) self.callback = [NSURL URLWithString:xsuccess];
            [self handleURL:[NSURL URLWithString:uri]];
        }
        
        if (callback && [[UIApplication sharedApplication] canOpenURL:callback]) {
            [[UIApplication sharedApplication] openURL:callback];
        }
    }
    else if ([url.scheme isEqual:@"bitcoin"]) {
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

- (NSString *)promptForAmount:(uint64_t)amount fee:(uint64_t)fee address:(NSString *)address name:(NSString *)name
memo:(NSString *)memo isSecure:(BOOL)isSecure
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSString *prompt = (isSecure && name.length > 0) ? LOCK @" " : @"";

    //BUG: XXX limit the length of name and memo to avoid having the amount clipped
    if (! isSecure && self.request.errorMessage.length > 0) prompt = [prompt stringByAppendingString:REDX @" "];
    if (name.length > 0) prompt = [prompt stringByAppendingString:sanitizeString(name)];
    if (! isSecure && prompt.length > 0) prompt = [prompt stringByAppendingString:@"\n"];
    if (! isSecure || prompt.length == 0) prompt = [prompt stringByAppendingString:address];
    if (memo.length > 0) prompt = [prompt stringByAppendingFormat:@"\n\n%@", sanitizeString(memo)];
    prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\n\n     amount %@ (%@)", nil),
              [m stringForAmount:amount - fee], [m localCurrencyStringForAmount:amount - fee]];

    if (fee > 0) {
        prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\nnetwork fee +%@ (%@)", nil),
                  [m stringForAmount:fee], [m localCurrencyStringForAmount:fee]];
        prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\n         total %@ (%@)", nil),
                  [m stringForAmount:amount], [m localCurrencyStringForAmount:amount]];
    }

    return prompt;
}

- (void)confirmRequest:(BRPaymentRequest *)request
{
    if (! request.isValid) {
        if ([request.paymentAddress isValidBitcoinPrivateKey] || [request.paymentAddress isValidBitcoinBIP38Key]) {
            [self confirmSweep:request.paymentAddress];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"not a valid bitcoin address", nil)
              message:request.paymentAddress delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
              otherButtonTitles:nil] show];
            [self cancel:nil];
        }
    }
    else if (request.r.length > 0) { // payment protocol over HTTP
        [(id)self.parentViewController.parentViewController startActivityWithTimeout:20.0];

        [BRPaymentRequest fetch:request.r timeout:20.0 completion:^(BRPaymentProtocolRequest *req, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

                if (error && ! [request.paymentAddress isValidBitcoinAddress]) {
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                      message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                      otherButtonTitles:nil] show];
                    [self cancel:nil];
                }
                else [self confirmProtocolRequest:(error) ? request.protocolRequest : req];
            });
        }];
    }
    else [self confirmProtocolRequest:request.protocolRequest];
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)protoReq
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRTransaction *tx = nil;
    uint64_t amount = 0, fee = 0;
    NSString *address = [NSString addressWithScriptPubKey:protoReq.details.outputScripts.firstObject];
    BOOL valid = protoReq.isValid, outputTooSmall = NO;

    if (! valid && [protoReq.errorMessage isEqual:NSLocalizedString(@"request expired", nil)]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"bad payment request", nil) message:protoReq.errorMessage
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    //TODO: check for duplicates of already paid requests

    if (self.amount == 0) {
        for (NSNumber *n in protoReq.details.outputAmounts) {
            if (n.unsignedLongLongValue > 0 && n.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) outputTooSmall = YES;
            amount += n.unsignedLongLongValue;
        }
    }
    else amount = self.amount;

    if ([m.wallet containsAddress:address]) {
        [[[UIAlertView alloc] initWithTitle:@""
          message:NSLocalizedString(@"this payment address is already in your wallet", nil)
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }
    else if (! [self.okAddress isEqual:address] && [m.wallet addressIsUsed:address] &&
             [[UIPasteboard generalPasteboard].string isEqual:address]) {
        self.request = protoReq;
        self.okAddress = address;
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
          message:NSLocalizedString(@"\nADDRESS ALREADY USED\n\nbitcoin addresses are intended for single use only\n\n"
                                    "re-use reduces privacy for both you and the recipient and can result in loss if "
                                    "the recipient doesn't directly control the address", nil)
          delegate:self cancelButtonTitle:nil
          otherButtonTitles:NSLocalizedString(@"ignore", nil), NSLocalizedString(@"cancel", nil), nil] show];
          return;
    }
    else if (protoReq.errorMessage.length > 0 && protoReq.commonName.length > 0 &&
             ! [self.okIdentity isEqual:protoReq.commonName]) {
        self.request = protoReq;
        self.okIdentity = protoReq.commonName;
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"payee identity isn't certified", nil)
          message:protoReq.errorMessage delegate:self cancelButtonTitle:nil
          otherButtonTitles:NSLocalizedString(@"ignore", nil), NSLocalizedString(@"cancel", nil), nil] show];
        return;
    }
    else if (amount == 0 || amount == UINT64_MAX) {
        BRAmountViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"AmountViewController"];
        
        c.delegate = self;
        self.request = protoReq;

        if (protoReq.commonName.length > 0) {
            if (valid && ! [protoReq.pkiType isEqual:@"none"]) {
                c.to = [LOCK @" " stringByAppendingString:sanitizeString(protoReq.commonName)];
            }
            else if (protoReq.errorMessage.length > 0) {
                c.to = [REDX @" " stringByAppendingString:sanitizeString(protoReq.commonName)];
            }
            else c.to = sanitizeString(protoReq.commonName);
        }
        else c.to = address;
        
        c.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                  [m localCurrencyStringForAmount:m.wallet.balance]];
        [self.navigationController pushViewController:c animated:YES];
        return;
    }
    else if (amount < TX_MIN_OUTPUT_AMOUNT) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin payments can't be less than %@", nil),
                   [m stringForAmount:TX_MIN_OUTPUT_AMOUNT]] delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }
    else if (outputTooSmall) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin transaction outputs can't be less than %@",
                                                               nil), [m stringForAmount:TX_MIN_OUTPUT_AMOUNT]]
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }
    
    self.request = protoReq;
    
    if (self.amount == 0) {
        tx = [m.wallet transactionForAmounts:protoReq.details.outputAmounts
              toOutputScripts:protoReq.details.outputScripts withFee:YES];
    }
    else {
        tx = [m.wallet transactionForAmounts:@[@(self.amount)]
              toOutputScripts:@[protoReq.details.outputScripts.firstObject] withFee:YES];
    }
    
    if (tx) {
        amount = [m.wallet amountSentByTransaction:tx] - [m.wallet amountReceivedFromTransaction:tx];
        fee = [m.wallet feeForTransaction:tx];
    }
    else {
        fee = [m.wallet feeForTxSize:[m.wallet transactionFor:m.wallet.balance to:address withFee:NO].size];
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
}

- (void)confirmTransaction:(BRTransaction *)tx withPrompt:(NSString *)prompt forAmount:(uint64_t)amount
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    BOOL auth = m.didAuthenticate;

    if (! tx) {
        if (m.didAuthenticate || [m seedWithPrompt:prompt forAmount:amount]) {
            // if user selected an amount equal to or below wallet balance, but the fee will bring the total above the
            // balance, so offer to reduce the amount to available funds minus fee
            if ((self.amount <= [m amountForLocalCurrencyString:[m localCurrencyStringForAmount:m.wallet.balance]] ||
                 self.amount <= m.wallet.balance) && self.amount > 0) {
                NSUInteger txSize = [m.wallet transactionForAmounts:@[@(m.wallet.balance)]
                                     toOutputScripts:@[self.request.details.outputScripts.firstObject] withFee:NO].size,
                           cpfpSize = 0;
                
                for (tx in m.wallet.recentTransactions) { // add up size of unconfirmed inputs for child-pays-for-parent
                    if (tx.blockHeight != TX_UNCONFIRMED) break;
                    if ([m.wallet amountSentByTransaction:tx] == 0) cpfpSize += tx.size; // only non-change inputs count
                }
                
                int64_t amount = m.wallet.balance - [m.wallet feeForTxSize:txSize + 34 + cpfpSize];
            
                [[[UIAlertView alloc]
                  initWithTitle:NSLocalizedString(@"insufficient funds for bitcoin network fee", nil)
                  message:[NSString stringWithFormat:NSLocalizedString(@"reduce payment amount by\n%@ (%@)?", nil),
                           [m stringForAmount:self.amount - amount],
                           [m localCurrencyStringForAmount:self.amount - amount]] delegate:self
                  cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                  otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:amount - self.amount],
                                     [m localCurrencyStringForAmount:amount - self.amount]], nil] show];
                self.amount = amount;
            }
            else {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"insufficient funds", nil) message:nil
                  delegate:self cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            }
        }
        else [self cancelOrChangeAmount];

        if (! auth) m.didAuthenticate = NO;
        return;
    }
    
    if (! [m.wallet signTransaction:tx withPrompt:prompt]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:NSLocalizedString(@"error signing bitcoin transaction", nil) delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    }
    
    if (! auth) m.didAuthenticate = NO;

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
            sent = YES;
            [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"sent!", nil)
             center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
             popOutAfterDelay:2.0]];
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:YES];
            [(id)self.parentViewController.parentViewController ping];

            if (self.callback && [[UIApplication sharedApplication] canOpenURL:self.callback]) {
                self.callback = [NSURL URLWithString:[self.callback.absoluteString stringByAppendingFormat:@"%@txid=%@",
                                 (self.callback.query.length > 0) ? @"&" : @"?",
                                 [NSString hexWithData:[NSData dataWithBytes:tx.txHash.u8 length:sizeof(UInt256)]]]];
                [[UIApplication sharedApplication] openURL:self.callback];
            }
            
            [self reset:nil];
        }
        
        waiting = NO;
    }];
    
    if (self.request.details.paymentURL.length > 0) {
        uint64_t refundAmount = 0;
        NSMutableData *refundScript = [NSMutableData data];
    
        // use the payment transaction's change address as the refund address, which prevents the same address being
        // used in other transactions in the event no refund is ever issued
        [refundScript appendScriptPubKeyForAddress:m.wallet.changeAddress];
        for (NSNumber *amt in self.request.details.outputAmounts) refundAmount += amt.unsignedLongLongValue;

        // TODO: keep track of commonName/memo to associate them with outputScripts
        BRPaymentProtocolPayment *payment =
            [[BRPaymentProtocolPayment alloc] initWithMerchantData:self.request.details.merchantData
             transactions:@[tx] refundToAmounts:@[@(refundAmount)] refundToScripts:@[refundScript] memo:nil];
    
        NSLog(@"posting payment to: %@", self.request.details.paymentURL);
    
        [BRPaymentRequest postPayment:payment to:self.request.details.paymentURL timeout:20.0
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
                    [m.wallet registerTransaction:tx];
                    [self.view addSubview:[[[BRBubbleView
                     viewWithText:(ack.memo.length > 0 ? ack.memo : NSLocalizedString(@"sent!", nil))
                     center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                     popOutAfterDelay:(ack.memo.length > 0 ? 3.0 : 2.0)]];
                    [(id)self.parentViewController.parentViewController stopActivityWithSuccess:YES];
                    [(id)self.parentViewController.parentViewController ping];

                    if (self.callback && [[UIApplication sharedApplication] canOpenURL:self.callback]) {
                        self.callback =
                            [NSURL URLWithString:[self.callback.absoluteString stringByAppendingFormat:@"%@txid=%@",
                             (self.callback.query.length > 0) ? @"&" : @"?",
                             [NSString hexWithData:[NSData dataWithBytes:tx.txHash.u8 length:sizeof(UInt256)]]]];
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
    if (! [privKey isValidBitcoinPrivateKey] && ! [privKey isValidBitcoinBIP38Key]) return;

    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRBubbleView *v = [BRBubbleView viewWithText:NSLocalizedString(@"checking private key balance...", nil)
                       center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];

    v.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    v.customView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [(id)v.customView startAnimating];
    [self.view addSubview:[v popIn]];

    [m sweepPrivateKey:privKey withFee:YES completion:^(BRTransaction *tx, uint64_t fee, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [v popOut];

            if (error) {
                [[[UIAlertView alloc] initWithTitle:@"" message:error.localizedDescription delegate:self
                  cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                [self cancel:nil];
            }
            else if (tx) {
                uint64_t amount = fee;

                for (NSNumber *amt in tx.outputAmounts) amount += amt.unsignedLongLongValue;
                self.sweepTx = tx;

                [[[UIAlertView alloc] initWithTitle:@"" message:[NSString
                  stringWithFormat:NSLocalizedString(@"Send %@ (%@) from this private key into your wallet? "
                                                     "The bitcoin network will receive a fee of %@ (%@).", nil),
                  [m stringForAmount:amount], [m localCurrencyStringForAmount:amount], [m stringForAmount:fee],
                  [m localCurrencyStringForAmount:fee]] delegate:self
                  cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                  otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:amount],
                                     [m localCurrencyStringForAmount:amount]], nil] show];
            }
            else [self cancel:nil];
        });
    }];
}

- (void)showBalance:(NSString *)address
{
    if (! [address isValidBitcoinAddress]) return;

    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRBubbleView *v = [BRBubbleView viewWithText:NSLocalizedString(@"checking address balance...", nil)
                       center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
    
    v.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    v.customView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [(id)v.customView startAnimating];
    [self.view addSubview:[v popIn]];

    [m utxosForAddress:address completion:^(NSArray *utxos, NSArray *amounts, NSArray *scripts, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [v popOut];
        
            if (error) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't check address balance", nil)
                  message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                  otherButtonTitles:nil] show];
            }
            else {
                uint64_t balance = 0;
            
                for (NSNumber *amt in amounts) balance += amt.unsignedLongLongValue;
            
                [[[UIAlertView alloc] initWithTitle:@""
                  message:[NSString stringWithFormat:NSLocalizedString(@"%@\n\nbalance: %@ (%@)", nil), address,
                           [m stringForAmount:balance], [m localCurrencyStringForAmount:balance]] delegate:nil
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

    BRBubbleView *v = self.tipView;

    self.tipView = nil;
    [v popOut];
    
    if ([v.text hasPrefix:SCAN_TIP]) {
        self.tipView = [BRBubbleView viewWithText:CLIPBOARD_TIP
                        tipPoint:CGPointMake(self.clipboardButton.center.x, self.clipboardButton.center.y + 10.0)
                        tipDirection:BRBubbleTipDirectionUp];
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

- (void)updateClipboardText
{
    NSString *p = [[UIPasteboard generalPasteboard].string
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    UIImage *img = [UIPasteboard generalPasteboard].image;
    NSMutableArray *a = [NSMutableArray array];
    NSCharacterSet *c = [NSCharacterSet alphanumericCharacterSet].invertedSet;
    
    if (p) {
        [a addObject:p];
        [a addObjectsFromArray:[p componentsSeparatedByCharactersInSet:c]];
    }
    
    if (img && CIDetectorTypeQRCode) {
        for (CIQRCodeFeature *qr in [[CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:nil]
                                     featuresInImage:[CIImage imageWithCGImage:img.CGImage]]) {
            [a addObject:[qr.messageString
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        }
    }

    self.clipboardText.text = @"";
    
    for (NSString *s in a) {
        BRPaymentRequest *req = [BRPaymentRequest requestWithString:s];
        
        if ([req.paymentAddress isValidBitcoinAddress]) {
            self.clipboardText.text = (req.label.length > 0) ? sanitizeString(req.label) : req.paymentAddress;
            break;
        }
        else if ([s hasPrefix:@"bitcoin:"]) {
            self.clipboardText.text = sanitizeString(s);
            break;
        }
    }

    CGFloat w = [self.clipboardText.text sizeWithAttributes:@{NSFontAttributeName:self.clipboardText.font}].width + 12;
    
    if (w < self.clipboardButton.bounds.size.width ) w = self.clipboardButton.bounds.size.width;
    if (w > self.view.bounds.size.width - 16.0) w = self.view.bounds.size.width - 16.0;
    self.clipboardXLeft.constant = (self.view.bounds.size.width - w)/2.0;
    [self.clipboardText scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)payFirstFromArray:(NSArray *)a
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSUInteger i = 0;

    for (NSString *s in a) {
        BRPaymentRequest *req = [BRPaymentRequest requestWithString:s];
        NSData *d = s.hexToData.reverse;
        
        i++;
        
        // if the clipboard contains a known txHash, we know it's not a hex encoded private key
        if (d.length == 32 && [[m.wallet.recentTransactions valueForKey:@"txHash"] containsObject:d]) continue;
        
        if ([req.paymentAddress isValidBitcoinAddress] || [s isValidBitcoinPrivateKey] || [s isValidBitcoinBIP38Key] ||
            (req.r.length > 0 && [s hasPrefix:@"bitcoin:"])) {
            [self performSelector:@selector(confirmRequest:) withObject:req afterDelay:0.1];// delayed to show highlight
            return;
        }
        else if (req.r.length > 0) {
            [BRPaymentRequest fetch:req.r timeout:5.0 completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) { // don't try any more BIP73 urls
                        [self payFirstFromArray:[a objectsAtIndexes:[a
                        indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                            return (idx >= i && ([obj hasPrefix:@"bitcoin:"] || ! [NSURL URLWithString:obj]));
                        }]]];
                    }
                    else [self confirmProtocolRequest:req];
                });
            }];
            
            return;
        }
    }
    
    [[[UIAlertView alloc] initWithTitle:@""
      message:NSLocalizedString(@"clipboard doesn't contain a valid bitcoin address", nil) delegate:nil
      cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    [self performSelector:@selector(cancel:) withObject:self afterDelay:0.1];
}

#pragma mark - IBAction

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
    self.tipView.backgroundColor = [UIColor orangeColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    [self.view addSubview:[self.tipView popIn]];
}

- (IBAction)scanQR:(id)sender
{
    if ([self nextTip]) return;
    if (! [sender isEqual:self.scanButton]) self.showBalance = YES;
    [sender setEnabled:NO];
    self.scanController.delegate = self;
    self.scanController.transitioningDelegate = self;
    [self.navigationController presentViewController:self.scanController animated:YES completion:nil];
}

- (IBAction)payToClipboard:(id)sender
{
    if ([self nextTip]) return;

    NSString *p = [[UIPasteboard generalPasteboard].string
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    UIImage *img = [UIPasteboard generalPasteboard].image;
    NSMutableOrderedSet *s = [NSMutableOrderedSet orderedSet];
    NSCharacterSet *c = [NSCharacterSet alphanumericCharacterSet].invertedSet;

    if (p) {
        [s addObject:p];
        [s addObjectsFromArray:[p componentsSeparatedByCharactersInSet:c]];
    }
    
    if (img && CIDetectorTypeQRCode) {
        for (CIQRCodeFeature *qr in [[CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:nil]
                                     featuresInImage:[CIImage imageWithCGImage:img.CGImage]]) {
            [s addObject:[qr.messageString
             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        }
    }
    
    [sender setEnabled:NO];
    self.clearClipboard = YES;
    [self payFirstFromArray:s.array];
}

- (IBAction)reset:(id)sender
{
    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }

    if (self.clearClipboard) [UIPasteboard generalPasteboard].string = @"";
    self.request = nil;
    [self cancel:sender];
}

- (IBAction)cancel:(id)sender
{
    self.url = self.callback = nil;
    self.sweepTx = nil;
    self.amount = 0;
    self.okAddress = self.okIdentity = nil;
    self.clearClipboard = self.useClipboard = NO;
    self.canChangeAmount = self.showBalance = NO;
    self.scanButton.enabled = self.clipboardButton.enabled = YES;
    [self updateClipboardText];
}

#pragma mark - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount
{
    self.amount = amount;
    [self confirmProtocolRequest:self.request];
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
fromConnection:(AVCaptureConnection *)connection
{
    for (AVMetadataMachineReadableCodeObject *o in metadataObjects) {
        if (! [o.type isEqual:AVMetadataObjectTypeQRCode]) continue;

        NSString *s = [o.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BRPaymentRequest *request = [BRPaymentRequest requestWithString:s];

        if ((! request.isValid && ! [s isValidBitcoinPrivateKey] && ! [s isValidBitcoinBIP38Key]) ||
            (request.r.length > 0 && ! [s hasPrefix:@"bitcoin:"])) {
            [BRPaymentRequest fetch:request.r timeout:5.0
            completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetQRGuide) object:nil];
                    
                    if (req) {
                        self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
                        [self.scanController stop];

                        [self.navigationController dismissViewControllerAnimated:YES completion:^{
                            [self resetQRGuide];
                        }];

                        [self confirmProtocolRequest:req];
                    }
                    else {
                        self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-red"];

                        if (([s hasPrefix:@"bitcoin:"] && request.paymentAddress.length > 1) ||
                            [request.paymentAddress hasPrefix:@"1"] || [request.paymentAddress hasPrefix:@"3"]) {
                            self.scanController.message.text = [NSString stringWithFormat:@"%@\n%@",
                                                                NSLocalizedString(@"not a valid bitcoin address", nil),
                                                                request.paymentAddress];
                        }
                        else self.scanController.message.text = NSLocalizedString(@"not a bitcoin QR code", nil);

                        [self performSelector:@selector(resetQRGuide) withObject:nil afterDelay:0.35];
                    }
                });
            }];
        }
        else {
            self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
            [self.scanController stop];

            if (request.r.length > 0) { // start fetching payment protocol request right away
                [BRPaymentRequest fetch:request.r timeout:5.0
                completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error) request.r = nil;
                    
                        if (error && ! request.isValid) {
                            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                              message:error.localizedDescription delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                            [self cancel:nil];
                        }

                        [self.navigationController dismissViewControllerAnimated:YES completion:^{
                            [self resetQRGuide];
                        }];
                        
                        if (error) {
                            [self confirmRequest:request];
                        }
                        else [self confirmProtocolRequest:req];
                    });
                }];
            }
            else {
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
        }

        break;
    }
}

#pragma mark - UIAlertViewDelegate

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
        [self confirmProtocolRequest:self.request];
    }
    else if (self.url) [self handleURL:self.url];
}

#pragma mark UITextViewDelegate

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
    UIImageView *img = self.scanButton.imageView;
    UIView *guide = self.scanController.cameraGuide;

    [self.scanController.view layoutIfNeeded];

    if (to == self.scanController) {
        [v addSubview:to.view];
        to.view.frame = from.view.frame;
        to.view.center = CGPointMake(to.view.center.x, v.frame.size.height*3/2);
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
        [v insertSubview:to.view belowSubview:from.view];
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
            from.view.center = CGPointMake(from.view.center.x, v.frame.size.height*3/2);
        } completion:^(BOOL finished) {
            [transitionContext completeTransition:YES];
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
