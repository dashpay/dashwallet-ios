//
//  ZNSecondViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNReceiveViewController.h"
#import "ZNPaymentRequest.h"
#import "ZNWallet.h"
#import "QREncoder.h"

@interface ZNReceiveViewController ()

@property (nonatomic, strong) IBOutlet UIImageView *qrView;
@property (nonatomic, strong) IBOutlet UIButton *addressButton;

//@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;
//@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;
//@property (nonatomic, strong) IBOutlet UITextField *amountField, *messageField;
//@property (nonatomic, strong) IBOutlet UIButton *requestButton;
//
//@property (nonatomic, strong) GKSession *session;
//@property (nonatomic, strong) NSString *peer;
//@property (nonatomic, strong) NSNumberFormatter *format;

@end

@implementation ZNReceiveViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Do any additional setup after loading the view, typically from a nib.
    
    self.addressButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.addressButton.titleLabel.numberOfLines = 1;
    
//    self.format = [NSNumberFormatter new];
//    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
//    self.format.currencySymbol = BTC;
//    [self.format setLenient:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self paymentRequest];
    if (! [[self paymentRequest] isValid]) return;
    
    NSString *s = [[NSString alloc] initWithData:self.paymentRequest.data encoding:NSUTF8StringEncoding];
    
    self.qrView.image = [QREncoder renderDataMatrix:[QREncoder encodeWithECLevel:1 version:1 string:s]
                         imageDimension:self.qrView.frame.size.width];
    
    [self.addressButton setTitle:self.paymentAddress forState:UIControlStateNormal];
}

- (ZNPaymentRequest *)paymentRequest
{
    // This should use official payment request protocol when finalized
    
    return [ZNPaymentRequest requestWithString:self.paymentAddress];

    //    ZNPaymentRequest *req = [ZNPaymentRequest new];
    //    req.paymentAddress = self.paymentAddress;
    //    req.amount = self.amount;
    //    req.message = self.message;
    //    req.label = self.label;
    //
    //    return req;
}

- (NSString *)paymentAddress
{
    return [[ZNWallet sharedInstance] receiveAddress];
}

//- (NSString *)message
//{
//    return self.messageField.text;
//}
//
//- (NSString *)label
//{
//    return nil;//@"register #1";
//}
//
//- (uint64_t)amount
//{
//    return ([[self.format numberFromString:self.amountField.text] doubleValue] + DBL_EPSILON)*SATOSHIS;
//}
//

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    UINavigationController *nav = nil;
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    
    
    if ([title isEqual:@"copy"]) {
        _copiedAddress = [self paymentAddress];
        [[UIPasteboard generalPasteboard] setString:[self paymentAddress]];
    }
    else if ([title isEqual:@"email"]) {
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *c = [MFMailComposeViewController new];
            
            [c setSubject:@"Bitcoin address"];
            [c setMessageBody:[@"bitcoin://" stringByAppendingString:[self paymentAddress]] isHTML:NO];
            c.mailComposeDelegate = self;
            nav = c;
            [self.navController presentViewController:c animated:YES completion:nil];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:nil message:@"email not configured on this device" delegate:nil
              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
    }
    else if ([title isEqual:@"sms"]) {
        if ([MFMessageComposeViewController canSendText]) {
            MFMessageComposeViewController *c = [MFMessageComposeViewController new];
            
            c.body = [@"bitcoin://" stringByAppendingString:[self paymentAddress]];
            c.messageComposeDelegate = self;
            nav = c;
        }
        else {
            [[[UIAlertView alloc] initWithTitle:nil message:@"sms not currently available on this device" delegate:nil
              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
    }
    
    if (nav) {
        [self.navController presentViewController:nav animated:YES completion:nil];
        nav.view.backgroundColor = [UIColor whiteColor];
        nav.navigationBar.titleTextAttributes =
            @{UITextAttributeTextColor:[UIColor lightGrayColor],
              UITextAttributeTextShadowColor:[UIColor whiteColor],
              UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0.0, 1.0)],
              UITextAttributeFont:[UIFont fontWithName:@"HelveticaNeue-Bold" size:19.0]};
    }
}

#pragma mark - MFMessageComposeViewControllerDelegate

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
didFinishWithResult:(MessageComposeResult)result
{
    [self.navController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result
error:(NSError *)error
{
    [self.navController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - IBAction

- (IBAction)address:(id)sender
{
    UIActionSheet *a = [UIActionSheet new];
    
    a.title = [@"Receive bitcoins at this address: " stringByAppendingString:self.paymentAddress];
    a.delegate = self;
    [a addButtonWithTitle:@"copy"];
    if ([MFMailComposeViewController canSendMail]) [a addButtonWithTitle:@"email"];
#if not TARGET_IPHONE_SIMULATOR
    if ([MFMessageComposeViewController canSendText]) [a addButtonWithTitle:@"sms"];
#endif
    [a addButtonWithTitle:@"cancel"];
    a.cancelButtonIndex = a.numberOfButtons - 1;
    
    [a showInView:[[UIApplication sharedApplication] keyWindow]];
}

//- (IBAction)issueRequest:(id)sender
//{
//    if (self.session) {
//        [self cancelRequest:sender];
//        return;
//    }
//
//    self.session = [[GKSession alloc] initWithSessionID:GK_SESSION_ID
//                    displayName:[NSString stringWithFormat:@"%@ - %@%.16g", self.message, BTC,
//                                 (double)self.amount/SATOSHIS] sessionMode:GKSessionModeServer];
//    self.session.delegate = self;
//    [self.session setDataReceiveHandler:self withContext:nil];
//    self.session.available = YES;
//
//    [self.spinner startAnimating];
//    [self.requestButton setTitle:@"cancel" forState:UIControlStateNormal];
//
//    [UIView animateWithDuration:0.2 animations:^{
//        self.amountField.alpha = 0.0;
//        self.messageField.alpha = 0.0;
//        self.waitingLabel.alpha = 1.0;
//    }];
//}
//
//- (IBAction)cancelRequest:(id)sender
//{
//    self.session.available = NO;
//    [self.session disconnectFromAllPeers];
//    self.session = nil;
//    self.peer = nil;
//
//    [self.spinner stopAnimating];
//    [self.requestButton setTitle:@"request payment" forState:UIControlStateNormal];
//
//    [UIView animateWithDuration:0.2 animations:^{
//        self.amountField.alpha = 1.0;
//        self.messageField.alpha = 1.0;
//        self.waitingLabel.alpha = 0.0;
//    }];
//}
//
//- (IBAction)number:(id)sender
//{
//    [self textField:self.amountField shouldChangeCharactersInRange:NSMakeRange(self.amountField.text.length, 0)
//     replacementString:[(UIButton *)sender titleLabel].text];
//}
//
//- (IBAction)del:(id)sender
//{
//    if (! self.amountField.text.length) return;
//
//    [self textField:self.amountField shouldChangeCharactersInRange:NSMakeRange(self.amountField.text.length - 1, 1)
//     replacementString:@""];
//}
//
//#pragma mark - UITextFieldDelegate
//
//- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
//replacementString:(NSString *)string
//{
//    if (! string.length && textField.text.length)
//        textField.text = [textField.text substringToIndex:textField.text.length - 1];
//
//    NSInteger amount = [[self.format numberFromString:textField.text] integerValue];
//
//    if (amount > 99999999) string = @"";
//
//    for (int i = 0; i < string.length; i++) amount = amount*10 + string.integerValue;
//
//    textField.text = amount ? [_format stringFromNumber:@(amount/100.0)] : nil;
//
//    self.requestButton.enabled = (textField.text != nil);
//
//    return NO;
//}
//
//#pragma mark - GKSessionDelegate
//
//// Indicates a state change for the given peer.
//- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
//{
//    if (state == GKPeerStateConnected) {
//        self.peer = peerID;
//        
//        NSError *error = nil;
//        
//        NSLog(@"connected... sending payment reqeust");
//        [session sendData:[[self paymentRequest] data] toPeers:@[self.peer] withDataMode:GKSendDataReliable
//         error:&error];
//    }
//    if (state == GKPeerStateDisconnected) {
//        [self cancelRequest:nil];
//    }
//}
//
//// Indicates a connection request was received from another peer.
////
//// Accept by calling -acceptConnectionFromPeer:
//// Deny by calling -denyConnectionFromPeer:
//- (void)session:(GKSession *)session didReceiveConnectionRequestFromPeer:(NSString *)peerID
//{
//    NSError *error = nil;
//    
//    [session acceptConnectionFromPeer:peerID error:&error];
//    session.available = NO;
//    
//    if (error) {
//        [[[UIAlertView alloc] initWithTitle:@"Payment failed" message:error.localizedDescription delegate:nil
//          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//        [self cancelRequest:nil];
//    }
//}
//
//// Indicates a connection error occurred with a peer, including connection request failures or timeouts.
//- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error
//{
//    [[[UIAlertView alloc] initWithTitle:@"Payment failed" message:error.localizedDescription delegate:nil
//      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//    [self cancelRequest:nil];
//}
//
//// Indicates an error occurred with the session such as failing to make available.
//- (void)session:(GKSession *)session didFailWithError:(NSError *)error
//{
//    [[[UIAlertView alloc] initWithTitle:@"Payment failed" message:error.localizedDescription delegate:nil
//      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//    [self cancelRequest:nil];
//}
//
//- (void)receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context
//{
//    [[[UIAlertView alloc] initWithTitle:@"Got Signed Transaction"
//      message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] delegate:nil cancelButtonTitle:@"OK"
//      otherButtonTitles:nil] show];
//    
//    // XXX transmit the transaction
//    
//    [self.session disconnectFromAllPeers];
//    self.session = nil;
//    self.peer = nil;
//    
//    [self.spinner stopAnimating];
//    [self.requestButton setTitle:@"request payment" forState:UIControlStateNormal];
//    
//    self.requestButton.enabled = NO;
//    self.amountField.text = nil;
//    
//    [UIView animateWithDuration:0.2 animations:^{
//        self.amountField.alpha = 1.0;
//        self.messageField.alpha = 1.0;
//        self.waitingLabel.alpha = 0.0;
//    }];
//}

@end
