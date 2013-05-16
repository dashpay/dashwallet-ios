//
//  ZNFirstViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNPayViewController.h"
#import "ZNWallet.h"
#import "ZNPaymentRequest.h"
#import "NSString+Base58.h"

#define BUTTON_HEIGHT 44
#define BUTTON_MARGIN 5

#define CONNECT_TIMEOUT 5.0

@interface ZNPayViewController ()

@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;

@property (nonatomic, strong) GKSession *session;
@property (nonatomic, strong) NSMutableArray *peers, *requestButtons;
@property (nonatomic, strong) NSMutableDictionary *unsignedRequests;
@property (nonatomic, strong) NSString *selectedPeer;

@end

@implementation ZNPayViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.peers = [NSMutableArray array];
    self.requestButtons = [NSMutableArray array];
    self.unsignedRequests = [NSMutableDictionary dictionary];
    
    double balance = [[ZNWallet singleton] balance];
    
    NSLog(@"wallet balance: %.17g", balance);
    
    //NSLog(@"%@", [@"0004f05543b270f96547c950a2b3ed3afe83d03869" hexToBase58check]);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.session = [[GKSession alloc] initWithSessionID:GK_SESSION_ID
                    displayName:[UIDevice.currentDevice.name stringByAppendingString:@" Wallet"]
                    sessionMode:GKSessionModeClient];
    self.session.delegate = self;
    [self.session setDataReceiveHandler:self withContext:nil];
    self.session.available = YES;

}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    self.session.available = NO;
    [self.session disconnectFromAllPeers];
    self.session = nil;
}

- (void)layoutButtons
{
    while (self.peers.count > self.requestButtons.count) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        CGRect f = self.waitingLabel.frame;

        f.size.height = BUTTON_HEIGHT;
        f.origin.y = self.view.frame.size.height/2 +
                     (BUTTON_HEIGHT + 2*BUTTON_MARGIN)*(self.requestButtons.count - self.peers.count/2.0);
        button.frame = f;
        button.alpha = 0;
        [button addTarget:self action:@selector(doIt:) forControlEvents:UIControlEventTouchUpInside];

        [self.view addSubview:button];

        [self.requestButtons addObject:button];
    }
    
    [UIView animateWithDuration:0.2 animations:^{
        [self.requestButtons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [obj setCenter:CGPointMake([obj center].x, self.view.frame.size.height/2 + BUTTON_HEIGHT/2 + BUTTON_MARGIN +
                                       (BUTTON_HEIGHT + 2*BUTTON_MARGIN)*(idx - self.peers.count/2.0))];
            if (idx < self.peers.count) {
                [obj setTitle:[self.session displayNameForPeer:self.peers[idx]] forState:UIControlStateNormal];
            }
            
            if (self.selectedPeer) {
                [obj setEnabled:NO];
                [obj setAlpha:idx < self.peers.count ? 0.5 : 0];
            }
            else {
                [obj setEnabled:YES];
                [obj setAlpha:idx < self.peers.count ? 1 : 0];
            }
        }];
        
        if (self.peers.count) {
            self.waitingLabel.alpha = 0;
            [self.spinner stopAnimating];
        }
        else {
            self.waitingLabel.alpha = 1;
            [self.spinner startAnimating];
        }
    } completion:^(BOOL finished) {
        while (self.requestButtons.count > self.peers.count) {
            [self.requestButtons.lastObject removeFromSuperview];
            [self.requestButtons removeLastObject];
        }
    }];
}

- (void)confirmRequest
{
    ZNPaymentRequest *req = self.unsignedRequests[self.selectedPeer];
    
    if (req) [[[UIAlertView alloc] initWithTitle:@"Confirm Payment" message:req.message delegate:self
               cancelButtonTitle:@"cancel"
               otherButtonTitles:[NSString stringWithFormat:@"%@%.17g", BTC, req.amount], nil] show];
}

#pragma mark - IBAction

- (IBAction)doIt:(id)sender
{
    NSUInteger idx = [self.requestButtons indexOfObject:sender];
    
    if (idx == NSNotFound) {
        NSLog(@"this shouldn't happen");
        return;
    }
    
    self.selectedPeer = self.peers[idx];

    [sender setEnabled:NO];
    
    [self confirmRequest];
}

#pragma mark - GKSessionDelegate

/* Indicates a state change for the given peer.
 */
- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
{
    NSLog(@"%@ didChangeState:%@", peerID, state == GKPeerStateAvailable ? @"available" :
          state == GKPeerStateUnavailable ? @"unavailable" :
          state == GKPeerStateConnecting ? @"connecting" :
          state == GKPeerStateConnected ? @"connected" :
          state == GKPeerStateDisconnected ? @"disconnected" : @"unkown");

    if (state == GKPeerStateAvailable) {
        if (! [self.peers containsObject:peerID]) {
            [self.peers addObject:peerID];
            
            [session connectToPeer:peerID withTimeout:CONNECT_TIMEOUT];
            
            [self layoutButtons];
        }
    }
    else if (state == GKPeerStateUnavailable || state == GKPeerStateDisconnected) {
        if ([self.peers containsObject:peerID]) {
            [self.peers removeObject:peerID];
            [self layoutButtons];
        }
    }
}

/* Indicates a connection request was received from another peer.
 
 Accept by calling -acceptConnectionFromPeer:
 Deny by calling -denyConnectionFromPeer:
 */
- (void)session:(GKSession *)session didReceiveConnectionRequestFromPeer:(NSString *)peerID
{
    NSLog(@"this shouldn't happen");
    
    [session denyConnectionFromPeer:peerID];
}

/* Indicates a connection error occurred with a peer, which includes connection request failures, or disconnects due to timeouts.
 */
- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error
{
    [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    
    if (peerID == self.selectedPeer) self.selectedPeer = nil;
    
    if ([self.peers containsObject:peerID]) {
        [self.peers removeObject:peerID];
        [self layoutButtons];
    }
}

/* Indicates an error occurred with the session such as failing to make available.
 */
- (void)session:(GKSession *)session didFailWithError:(NSError *)error
{
    self.selectedPeer = nil;
    [self.peers removeAllObjects];
    [self layoutButtons];
    
    [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context
{
    ZNPaymentRequest *req = [ZNPaymentRequest requestWithData:data];

    if (! req.valid) {
        [[[UIAlertView alloc] initWithTitle:@"Couldn't validate payment request"
          message:@"The payment reqeust did not contain a valid merchant signature" delegate:self
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        
        if (peer == self.selectedPeer) self.selectedPeer = nil;
        
        if ([self.peers containsObject:peer]) {
            [self.peers removeObject:peer];
            [self layoutButtons];
        }
        
        return;
    }
    
    NSLog(@"got payment reqeust for %@", peer);
    NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    
    [self.unsignedRequests setObject:req forKey:peer];
    
    if ([self.selectedPeer isEqual:peer]) [self confirmRequest];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self.session disconnectFromAllPeers];
        [self.peers removeObject:self.selectedPeer];
        self.selectedPeer = nil;
        
        [self layoutButtons];

        return;
    }
    
    NSData *signedRequest = [self.unsignedRequests[self.selectedPeer] signedTransaction];
    NSError *error;
    
    NSLog(@"sending signed request to %@", self.selectedPeer);
    [self.session sendData:signedRequest toPeers:@[self.selectedPeer] withDataMode:GKSendDataReliable error:&error];
    
    if (error) {
        [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
    
    [self.peers removeObject:self.selectedPeer];
    self.selectedPeer = nil;
    
    [self layoutButtons];
}

@end
