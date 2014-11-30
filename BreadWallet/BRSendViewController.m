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
#import "NSData+Hash.h"

#define SCAN_TIP      NSLocalizedString(@"Scan someone else's QR code to get their bitcoin address. "\
                                         "You can send a payment to anyone with an address.", nil)
#define CLIPBOARD_TIP NSLocalizedString(@"Bitcoin addresses can also be copied to the clipboard. "\
                                         "A bitcoin address always starts with '1' or '3'.", nil)

#define LOCK @"\xF0\x9F\x94\x92" // unicode lock symbol U+1F512 (utf-8)
#define REDX @"\xE2\x9D\x8C"     // unicode cross mark U+274C, red x emoji (utf-8)
#define NBSP @"\xC2\xA0"         // no-break space (utf-8)

static NSString *sanitizeString(NSString *s)
{
    NSMutableString *sane = [NSMutableString stringWithString:s ? s : @""];
    
    CFStringTransform((CFMutableStringRef)sane, NULL, kCFStringTransformToUnicodeName, NO);
    return sane;
}

@interface BRSendViewController ()

@property (nonatomic, assign) BOOL clearClipboard, useClipboard, showTips, didAskFee, removeFee;
@property (nonatomic, strong) BRTransaction *sweepTx;
@property (nonatomic, strong) BRPaymentProtocolRequest *request;
@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, strong) NSString *okAddress;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, strong) BRScanViewController *scanController;
@property (nonatomic, strong) id clipboardObserver;

@property (nonatomic, strong) IBOutlet UILabel *sendLabel;
@property (nonatomic, strong) IBOutlet UIButton *scanButton, *clipboardButton;
@property (nonatomic, strong) IBOutlet UITextView *clipboardText;

@end

@implementation BRSendViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // TODO: XXXX redesign page with round buttons like the iOS power down screen... apple watch also has round buttons
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
                 viewWithText:(payment.memo.length > 0 ? payment.memo : NSLocalizedString(@"received", nil))
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

- (NSString *)promptForAmount:(uint64_t)amount fee:(uint64_t)fee address:(NSString *)address name:(NSString *)name
memo:(NSString *)memo isSecure:(BOOL)isSecure
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSString *prompt = (isSecure && name.length > 0) ? LOCK @" " : @"";

    //BUG: XXXX limit the length of name and memo to avoid having the amount clipped
    if (! isSecure && self.request.errorMessage.length > 0) prompt = [prompt stringByAppendingString:REDX @" "];
    if (name.length > 0) prompt = [prompt stringByAppendingString:sanitizeString(name)];
    if (! isSecure && prompt.length > 0) prompt = [prompt stringByAppendingString:@"\n"];
    if (! isSecure || prompt.length == 0) prompt = [prompt stringByAppendingString:address];
    if (memo.length > 0) prompt = [prompt stringByAppendingFormat:@"\n\n%@", sanitizeString(memo)];
    prompt = [prompt stringByAppendingFormat:@"\n\n%@ (%@)", [m stringForAmount:amount - fee],
              [m localCurrencyStringForAmount:amount - fee]];

    if (fee > 0) {
        prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\nbitcoin network fee +%@ (%@)", nil),
                  [m stringForAmount:fee], [m localCurrencyStringForAmount:fee]];
        prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\ntotal %@ (%@)", nil),
                  [m stringForAmount:amount], [m localCurrencyStringForAmount:amount]];
    }

    self.okAddress = nil;
    return prompt;
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
    }
    else if (request.r.length > 0) { // payment protocol over HTTP
        [(id)self.parentViewController.parentViewController startActivityWithTimeout:20.0];

        [BRPaymentRequest fetch:request.r timeout:20.0 completion:^(BRPaymentProtocolRequest *req, NSError *error) {
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

            if (error) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                  message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
                  otherButtonTitles:nil] show];
                [self cancel:nil];
            }
            else [self confirmProtocolRequest:req];
        }];
    }
    else [self confirmProtocolRequest:request.protocolRequest];
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)protoReq
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    uint64_t amount = 0, fee = 0;
    NSString *address = [NSString addressWithScriptPubKey:protoReq.details.outputScripts.firstObject];
    BOOL valid = [protoReq isValid], outputTooSmall = NO;

    if (! valid && [protoReq.errorMessage isEqual:NSLocalizedString(@"request expired", nil)]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"bad payment request", nil) message:protoReq.errorMessage
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    //TODO: check for duplicates of already paid requests

    for (NSNumber *n in protoReq.details.outputAmounts) {
        if ([n unsignedLongLongValue] < TX_MIN_OUTPUT_AMOUNT) outputTooSmall = YES;
        amount += [n unsignedLongLongValue];
    }

    if ([m.wallet containsAddress:address]) {
        [[[UIAlertView alloc] initWithTitle:nil
          message:NSLocalizedString(@"this payment address is already in your wallet", nil)
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }
    else if (! [self.okAddress isEqual:address] && [m.wallet addressIsUsed:address] &&
             [[[UIPasteboard generalPasteboard] string] isEqual:address]) {
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
    else if (amount == 0 && self.amount == 0) {
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
        else c.to = [NSString addressWithScriptPubKey:protoReq.details.outputScripts.firstObject];
        
        c.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                  [m localCurrencyStringForAmount:m.wallet.balance]];
        [self.navigationController pushViewController:c animated:YES];
        return;
    }
    else if (amount > 0 && amount < TX_MIN_OUTPUT_AMOUNT) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin payments can't be less than %@", nil),
                   [m stringForAmount:TX_MIN_OUTPUT_AMOUNT]] delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }
    else if (amount > 0 && outputTooSmall) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin transaction outputs can't be less than %@",
                                                               nil), [m stringForAmount:TX_MIN_OUTPUT_AMOUNT]]
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    BRTransaction *tx = nil;
    
    self.request = protoReq;
    
    if (self.amount > 0) {
        amount = self.amount;
        tx = [m.wallet transactionForAmounts:@[@(self.amount)]
              toOutputScripts:@[protoReq.details.outputScripts.firstObject] withFee:NO];
    }
    else {
        tx = [m.wallet transactionForAmounts:protoReq.details.outputAmounts
              toOutputScripts:protoReq.details.outputScripts withFee:NO];
    }

    if (tx && [m.wallet blockHeightUntilFree:tx] <= [[BRPeerManager sharedInstance] lastBlockHeight] + 1 &&
        ! self.didAskFee && [[NSUserDefaults standardUserDefaults] boolForKey:SETTINGS_SKIP_FEE_KEY]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"bitcoin network fee", nil)
          message:[NSString stringWithFormat:NSLocalizedString(@"the standard bitcoin network fee for this transaction "
                                                               "is %@ (%@)\n\nremoving this fee may delay confirmation",
                                                               nil),
                   [m stringForAmount:tx.standardFee], [m localCurrencyStringForAmount:tx.standardFee]]
          delegate:self cancelButtonTitle:nil
          otherButtonTitles:NSLocalizedString(@"remove fee", nil), NSLocalizedString(@"continue", nil), nil] show];
        return;
    }

    if (tx) amount = [m.wallet amountSentByTransaction:tx] - [m.wallet amountReceivedFromTransaction:tx];
    
    if (! self.removeFee) {
        fee = tx.standardFee;
        amount += fee;
        
        if (self.amount > 0) {
            tx = [m.wallet transactionForAmounts:@[@(self.amount)]
                  toOutputScripts:@[protoReq.details.outputScripts.firstObject] withFee:YES];
        }
        else {
            tx = [m.wallet transactionForAmounts:protoReq.details.outputAmounts
                  toOutputScripts:protoReq.details.outputScripts withFee:YES];
        }

        if (tx) {
            amount = [m.wallet amountSentByTransaction:tx] - [m.wallet amountReceivedFromTransaction:tx];
            fee = [m.wallet feeForTransaction:tx];
        }
    }

    for (NSData *script in protoReq.details.outputScripts) {
        NSString *addr = [NSString addressWithScriptPubKey:script];
            
        if (! addr) addr = NSLocalizedString(@"unrecognized address", nil);
        if ([address rangeOfString:addr].location != NSNotFound) continue;
        address = [address stringByAppendingFormat:@"%@%@", (address.length > 0) ? @", " : @"", addr];
    }
    
    NSString *prompt = [self promptForAmount:amount fee:fee address:address name:protoReq.commonName
                        memo:protoReq.details.memo isSecure:(valid && ! [protoReq.pkiType isEqual:@"none"])];
    
    if (! tx) {
        if (m.didAuthenticate || [m seedWithPrompt:prompt forAmount:amount]) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"insufficient funds", nil) message:nil
              delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        }
        
        [self cancel:nil];
        return;
    }
    
    if (! [m.wallet signTransaction:tx withPrompt:prompt]) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
          message:NSLocalizedString(@"error signing bitcoin transaction", nil) delegate:nil
          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    }
    
    if (! [tx isSigned]) { // user canceled authentication
        [self cancel:nil];
        return;
    }
    
    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
    
    [(id)self.parentViewController.parentViewController startActivityWithTimeout:30.0];
    
    [[BRPeerManager sharedInstance] publishTransaction:tx completion:^(NSError *error) {
        if (protoReq.details.paymentURL.length > 0) return;
        [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];
    
        if (error) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
              message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
              otherButtonTitles:nil] show];
            [self cancel:nil];
        }
        else {
            //TODO: show full screen sent dialog with tx info, "you sent b10,000 to bob"
            [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"sent!", nil)
             center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
              popOutAfterDelay:2.0]];
            [self reset:nil];
        }
    }];
    
    if (protoReq.details.paymentURL.length > 0) {
        uint64_t refundAmount = 0;
        NSMutableData *refundScript = [NSMutableData data];
    
        // use the payment transaction's change address as the refund address, which prevents the same address being
        // used in other transactions in the event no refund is ever issued
        [refundScript appendScriptPubKeyForAddress:m.wallet.changeAddress];
    
        for (NSNumber *amount in protoReq.details.outputAmounts) {
            refundAmount += [amount unsignedLongLongValue];
        }

        // TODO: keep track of commonName/memo to associate them with outputScripts
        BRPaymentProtocolPayment *payment =
            [[BRPaymentProtocolPayment alloc] initWithMerchantData:protoReq.details.merchantData
             transactions:@[tx] refundToAmounts:@[@(refundAmount)] refundToScripts:@[refundScript] memo:nil];
    
        NSLog(@"posting payment to: %@", protoReq.details.paymentURL);
    
        [BRPaymentRequest postPayment:payment to:protoReq.details.paymentURL timeout:20.0
        completion:^(BRPaymentProtocolACK *ack, NSError *error) {
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];
    
            if (error && [m.wallet transactionForHash:tx.txHash] == nil) {
                [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:nil
                  cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                [self cancel:nil];
            }
            else {
                [self.view
                 addSubview:[[[BRBubbleView
                               viewWithText:(ack.memo.length > 0 ? ack.memo : NSLocalizedString(@"sent!", nil))
                               center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                             popOutAfterDelay:(ack.memo.length > 10 ? 3.0 : 2.0)]];
                [self reset:nil];
    
                if (error) NSLog(@"%@", error.localizedDescription); // transaction was sent despite pay protocol error
            }
        }];
    }
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
    [self.clipboardText resignFirstResponder];
    if (self.tipView.alpha < 0.5) return [(id)self.parentViewController.parentViewController nextTip];

    BRBubbleView *v = self.tipView;

    self.tipView = nil;
    [v popOut];
    
    if ([v.text hasPrefix:SCAN_TIP]) {
        self.tipView = [BRBubbleView viewWithText:CLIPBOARD_TIP
                        tipPoint:CGPointMake(self.clipboardButton.center.x, self.clipboardButton.center.y + 10.0)
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

- (void)updateClipboardText
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSString *p = [[[UIPasteboard generalPasteboard] string]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *c = [[NSCharacterSet alphanumericCharacterSet] invertedSet];

    if (! p) p = @"";
    self.clipboardText.text = @"";
    
    for (NSString *s in [@[p] arrayByAddingObjectsFromArray:[p componentsSeparatedByCharactersInSet:c]]) {
        BRPaymentRequest *req = [BRPaymentRequest requestWithString:s];
        NSData *d = s.hexToData.reverse;
        
        // if the clipboard contains a known txHash, we know it's not a hex encoded private key
        if (d.length == 32 && [[m.wallet.recentTransactions valueForKey:@"txHash"] containsObject:d]) continue;
        
        if ([req.paymentAddress isValidBitcoinAddress]) {
            self.clipboardText.text = (req.label.length > 0) ? sanitizeString(req.label) : req.paymentAddress;
            break;
        }
        else if ([req isValid] || [s isValidBitcoinPrivateKey] || [s isValidBitcoinBIP38Key]) {
            self.clipboardText.text = sanitizeString(s);
            break;
        }
    }

    if ([self.clipboardText.text sizeWithAttributes:@{NSFontAttributeName:self.clipboardText.font}].width < 210.0) {
        self.clipboardText.text = [@"    " stringByAppendingString:self.clipboardText.text];
    }
    
    [self.clipboardText scrollRangeToVisible:NSMakeRange(0, 0)];
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
    if (self.showTips) self.tipView.text = [self.tipView.text stringByAppendingString:@" (5/6)"];
    self.tipView.backgroundColor = [UIColor orangeColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    [self.view addSubview:[self.tipView popIn]];
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
    if ([self nextTip]) return;

    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSString *p = [[[UIPasteboard generalPasteboard] string]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *c = [[NSCharacterSet alphanumericCharacterSet] invertedSet];

    [sender setEnabled:NO];
    self.clearClipboard = YES;
    if (! p) p = @"";

    for (NSString *s in [@[p] arrayByAddingObjectsFromArray:[p componentsSeparatedByCharactersInSet:c]]) {
        BRPaymentRequest *req = [BRPaymentRequest requestWithString:s];
        NSData *d = s.hexToData.reverse;

        // if the clipboard contains a known txHash, we know it's not a hex encoded private key
        if (d.length == 32 && [[m.wallet.recentTransactions valueForKey:@"txHash"] containsObject:d]) continue;
        
        if ([req isValid] || [s isValidBitcoinPrivateKey] || [s isValidBitcoinBIP38Key]) {
            [self performSelector:@selector(confirmRequest:) withObject:req afterDelay:0.1];// delayed to show highlight
            return;
        }
    }
    
    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"clipboard doesn't contain a valid bitcoin address", nil)
      message:nil delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
    [self performSelector:@selector(cancel:) withObject:self afterDelay:0.1];
}

- (IBAction)reset:(id)sender
{
    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }

    if (self.clearClipboard) [[UIPasteboard generalPasteboard] setString:@""];
    self.request = nil;
    [self cancel:sender];
}

- (IBAction)cancel:(id)sender
{
    self.sweepTx = nil;
    self.amount = 0;
    self.okAddress = nil;
    self.clearClipboard = self.useClipboard = NO;
    self.didAskFee = self.removeFee = NO;
    self.scanButton.enabled = self.clipboardButton.enabled = YES;
    [self updateClipboardText];
}

#pragma mark - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount
{
    //TODO: XXXX if user selected an amount equal or below wallet balance, but the fee will bring the total above the
    // balance, offer to reduce the amount to available funds minus fee

    self.amount = amount;
    [self confirmProtocolRequest:self.request];
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
                [BRPaymentRequest fetch:request.r timeout:5.0
                completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                    if (error) request.r = nil;
                    
                    if (error && ! [request isValid]) {
                        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                          message:error.localizedDescription delegate:nil
                          cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                        [self cancel:nil];
                        return;
                    }

                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.navigationController dismissViewControllerAnimated:YES completion:^{
                            [self resetQRGuide];
                        }];
                    });
                    
                    // using performSelectorOnMainThread instead of dispatch_async fixes the frozen pincode keyboard bug
                    if (error) {
                        [self performSelectorOnMainThread:@selector(confirmRequest:) withObject:request
                         waitUntilDone:NO];
                    }
                    else {
                        [self performSelectorOnMainThread:@selector(confirmProtocolRequest:) withObject:req
                         waitUntilDone:NO];
                    }
                }];
            }
            else {
                [self.navigationController dismissViewControllerAnimated:YES completion:^{ [self resetQRGuide]; }];
                [self confirmRequest:request];
            }
        }

        break;
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self cancel:nil];
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
    else if (self.okAddress) { // handle address reuse warning response
        if ([title isEqual:NSLocalizedString(@"ignore", nil)]) {
            if (self.request) [self confirmProtocolRequest:self.request];
        }
        else [self cancel:nil];
    }
    else if ([title isEqual:NSLocalizedString(@"remove fee", nil)] ||
             [title isEqual:NSLocalizedString(@"continue", nil)]) {
        self.didAskFee = YES;
        self.removeFee = ([title isEqual:NSLocalizedString(@"remove fee", nil)]) ? YES : NO;
        if (self.request) [self confirmProtocolRequest:self.request];
    }
}

#pragma mark UITextViewDelegate

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView
{
    if ([self nextTip]) return NO;
    
    return YES;
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    //BUG: XXXX this needs to take keyboard size into account
    self.useClipboard = NO;
    self.clipboardText.text = [[UIPasteboard generalPasteboard] string];
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
    
    if (! self.useClipboard) [[UIPasteboard generalPasteboard] setString:textView.text];
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
