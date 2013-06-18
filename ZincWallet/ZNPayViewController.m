//
//  ZNFirstViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNPayViewController.h"
#import "ZNAmountViewController.h"
#import "ZNReceiveViewController.h"
#import "ZNWallet.h"
#import "ZNPaymentRequest.h"
#import "NSString+Base58.h"
#import "ZNKey.h"
#import "ZNTransaction.h"
#import "ZBarReaderViewController.h"
#import "ZNButton.h"

#define BUTTON_HEIGHT 44.0
#define BUTTON_MARGIN 5.0

#define CONNECT_TIMEOUT 5.0

#define CLIPBOARD_ID @"clipboard"
#define QR_ID @"qr"
#define URL_ID @"url"

@interface ZNPayViewController ()

//@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;
//@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;

@property (nonatomic, strong) GKSession *session;
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic, strong) NSMutableArray *requestIDs;
@property (nonatomic, strong) NSMutableArray *requestButtons;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, strong) id urlObserver;
@property (nonatomic, strong) id syncStartedObserver, syncFinishedObserver, syncFailedObserver;

@property (nonatomic, strong) IBOutlet UIScrollView *scrollView;
@property (nonatomic, strong) IBOutlet UIPageControl *pageControl;

@property (nonatomic, strong) ZNReceiveViewController *receiveController;

@end

@implementation ZNPayViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // if iOS 6, we can customize the appearance of the pageControl and don't need the black bar behind it.
    if ([self.pageControl respondsToSelector:@selector(pageIndicatorTintColor)]) {
        self.pageControl.pageIndicatorTintColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        self.pageControl.currentPageIndicatorTintColor = [UIColor grayColor];
        self.view.backgroundColor = self.scrollView.backgroundColor;
    }
    
    self.requests = [NSMutableArray array];
    self.requestIDs = [NSMutableArray array];
    self.requestButtons = [NSMutableArray array];
    self.selectedIndex = NSNotFound;

    self.urlObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:bitcoinURLNotification object:nil queue:nil
    usingBlock:^(NSNotification *note) {
        ZNPaymentRequest *req = [ZNPaymentRequest requestWithURL:note.userInfo[@"url"]];
    
        if (req.isValid) {
            [self.requests insertObject:req atIndex:0];
            [self.requestIDs insertObject:URL_ID atIndex:0];
            [self layoutButtons];
        }
    }];
    
    self.syncStartedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:walletSyncStartedNotification object:nil queue:nil
    usingBlock:^(NSNotification *note) {
    }];

    self.syncFinishedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:walletSyncFinishedNotification object:nil queue:nil
    usingBlock:^(NSNotification *note) {
    }];

    self.syncFailedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:walletSyncFailedNotification object:nil queue:nil
    usingBlock:^(NSNotification *note) {
    }];

    [self refresh:nil];
    
    ZNPaymentRequest *req = [ZNPaymentRequest new];
    
    req.label = @"scan QR code";
    [self.requestIDs addObject:QR_ID];
    [self.requests addObject:req];
    
    if (! [[ZNWallet sharedInstance] seed]) { // first launch
        UINavigationController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNNewWalletNav"];
        [self.navigationController presentViewController:c animated:NO completion:nil];
    }    
}

- (void)viewWillUnload
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];

    [super viewWillUnload];
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
    
    if ([[[UIPasteboard generalPasteboard] string] length] &&
        ! [[[UIPasteboard generalPasteboard] string] isEqual:[[ZNWallet sharedInstance] receiveAddress]]) {
        ZNPaymentRequest *req = [ZNPaymentRequest requestWithString:[[UIPasteboard generalPasteboard] string]];

        if (req.paymentAddress) {
            if (! req.label) {
                req.label = [NSString stringWithFormat:@"%@ - %@", req.paymentAddress,
                             [[ZNWallet sharedInstance] stringForAmount:req.amount]];
            }
        
            if (! req.label.length) req.label = @"pay address from clipboard";
            [self.requests addObject:req];
            [self.requestIDs addObject:CLIPBOARD_ID];
        }
    }
    
    self.scrollView.contentSize = CGSizeMake(self.scrollView.frame.size.width*2, self.scrollView.frame.size.height);
    
    //XXX sould have a main viewcontroller that contains the scrollview, with both pay and receive as subviews
    // having payviewcontroller instantiate receiveviewcontroller like this is ugly
    CGRect f = self.scrollView.frame;
    
    self.receiveController.view.frame = CGRectMake(f.origin.x + f.size.width, f.origin.y, f.size.width, f.size.height);
    [self.receiveController viewWillAppear:NO];
    [self.scrollView addSubview:self.receiveController.view];
    
    [self layoutButtons];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    self.session.available = NO;
    [self.session disconnectFromAllPeers];
    self.session = nil;
}

- (ZNReceiveViewController *)receiveController
{
    if (! _receiveController) {
        _receiveController = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNReceiveViewController"];
        _receiveController.navController = self.navigationController;
    }
    
    return _receiveController;
}

- (void)layoutButtons
{
    while (self.requests.count > self.requestButtons.count) {
        UIButton *button = [ZNButton buttonWithType:UIButtonTypeCustom];

        button.frame = CGRectMake(BUTTON_MARGIN*4, self.scrollView.frame.size.height/2 +
                                  (BUTTON_HEIGHT + 2*BUTTON_MARGIN)*(self.requestButtons.count-self.requests.count/2.0),
                                  self.scrollView.frame.size.width - BUTTON_MARGIN*8, BUTTON_HEIGHT);
        button.alpha = 0;
        [button addTarget:self action:@selector(doIt:) forControlEvents:UIControlEventTouchUpInside];

        [self.scrollView addSubview:button];

        [self.requestButtons addObject:button];
    }
    
    [UIView animateWithDuration:0.2 animations:^{
        [self.requestButtons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [obj setCenter:CGPointMake([obj center].x, self.scrollView.frame.size.height/2 + BUTTON_HEIGHT/2 +
                                       BUTTON_MARGIN + (BUTTON_HEIGHT+2*BUTTON_MARGIN)*(idx-self.requests.count/2.0))];
            if (idx < self.requests.count) {
                ZNPaymentRequest *req = self.requests[idx];
                [obj setTitle:req.label forState:UIControlStateNormal];
                
                if ([req.label rangeOfString:BTC].location != NSNotFound) {
                    [obj titleLabel].font = [UIFont fontWithName:@"HelveticaNeue" size:15];
                }
                else {
                    [obj titleLabel].font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15];
                }                
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

- (void)confirmRequest:(ZNPaymentRequest *)request
{
    //XXX need to handle the situation when the user's own receive address is the payment address
    if (request.isValid) {
        if (request.amount == 0) {
            ZNAmountViewController *c =
                [self.storyboard instantiateViewControllerWithIdentifier:@"ZNAmountViewController"];
            
            c.request = request;
            [self.navigationController pushViewController:c animated:YES];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:@"Confirm Payment" message:request.message delegate:self
             cancelButtonTitle:@"cancel"
             otherButtonTitles:[NSString stringWithFormat:@"%@%.16g", BTC, (double)request.amount/SATOSHIS], nil] show];
        }
    }
}

#pragma mark - IBAction

- (IBAction)doIt:(id)sender
{
    self.selectedIndex = [self.requestButtons indexOfObject:sender];
    
    if (self.selectedIndex == NSNotFound) {
        NSAssert(FALSE, @"[%s %s] line %d: selectedIndex = NSNotFound", object_getClassName(self), sel_getName(_cmd),
                 __LINE__);
        return;
    }
    
    if ([self.requestIDs[self.selectedIndex] isEqual:QR_ID]) {
//        //XXX just for testing
//        [self.requests[self.selectedIndex]
//         setData:[@"1JA9nMhjJcUL9nFcrm7ftXXA7PAbyZC5DB" dataUsingEncoding:NSUTF8StringEncoding]];
//        [self confirmRequest:self.requests[self.selectedIndex]];
//        self.selectedIndex = NSNotFound;
//        return;

        self.selectedIndex = NSNotFound;
        
        ZBarReaderViewController *c = [ZBarReaderViewController new];

        c.readerDelegate = self;
        [self.navigationController presentViewController:c animated:YES completion:^{
            NSLog(@"present qr reader complete");
        }];
    }
    else {
        [sender setEnabled:NO];
        [self confirmRequest:self.requests[self.selectedIndex]];
    }
}

- (IBAction)refresh:(id)sender
{
    [[ZNWallet sharedInstance] synchronize];   
}

- (IBAction)page:(id)sender
{
    if (! [self.scrollView isTracking] && ! [self.scrollView isDecelerating] &&
        self.pageControl.currentPage != self.scrollView.contentOffset.x/self.scrollView.frame.size.width + 0.5) {
        
        [self.scrollView setContentOffset:CGPointMake(self.pageControl.currentPage*self.scrollView.frame.size.width, 0)
         animated:YES];
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    self.pageControl.currentPage = scrollView.contentOffset.x/scrollView.frame.size.width + 0.5;
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
    NSAssert(FALSE, @"[%s %s] line %d: recieved connection request (should be in client mode)",
             object_getClassName(self), sel_getName(_cmd), __LINE__);
    return;

    
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
        NSAssert(FALSE, @"[%s %s] line %d: idx = NSNotFound", object_getClassName(self), sel_getName(_cmd), __LINE__);
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
    
    if (self.selectedIndex == idx) [self confirmRequest:req];
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
    
    NSString *tx = [[ZNWallet sharedInstance] transactionFor:[self.requests[self.selectedIndex] amount]
                    to:[self.requests[self.selectedIndex] paymentAddress]];
    NSError *error;
    
    NSLog(@"sending signed request to %@", self.requestIDs[self.selectedIndex]);
    [self.session sendData:[tx dataUsingEncoding:NSUTF8StringEncoding] toPeers:@[self.requestIDs[self.selectedIndex]]
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
        [[[UIAlertView alloc] initWithTitle:@"not a bitcoin QR code" message:nil delegate:nil cancelButtonTitle:@"OK"
          otherButtonTitles:nil] show];
    }
    else {
        [self.requestButtons[self.selectedIndex] setEnabled:NO];
        [self confirmRequest:req];
    }
}

@end
