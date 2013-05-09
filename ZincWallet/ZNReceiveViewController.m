//
//  ZNSecondViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNReceiveViewController.h"

@interface ZNReceiveViewController ()

@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;
@property (nonatomic, strong) IBOutlet UITextField *amountField, *messageField;
@property (nonatomic, strong) IBOutlet UIButton *requestButton;

@property (nonatomic, strong) GKSession *session;
@property (nonatomic, strong) NSString *peer;

@end

@implementation ZNReceiveViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (NSString *)message
{
    return @"Alice's Coffee Shop";
}

- (double)amount
{
    return 0.01;
}

- (NSData *)paymentRequest
{
    // This should use official payment request protocol when finalized

    return [[NSString stringWithFormat:@"1T7cQHDFLuMVx77cDBn9jKkRQDuasXqt2?amount=%f", self.amount]
            dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - IBAction

- (IBAction)issueRequest:(id)sender
{
    if (self.session) {
        [self cancelRequest:sender];
        return;
    }

    self.session = [[GKSession alloc] initWithSessionID:GK_SESSION_ID
                    displayName:[NSString stringWithFormat:@"%@ - %@%f", self.message, BTC, self.amount]
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

#pragma mark - GKSessionDelegate

/* Indicates a state change for the given peer.
 */
- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
{
    if (state == GKPeerStateConnected) {
        self.peer = peerID;
        
        NSError *error = nil;
        
        NSLog(@"connected... sending payment reqeust");
        [session sendData:[self paymentRequest] toPeers:@[self.peer] withDataMode:GKSendDataReliable error:&error];
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
    NSString *tx = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    [[[UIAlertView alloc] initWithTitle:@"Got Signed Transaction" message:tx delegate:nil
      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    
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


@end
