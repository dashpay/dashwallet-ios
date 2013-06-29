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
#define QR_ID        @"qr"
#define URL_ID       @"url"

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
@property (nonatomic, strong) IBOutlet UIBarButtonItem *refreshButton;

@property (nonatomic, strong) ZNReceiveViewController *receiveController;

@end

@implementation ZNPayViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    ZNPaymentRequest *req = [ZNPaymentRequest new];
    
    req.label = @"scan QR code";
    
    self.requests = [NSMutableArray arrayWithObject:req];
    self.requestIDs = [NSMutableArray arrayWithObject:QR_ID];
    self.requestButtons = [NSMutableArray array];
    self.selectedIndex = NSNotFound;

    // if > iOS 6, we can customize the appearance of the pageControl and don't need the black bar behind it.
    if ([self.pageControl respondsToSelector:@selector(pageIndicatorTintColor)]) {
        self.pageControl.pageIndicatorTintColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        self.pageControl.currentPageIndicatorTintColor = [UIColor grayColor];
        self.view.backgroundColor = self.scrollView.backgroundColor;
    }
    
    self.urlObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:bitcoinURLNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            ZNPaymentRequest *req = [ZNPaymentRequest requestWithURL:note.userInfo[@"url"]];
        
            if (req.isValid && [self.requests indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                return [[req data] isEqualToData:[obj data]] ? (*stop = YES) : NO;
            }] == NSNotFound) {
                [self.requests insertObject:req atIndex:0];
                [self.requestIDs insertObject:URL_ID atIndex:0];
                [self layoutButtonsAnimated:YES];
                [self.scrollView setContentOffset:CGPointZero animated:YES];
            }
        }];
    
    self.syncStartedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:walletSyncStartedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
                                                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            CGRect f = spinner.frame;

            f.size.width = 33;
            spinner.frame = f;
            [spinner startAnimating];
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
        }];

    self.syncFinishedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:walletSyncFinishedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            self.navigationItem.rightBarButtonItem = self.refreshButton;
        }];

    self.syncFailedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:walletSyncFailedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            self.navigationItem.rightBarButtonItem = self.refreshButton;
            
            //XXX need a status bar error message that doesn't require user interaction
            [[[UIAlertView alloc] initWithTitle:@"Couldn't refresh wallet balance" message:[note.userInfo[@"error"]
              localizedDescription] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }];    
}

- (void)viewWillUnload
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];

    [super viewWillUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (! [[ZNWallet sharedInstance] seed]) {
        UINavigationController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNNewWalletNav"];
        
        [self.navigationController presentViewController:c animated:NO completion:nil];
        return;
    }
    
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
    
    static BOOL firstAppearance = YES;
    
    if (firstAppearance) {
        firstAppearance = NO;
    
        [self refresh:nil];
    
        if ([[ZNWallet sharedInstance] balance] == 0) {
            [self.scrollView setContentOffset:CGPointMake(self.scrollView.frame.size.width, 0) animated:NO];
        }
    }
    
    [self layoutButtonsAnimated:NO];
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

- (void)layoutButtonsAnimated:(BOOL)animated
{
    while (self.requests.count > self.requestButtons.count) {
        UIButton *button = [ZNButton buttonWithType:UIButtonTypeCustom];

        button.frame = CGRectMake(BUTTON_MARGIN*4, self.scrollView.frame.size.height/2 +
                                  (BUTTON_HEIGHT + 2*BUTTON_MARGIN)*(self.requestButtons.count-self.requests.count/2.0),
                                  self.scrollView.frame.size.width - BUTTON_MARGIN*8, BUTTON_HEIGHT);
        button.alpha = animated ? 0 : 1;
        [button addTarget:self action:@selector(doIt:) forControlEvents:UIControlEventTouchUpInside];

        [self.scrollView addSubview:button];

        [self.requestButtons addObject:button];
    }

    void (^block)(void) = ^{
        [self.requestButtons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            CGPoint c = CGPointMake([obj center].x, self.scrollView.frame.size.height/2 + BUTTON_HEIGHT/2 +
                                    BUTTON_MARGIN + (BUTTON_HEIGHT + 2*BUTTON_MARGIN)*(idx - self.requests.count/2.0));
            
            [obj setCenter:c];
            
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
    };
    
    if (animated) {
        [UIView animateWithDuration:0.2 animations:block completion:^(BOOL finished) {
            while (self.requestButtons.count > self.requests.count) {
                [self.requestButtons.lastObject removeFromSuperview];
                [self.requestButtons removeLastObject];
            }
        }];
    }
    else {
        block();

        while (self.requestButtons.count > self.requests.count) {
            [self.requestButtons.lastObject removeFromSuperview];
            [self.requestButtons removeLastObject];
        }
    }
}

- (void)confirmRequest:(ZNPaymentRequest *)request
{
    if (! request.isValid) return;
    
    ZNWallet *w = [ZNWallet sharedInstance];
    
    if ([w containsAddress:request.paymentAddress]) {
        [[[UIAlertView alloc] initWithTitle:nil message:@"This payment address is already in your wallet." delegate:nil
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            
        self.selectedIndex = NSNotFound;
    }
    else if (request.amount == 0) {
        ZNAmountViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNAmountViewController"];
            
        c.request = request;
        [self.navigationController pushViewController:c animated:YES];
            
        self.selectedIndex = NSNotFound;
    }
    else if (request.amount < TX_MIN_OUTPUT_AMOUNT) {
        [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment"
          message:[@"Bitcoin payments can't be less than "
                   stringByAppendingString:[w stringForAmount:TX_MIN_OUTPUT_AMOUNT]]
          delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
    else {
        ZNTransaction *tx = [w transactionFor:request.amount to:request.paymentAddress withFee:NO];
        ZNTransaction *txWithFee = [w transactionFor:request.amount to:request.paymentAddress withFee:YES];
        
        NSString *fee = [w stringForAmount:[w transactionFee:txWithFee]];
        NSTimeInterval t = [w timeUntilFree:tx];
        
        if (! tx || (t > DBL_EPSILON && ! txWithFee)) {
            [[[UIAlertView alloc] initWithTitle:@"Insuficient Funds" message:nil delegate:nil cancelButtonTitle:@"OK"
              otherButtonTitles:nil] show];
        }
        else if (t > DBL_MAX - DBL_EPSILON) {
            [[[UIAlertView alloc] initWithTitle:@"transaction fee needed"
              message:[NSString stringWithFormat:@"the bitcoin network needs a fee of %@ to send this payment", fee]
              delegate:self cancelButtonTitle:@"cancel" otherButtonTitles:[NSString stringWithFormat:@"+ %@", fee], nil]
             show];
        }
        else if (t > DBL_EPSILON) {
            NSUInteger minutes = t/60, hours = t/(60*60);
            NSString *time = [NSString stringWithFormat:@"%d %@%@", hours ? hours : minutes,
                              hours ? @"hour" : @"minutes", hours > 1 ? @"s" : @""];
            
            [[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ transaction fee recommended", fee]
              message:[NSString stringWithFormat:@"estimated confirmation time with no fee: %@", time] delegate:self
              cancelButtonTitle:nil otherButtonTitles:@"no fee", [NSString stringWithFormat:@"+ %@", fee], nil] show];
        }
        else {
            w.format.minimumFractionDigits = w.format.maximumFractionDigits;
            [[[UIAlertView alloc] initWithTitle:@"Confirm Payment"
              message:request.message ? request.message : request.paymentAddress delegate:self
             cancelButtonTitle:@"cancel" otherButtonTitles:[w stringForAmount:request.amount], nil] show];
            w.format.minimumFractionDigits = 0;
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
        self.selectedIndex = NSNotFound;
        
        //XXX remove or customize zbar info button
        //XXX also need to add a camera guide
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
            
            [self layoutButtonsAnimated:YES];
        }
    }
    else if (state == GKPeerStateUnavailable || state == GKPeerStateDisconnected) {
        if ([self.requestIDs containsObject:peerID]) {
            NSUInteger idx = [self.requestIDs indexOfObject:peerID];

            [self.requestIDs removeObjectAtIndex:idx];
            [self.requests removeObjectAtIndex:idx];
            [self layoutButtonsAnimated:YES];
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
        [self layoutButtonsAnimated:YES];
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

    [self layoutButtonsAnimated:YES];
    
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
        [self layoutButtonsAnimated:YES];
        
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
        
        [self layoutButtonsAnimated:YES];

        return;
    }
    
    ZNWallet *w = [ZNWallet sharedInstance];
    ZNPaymentRequest *request = self.requests[self.selectedIndex];
    ZNTransaction *tx = [w transactionFor:request.amount to:request.paymentAddress withFee:NO];
    ZNTransaction *txWithFee = [w transactionFor:request.amount to:request.paymentAddress withFee:YES];
    
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    
    if ([title hasPrefix:@"+ "] || [title isEqual:@"no fee"]) {
        if ([title hasPrefix:@"+ "]) tx = txWithFee;
        
        uint64_t fee = [w transactionFee:tx];
    
        w.format.minimumFractionDigits = w.format.maximumFractionDigits;
        [[[UIAlertView alloc] initWithTitle:@"Confirm Payment"
          message:request.message ? request.message : request.paymentAddress delegate:self
          cancelButtonTitle:@"cancel" otherButtonTitles:[w stringForAmount:request.amount + fee], nil] show];
        w.format.minimumFractionDigits = 0;
    }
    else {
        if ([w amountForString:title] > request.amount) tx = txWithFee;
    
        NSLog(@"signing transaction");
        [w signTransaction:tx];
        
        if (! [tx isSigned]) {
            [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:@"error signing bitcoin transaction"
              delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            return;
        }

        NSLog(@"signed transaction:\n%@", [tx toHex]);
        
        if (self.selectedIndex == NSNotFound || [self.requestIDs[self.selectedIndex] isEqual:QR_ID] ||
            [self.requestIDs[self.selectedIndex] isEqual:CLIPBOARD_ID]) {
            
            //XXXX need some kind of spinner feedback, and MBProgressHUD instead of alert
            [w publishTransaction:tx completion:^(NSError *error) {
                [[[UIAlertView alloc] initWithTitle:@"sent!"
                  message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }];
        }
        else {
            NSLog(@"sending signed request to %@", self.requestIDs[self.selectedIndex]);
        
            NSError *error = nil;
            
            [self.session sendData:[[tx toHex] dataUsingEncoding:NSUTF8StringEncoding]
             toPeers:@[self.requestIDs[self.selectedIndex]] withDataMode:GKSendDataReliable error:&error];
    
            if (error) {
                [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
                                  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }
    
            [self.requestIDs removeObjectAtIndex:self.selectedIndex];
            [self.requests removeObjectAtIndex:self.selectedIndex];
        }
        self.selectedIndex = NSNotFound;
    
        [self layoutButtonsAnimated:YES];
    }
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)reader didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    ZNPaymentRequest *req = self.requests[self.selectedIndex];

    req.data = [(NSString *)[[info objectForKey:ZBarReaderControllerResults][0] data]
                dataUsingEncoding:NSUTF8StringEncoding];
    
    if (! req.paymentAddress) {
        [[[UIAlertView alloc] initWithTitle:@"not a bitcoin QR code" message:nil delegate:nil cancelButtonTitle:@"OK"
          otherButtonTitles:nil] show];
    }
    else {
        [reader dismissViewControllerAnimated:YES completion:nil];
        [self.requestButtons[self.selectedIndex] setEnabled:NO];
        [self confirmRequest:req];
    }
}

@end
