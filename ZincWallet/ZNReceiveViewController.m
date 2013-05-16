//
//  ZNSecondViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNReceiveViewController.h"
#import "ZNPaymentRequest.h"

@interface ZNReceiveViewController ()

@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;
@property (nonatomic, strong) IBOutlet UITextField *amountField, *messageField;
@property (nonatomic, strong) IBOutlet UIButton *requestButton;

@property (nonatomic, strong) GKSession *session;
@property (nonatomic, strong) NSString *peer;
@property (nonatomic, strong) NSNumberFormatter *format;

@end

@implementation ZNReceiveViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.format = [NSNumberFormatter new];
    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
    self.format.currencySymbol = BTC;
}

- (NSString *)paymentAddress
{
    // XXX hard coded for testing
    return @"1JA9nMhjJcUL9nFcrm7ftXXA7PAbyZC5DB";
}

- (NSString *)message
{
    return self.messageField.text;
}

- (NSString *)label
{
    return nil;//@"register #1";
}

- (double)amount
{
    return ((UInt64)([[[self.amountField.text
                        stringByReplacingOccurrencesOfString:_format.currencySymbol withString:@""]
                       stringByReplacingOccurrencesOfString:_format.currencyGroupingSeparator withString:@""]
                      doubleValue]*SATOSHIS))/SATOSHIS;
}

- (ZNPaymentRequest *)paymentRequest
{
    // This should use official payment request protocol when finalized

    ZNPaymentRequest *req = [[ZNPaymentRequest alloc] init];
    req.amount = self.amount;
    req.paymentAddress = self.paymentAddress;
    req.message = self.message;
    req.label = self.label;

    return req;
}

#pragma mark - IBAction

- (IBAction)issueRequest:(id)sender
{
    if (self.session) {
        [self cancelRequest:sender];
        return;
    }

    self.session = [[GKSession alloc] initWithSessionID:GK_SESSION_ID
                    displayName:[NSString stringWithFormat:@"%@ - %@%.17g", self.message, BTC, self.amount]
                    //displayName:[NSString stringWithFormat:@"%@ - %@", self.message, self.amountField.text]
                    sessionMode:GKSessionModeServer];
    self.session.delegate = self;
    [self.session setDataReceiveHandler:self withContext:nil];
    self.session.available = YES;
    
    [self.spinner startAnimating];
    [self.requestButton setTitle:@"cancel" forState:UIControlStateNormal];
    
    [UIView animateWithDuration:0.2 animations:^{
        self.amountField.alpha = 0.0;
        self.messageField.alpha = 0.0;
        self.waitingLabel.alpha = 1.0;
    }];
}

- (IBAction)cancelRequest:(id)sender
{
    self.session.available = NO;
    [self.session disconnectFromAllPeers];
    self.session = nil;
    self.peer = nil;
    
    [self.spinner stopAnimating];
    [self.requestButton setTitle:@"request payment" forState:UIControlStateNormal];
    
    [UIView animateWithDuration:0.2 animations:^{
        self.amountField.alpha = 1.0;
        self.messageField.alpha = 1.0;
        self.waitingLabel.alpha = 0.0;
    }];
}

- (IBAction)number:(id)sender
{
    [self textField:self.amountField shouldChangeCharactersInRange:NSMakeRange(self.amountField.text.length, 0)
     replacementString:[(UIButton *)sender titleLabel].text];
}

- (IBAction)del:(id)sender
{
    if (! self.amountField.text.length) return;
    
    [self textField:self.amountField shouldChangeCharactersInRange:NSMakeRange(self.amountField.text.length - 1, 1)
     replacementString:@""];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    if (! string.length && textField.text.length)
        textField.text = [textField.text substringToIndex:textField.text.length - 1];

    NSInteger amount = [[[[textField.text
                           stringByReplacingOccurrencesOfString:_format.currencySymbol withString:@""]
                          stringByReplacingOccurrencesOfString:_format.currencyGroupingSeparator withString:@""]
                         stringByReplacingOccurrencesOfString:_format.currencyDecimalSeparator withString:@""]
                        integerValue];
        
    if (amount > 99999999) string = @"";
    
    for (int i = 0; i < string.length; i++) amount = amount*10 + string.integerValue;
    
    textField.text = amount ? [_format stringFromNumber:@(amount/100.0)] : nil;
    
    self.requestButton.enabled = (textField.text != nil);
    
    return NO;
}

#pragma mark - GKSessionDelegate

/* Indicates a state change for the given peer.
 */
- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
{
    if (state == GKPeerStateConnected) {
        self.peer = peerID;
        
        NSError *error = nil;
        
        NSLog(@"connected... sending payment reqeust");
        [session sendData:[[self paymentRequest] data] toPeers:@[self.peer] withDataMode:GKSendDataReliable
         error:&error];
    }
    if (state == GKPeerStateDisconnected) {
        [self cancelRequest:nil];
    }
}

/* Indicates a connection request was received from another peer.
 
 Accept by calling -acceptConnectionFromPeer:
 Deny by calling -denyConnectionFromPeer:
 */
- (void)session:(GKSession *)session didReceiveConnectionRequestFromPeer:(NSString *)peerID
{
    NSError *error = nil;
    
    [session acceptConnectionFromPeer:peerID error:&error];
    session.available = NO;
    
    if (error) {
        [[[UIAlertView alloc] initWithTitle:@"Payment failed" message:error.localizedDescription delegate:nil
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        [self cancelRequest:nil];
    }
}

/* Indicates a connection error occurred with a peer, which includes connection request failures, or disconnects due to timeouts.
 */
- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error
{
    [[[UIAlertView alloc] initWithTitle:@"Payment failed" message:error.localizedDescription delegate:nil
      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    [self cancelRequest:nil];
}

/* Indicates an error occurred with the session such as failing to make available.
 */
- (void)session:(GKSession *)session didFailWithError:(NSError *)error
{
    [[[UIAlertView alloc] initWithTitle:@"Payment failed" message:error.localizedDescription delegate:nil
      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    [self cancelRequest:nil];
}

- (void)receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context
{
    [[[UIAlertView alloc] initWithTitle:@"Got Signed Transaction"
      message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] delegate:nil cancelButtonTitle:@"OK"
      otherButtonTitles:nil] show];
    
    // XXX transmit the transaction
    
    [self.session disconnectFromAllPeers];
    self.session = nil;
    self.peer = nil;
    
    [self.spinner stopAnimating];
    [self.requestButton setTitle:@"request payment" forState:UIControlStateNormal];
    
    self.requestButton.enabled = NO;
    self.amountField.text = nil;
    
    [UIView animateWithDuration:0.2 animations:^{
        self.amountField.alpha = 1.0;
        self.messageField.alpha = 1.0;
        self.waitingLabel.alpha = 0.0;
    }];
}


@end
