//
//  ZNFirstViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNPayViewController.h"
#import "ZNAmountViewController.h"
#import "ZNWallet.h"
#import "ZNPaymentRequest.h"
#import "NSString+Base58.h"
#import "ZNKey.h"
#import "ZNTransaction.h"
#import "ZBarReaderViewController.h"

#define BUTTON_HEIGHT 44
#define BUTTON_MARGIN 5

#define CONNECT_TIMEOUT 5.0

#define CLIPBOARD_ID @"clipboard"
#define QR_ID @"qr"

@interface ZNPayViewController ()

//@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;
//@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;

@property (nonatomic, strong) GKSession *session;
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic, strong) NSMutableArray *requestIDs;
@property (nonatomic, strong) NSMutableArray *requestButtons;
@property (nonatomic, assign) NSUInteger selectedIndex;

@property (nonatomic, strong) IBOutlet UIScrollView *scrollView;

@end

@implementation ZNPayViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.requests = [NSMutableArray array];
    self.requestIDs = [NSMutableArray array];
    self.requestButtons = [NSMutableArray array];
    self.selectedIndex = NSNotFound;

    ZNWallet *w = [ZNWallet sharedInstance];

    [w synchronizeWithCompletionBlock:^(BOOL success) {
        if (! success) {
            NSLog(@"syncronize failed :(");
        }
        else {
            NSLog(@"wallet balance: %.16g", w.balance);
        }
    }];
    
    ZNPaymentRequest *req = [ZNPaymentRequest new];
    
    req.label = @"scan QR";
    [self.requestIDs addObject:QR_ID];
    [self.requests addObject:req];

//    [[UINavigationBar appearance] setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor greenColor],
//     UITextAttributeTextShadowColor:[UIColor redColor],
//     UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0.0f, 1.0f)],
//     UITextAttributeFont:[UIFont fontWithName:@"Helvetica Neue" size:20.0f]}];
    
//    double balance = [[ZNWallet sharedInstance] balance];
//    
//    NSLog(@"wallet balance: %.16g", balance);
//    
//    uint64_t amt = 2100000000000001ull;
//    NSLog(@"uint64_t test: %llu", amt);
//    
//    NSString *tx = [[ZNWallet sharedInstance] transactionFor:0.01 to:[ZNWallet sharedInstance].receiveAddress];
//    
//    NSLog(@"tx hex:\n%@", tx);
    
    //NSLog(@"tx: %@", [[ZNTransaction new] toHex]);
    
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
    
    if ([[UIPasteboard generalPasteboard] string]) {
        ZNPaymentRequest *req = [ZNPaymentRequest requestWithString:[[UIPasteboard generalPasteboard] string]];

        if (req.paymentAddress) {
            if (! req.label.length) req.label = @"pay address from clipboard";
            [self.requests addObject:req];
            [self.requestIDs addObject:CLIPBOARD_ID];
        }
    }
        
    [self layoutButtons];
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
    while (self.requests.count > self.requestButtons.count) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];

        button.frame = CGRectMake(BUTTON_MARGIN*4, self.view.frame.size.height/2 +
                                  (BUTTON_HEIGHT + 2*BUTTON_MARGIN)*(self.requestButtons.count - self.requests.count/2),
                                  self.view.frame.size.width - BUTTON_MARGIN*8, BUTTON_HEIGHT);
        button.alpha = 0;
        [button addTarget:self action:@selector(doIt:) forControlEvents:UIControlEventTouchUpInside];

        [self.view addSubview:button];

        [self.requestButtons addObject:button];
    }
    
    [UIView animateWithDuration:0.2 animations:^{
        [self.requestButtons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [obj setCenter:CGPointMake([obj center].x, self.view.frame.size.height/2 + BUTTON_HEIGHT/2 + BUTTON_MARGIN +
                                       (BUTTON_HEIGHT + 2*BUTTON_MARGIN)*(idx - self.requests.count/2))];
            if (idx < self.requests.count) {
                [obj setTitle:[self.requests[idx] label] forState:UIControlStateNormal];
            }
            
            if (self.selectedIndex != NSNotFound) {
                [obj setEnabled:NO];
                [obj setAlpha:idx < self.requests.count ? 0.5 : 0];
            }
            else {
                [obj setEnabled:YES];
                [obj setAlpha:idx < self.requests.count ? 1 : 0];
            }
        }];
        
    } completion:^(BOOL finished) {
        while (self.requestButtons.count > self.requests.count) {
            [self.requestButtons.lastObject removeFromSuperview];
            [self.requestButtons removeLastObject];
        }
    }];
}

- (void)confirmRequest
{
    if (self.selectedIndex == NSNotFound) {
        NSLog(@"this should never happen");
        return;
    }
    
    ZNPaymentRequest *req = self.requests[self.selectedIndex];
    
    if (req && req.isValid)
        [[[UIAlertView alloc] initWithTitle:@"Confirm Payment" message:req.message delegate:self
          cancelButtonTitle:@"cancel"
          otherButtonTitles:[NSString stringWithFormat:@"%@%.16g", BTC, req.amount], nil] show];
}

#pragma mark - IBAction

- (IBAction)doIt:(id)sender
{
    self.selectedIndex = [self.requestButtons indexOfObject:sender];
    
    if (self.selectedIndex == NSNotFound) {
        NSLog(@"this shouldn't happen");
        return;
    }
    
    if ([self.requestIDs[self.selectedIndex] isEqual:QR_ID]) {
        ZBarReaderViewController *c = [ZBarReaderViewController new];

        c.readerDelegate = self;
        [self.navigationController presentViewController:c animated:YES completion:^{
            NSLog(@"present qr reader complete");
        }];
    }
    else {
        [sender setEnabled:NO];
        [self confirmRequest];
    }
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
        if (! [self.requestIDs containsObject:peerID]) {
            [self.requestIDs addObject:peerID];
            [self.requests addObject:[ZNPaymentRequest new]];
            
            [session connectToPeer:peerID withTimeout:CONNECT_TIMEOUT];
            
            [self layoutButtons];
        }
    }
    else if (state == GKPeerStateUnavailable || state == GKPeerStateDisconnected) {
        if ([self.requestIDs containsObject:peerID]) {
            NSUInteger idx = [self.requestIDs indexOfObject:peerID];

            [self.requestIDs removeObjectAtIndex:idx];
            [self.requests removeObjectAtIndex:idx];
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
    
    if (self.selectedIndex != NSNotFound && [self.requestIDs[self.selectedIndex] isEqual:peerID]) {
        self.selectedIndex = NSNotFound;
    }

    if ([self.requestIDs containsObject:peerID]) {
        NSUInteger idx = [self.requestIDs indexOfObject:peerID];
        
        [self.requestIDs removeObjectAtIndex:idx];
        [self.requests removeObjectAtIndex:idx];
        [self layoutButtons];
    }
}

/* Indicates an error occurred with the session such as failing to make available.
 */
- (void)session:(GKSession *)session didFailWithError:(NSError *)error
{
    if (self.selectedIndex != NSNotFound && ! [self.requestIDs[self.selectedIndex] isEqual:CLIPBOARD_ID] &&
        ! [self.requestIDs[self.selectedIndex] isEqual:QR_ID]) {
        self.selectedIndex = NSNotFound;
    }

    NSIndexSet *indexes = [self.requestIDs indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return ! [obj isEqual:CLIPBOARD_ID] && ! [obj isEqual:QR_ID];
    }];

    [self.requestIDs removeObjectsAtIndexes:indexes];
    [self.requests removeObjectsAtIndexes:indexes];

    [self layoutButtons];
    
    [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context
{
    NSUInteger idx = [self.requestIDs indexOfObject:peer];
    
    if (idx == NSNotFound) {
        NSLog(@"this should never happen");
        return;
    }

    ZNPaymentRequest *req = self.requests[idx];

    [req setData:data];

    if (! req.valid) {
        [[[UIAlertView alloc] initWithTitle:@"Couldn't validate payment request"
          message:@"The payment reqeust did not contain a valid merchant signature" delegate:self
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        
        if (self.selectedIndex == idx) {
            self.selectedIndex = NSNotFound;
        }
        
        [self.requestIDs removeObjectAtIndex:idx];
        [self.requests removeObjectAtIndex:idx];
        [self layoutButtons];
        
        return;
    }
    
    NSLog(@"got payment reqeust for %@", peer);
    NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    
    if (self.selectedIndex == idx) [self confirmRequest];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex || self.selectedIndex == NSNotFound) {
        self.selectedIndex = NSNotFound;
        
        //XXX remove request button?
        
        [self layoutButtons];

        return;
    }
    
    NSData *signedRequest = [self.requests[self.selectedIndex] signedTransaction];
    NSError *error;
    
    NSLog(@"sending signed request to %@", self.requestIDs[self.selectedIndex]);
    [self.session sendData:signedRequest toPeers:@[self.requestIDs[self.selectedIndex]]
     withDataMode:GKSendDataReliable error:&error];
    
    if (error) {
        [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
    
    [self.requestIDs removeObjectAtIndex:self.selectedIndex];
    [self.requests removeObjectAtIndex:self.selectedIndex];
    self.selectedIndex = NSNotFound;
    
    [self layoutButtons];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)reader didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    ZNPaymentRequest *req = self.requests[self.selectedIndex];

    req.data = [(NSString *)[[info objectForKey:ZBarReaderControllerResults][0] data]
                dataUsingEncoding:NSUTF8StringEncoding];
    
    [reader dismissViewControllerAnimated:YES completion:nil];
    
    //XXX would be cooler to display an error message without closing scan window on non-bitcoin qr
    if (! req.paymentAddress) {
        [[[UIAlertView alloc] initWithTitle:@"not a bitcoin qr" message:nil delegate:nil cancelButtonTitle:@"OK"
          otherButtonTitles:nil] show];
    }
    else {
        [self.requestButtons[self.selectedIndex] setEnabled:NO];
        [self confirmRequest];
    }
}

@end
