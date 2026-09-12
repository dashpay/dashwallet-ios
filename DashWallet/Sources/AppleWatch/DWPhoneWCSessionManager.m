//
//  DWPhoneWCSessionManager.h
//  DashWallet
//
//  Created by Henry on 10/27/15.
//  Copyright (c) 2015 Aaron Voisine <voisine@gmail.com>
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

#import "DWPhoneWCSessionManager.h"

#import <WatchConnectivity/WatchConnectivity.h>

#import "BRAppleWatchSharedConstants.h"
#import "BRAppleWatchTransactionData.h"
#import "DWAppGroupConstants.h"
#import "UIImage+Utils.h"
#import "dashwallet-Swift.h"

static CGSize const QR_SIZE = {240.0, 240.0};
static CGSize const HOLE_SIZE = {58.0, 58.0};
static CGSize const LOGO_SIZE = {54.0, 54.0};

@interface DWPhoneWCSessionManager () <WCSessionDelegate, SyncingActivityMonitorObserver>

@property WCSession *session;
@property id balanceObserver;
// Coalesces bursts of context sends (every balance tick fires one) into a
// single delayed send — building the context is expensive (recent-tx
// snapshot + CoreImage QR render) and `sendApplicationContext` runs on a
// concurrent queue, so undamped bursts pile up overlapping builds.
@property (atomic) BOOL contextSendScheduled;

@end

@implementation DWPhoneWCSessionManager

+ (instancetype)sharedInstance {
    static DWPhoneWCSessionManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        // prevent pre watchOS iOS access the feature
        if ([WCSession class] && [WCSession isSupported]) {
            self.session = [WCSession defaultSession];
            self.session.delegate = self;
            [self.session activateSession];
            [self sendApplicationContext];

            self.balanceObserver =
                [[NSNotificationCenter defaultCenter] addObserverForName:DWSwiftDashSDKWalletState.balanceDidChangeNotification
                                                                  object:nil
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *_Nonnull note) {
                                                                  if ([SyncingActivityMonitor shared].state == SyncingActivityMonitorStateSyncDone)
                                                                      [self scheduleApplicationContextSend];
                                                              }];

            [[SyncingActivityMonitor shared] addObserver:self];
        }
    }

    return self;
}

- (void)dealloc {
    if (self.balanceObserver)
        [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    [[SyncingActivityMonitor shared] removeObserver:self];
}

#pragma mark - SyncingActivityMonitorObserver

- (void)syncingActivityMonitorProgressDidChange:(double)progress {
}

- (void)syncingActivityMonitorStateDidChangeWithPreviousState:(enum SyncingActivityMonitorState)previousState state:(enum SyncingActivityMonitorState)state {
    if (state == SyncingActivityMonitorStateSyncDone || state == SyncingActivityMonitorStateSyncFailed) {
        [self scheduleApplicationContextSend];
    }
}

// Coalesced entry point for runtime context sends: the first request arms a
// 15s timer; requests landing while armed fold into that send (the context
// is built at send time, so it always reflects the latest state). The watch
// face doesn't need tighter freshness than this, and the damping keeps a
// balance-tick storm during sync from queueing overlapping context builds.
- (void)scheduleApplicationContextSend {
    if (self.contextSendScheduled)
        return;
    self.contextSendScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                       self.contextSendScheduled = NO;
                       [self sendApplicationContext];
                   });
}

- (BOOL)reachable {
    return self.session.reachable;
}

- (void)notifyTransactionString:(NSString *)notification {
    if (self.reachable) {
        NSDictionary *msg = @{
            AW_PHONE_NOTIFICATION_KEY : notification,
            AW_PHONE_NOTIFICATION_TYPE_KEY : @(AWPhoneNotificationTypeTxReceive)
        };

        [self.session sendMessage:msg
            replyHandler:^(NSDictionary<NSString *, id> *_Nonnull replyMessage) {
                NSLog(@"received response from balance update notification to watch: %@", replyMessage);
            }
            errorHandler:^(NSError *_Nonnull error) {
                NSLog(@"got an error sending a balance update notification to watch");
            }];

        NSLog(@"sent a balance update notification to watch: %@", msg);
    }
}

// MARK: - WKSession delegate

- (void)session:(WCSession *)session
    didReceiveMessage:(NSDictionary<NSString *, id> *)message
         replyHandler:(void (^)(NSDictionary<NSString *, id> *replyMessage))replyHandler {
    NSLog(@"DWPhoneWCSessionManager didReceiveMessage %@", message);

    if ([message[AW_SESSION_REQUEST_TYPE] integerValue] == AWSessionRquestTypeFetchData) {
        switch ([message[AW_SESSION_REQUEST_DATA_TYPE_KEY] integerValue]) {
            case AWSessionRquestDataTypeApplicationContextData:
                [self handleApplicationContextDataRequest:message replyHandler:replyHandler];
                // TODO(watch-sync): a watch fetch-data request no longer
                // triggers a phone-side sync — the background-fetch stub it
                // used to call was a no-op and has been removed. The reply
                // above serves the last known balance; it can be stale until
                // the user opens the phone app.
                break;

            case AWSessionRquestDataTypeQRCodeBits: {
                NSString *receiveAddress = [DWSwiftDashSDKReceiveAddressReader receiveAddress];
                DWPaymentURIBuilder *req = [[DWPaymentURIBuilder alloc] initWithAddress:receiveAddress
                                                                                 amount:[message[AW_SESSION_QR_CODE_BITS_KEY] integerValue]];
                NSLog(@"watch requested a qr code amount %lld", req.amount);

                NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
                UIImage *image = nil;

                if ([req.data isEqual:[defs objectForKey:APP_GROUP_REQUEST_DATA_KEY]]) {
                    image = [UIImage imageWithData:[defs objectForKey:APP_GROUP_QR_IMAGE_KEY]];
                }

                if (!image && req.data) {
                    image = [self qrCodeImageForData:req.data];
                }
                replyHandler(image ? @{AW_QR_CODE_BITS_KEY : UIImagePNGRepresentation(image)} : @{});
                break;
            }

            default:
                replyHandler(@{});
        }
    }
    else {
        replyHandler(@{});
    }
}

- (void)session:(nonnull WCSession *)session activationDidCompleteWithState:(WCSessionActivationState)activationState error:(nullable NSError *)error {
}


- (void)sessionDidBecomeInactive:(nonnull WCSession *)session {
}


- (void)sessionDidDeactivate:(nonnull WCSession *)session {
}


// MARK: - request handlers

- (void)handleApplicationContextDataRequest:(NSDictionary *)request
                               replyHandler:(void (^)(NSDictionary<NSString *, id> *replyMessage))replyHandler {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[self applicationContextData]
                                         requiringSecureCoding:NO
                                                         error:nil];

    NSDictionary *replay = @{AW_SESSION_RESPONSE_KEY : data} ?: @{};

    replyHandler(replay);
}

- (void)sendApplicationContext {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[self applicationContextData]
                                             requiringSecureCoding:NO
                                                             error:nil];
        if (data == nil) {
            return;
        }
        [self.session updateApplicationContext:@{AW_APPLICATION_CONTEXT_KEY : data}
                                         error:nil];
    });
}

- (BRAppleWatchData *)applicationContextData {
    NSArray<DWAppleWatchTransactionSnapshot *> *transactions = [DWAppleWatchSnapshotProvider recentTransactions];
    BOOL hasWallet = [DWAppleWatchSnapshotProvider hasWallet];
    UIImage *qrCodeImage = self.qrCode;
    BRAppleWatchData *appleWatchData = [[BRAppleWatchData alloc] init];

    uint64_t balance = DWSwiftDashSDKWalletState.currentTotalBalance;
    appleWatchData.balance = [CurrencyExchangerObjcWrapper stringForDashAmount:balance];
    appleWatchData.balanceInLocalCurrency = [CurrencyExchangerObjcWrapper localCurrencyStringForDashAmount:balance];
#if SNAPSHOT
    appleWatchData.balance = [CurrencyExchangerObjcWrapper stringForDashAmount:42980000];
    appleWatchData.balanceInLocalCurrency = [CurrencyExchangerObjcWrapper localCurrencyStringForDashAmount:42980000];
#endif
    appleWatchData.receiveMoneyAddress = [DWSwiftDashSDKReceiveAddressReader receiveAddress];
    appleWatchData.transactions = [self recentTransactionListFromTransactions:transactions];
    appleWatchData.receiveMoneyQRCodeImage = qrCodeImage;
    appleWatchData.hasWallet = hasWallet;

    if (transactions.count > 0) {
        appleWatchData.lastestTransction = [self lastTransactionStringFromSnapshot:transactions[0]];
    }

    return appleWatchData;
}

- (nullable NSString *)lastTransactionStringFromSnapshot:(DWAppleWatchTransactionSnapshot *)transaction {
    NSString *transactionTypeString;
    switch ((BRAWTransactionType)transaction.typeRawValue) {
        case BRAWTransactionTypeSent:
            transactionTypeString = NSLocalizedString(@"Sent", @"Sent transaction");
            break;
        case BRAWTransactionTypeReceive:
            transactionTypeString = NSLocalizedString(@"Received", @"Received transaction");
            break;
        case BRAWTransactionTypeMove:
            transactionTypeString = NSLocalizedString(@"Internal Transfer", @"Transaction within the wallet, transfer of own funds");
            break;
        case BRAWTransactionTypeInvalid:
            transactionTypeString = NSLocalizedString(@"Invalid", @"Invalid transaction");
            break;
    }

    return [NSString
        stringWithFormat:@"%@ %@ %@ , %@", transactionTypeString,
                         [transaction.amountText stringByReplacingOccurrencesOfString:@"-"
                                                                           withString:@""],
                         (transaction.amountTextInLocalCurrency.length > 2)
                             ? transaction.amountTextInLocalCurrency
                             : @"",
                         transaction.dateText];
}

- (nullable UIImage *)qrCode {
    if (![DWAppleWatchSnapshotProvider hasWallet]) {
        return nil;
    }

    NSString *receiveAddress = [DWSwiftDashSDKReceiveAddressReader receiveAddress];
    NSData *req = [[DWPaymentURIBuilder alloc] initWithAddress:receiveAddress].data;
    if (!req) {
        return nil;
    }

    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
    UIImage *image = nil;

    if ([req isEqual:[defs objectForKey:APP_GROUP_REQUEST_DATA_KEY]]) {
        image = [UIImage imageWithData:[defs objectForKey:APP_GROUP_QR_IMAGE_KEY]];
    }

    if (!image) {
        image = [self qrCodeImageForData:req];
    }

    return image;
}

- (UIImage *)qrCodeImageForData:(NSData *)imageData {
    NSParameterAssert(imageData);

    UIImage *image = [UIImage dw_imageWithQRCodeData:imageData color:[CIColor blackColor]];

    UIImage *resizedImage = [image dw_resize:QR_SIZE withInterpolationQuality:kCGInterpolationNone];
    resizedImage = [resizedImage dw_imageByCuttingHoleInCenterWithSize:HOLE_SIZE];
    UIImage *overlayLogo = [UIImage imageNamed:@"dash_logo_qr"];
    overlayLogo = [overlayLogo dw_resize:LOGO_SIZE withInterpolationQuality:kCGInterpolationHigh];
    UIImage *result = [resizedImage dw_imageByMergingWithImage:overlayLogo];

    return result;
}

// MARK: - data helper methods

- (NSArray *)recentTransactionListFromTransactions:(NSArray<DWAppleWatchTransactionSnapshot *> *)transactions {
    NSMutableArray *transactionListData = [[NSMutableArray alloc] init];

    for (DWAppleWatchTransactionSnapshot *snapshot in transactions) {
        BRAppleWatchTransactionData *transactionData = [BRAppleWatchTransactionData new];
        transactionData.amountText = snapshot.amountText;
        transactionData.amountTextInLocalCurrency = snapshot.amountTextInLocalCurrency;
        transactionData.dateText = snapshot.dateText;
        transactionData.type = (BRAWTransactionType)snapshot.typeRawValue;
        [transactionListData addObject:transactionData];
    }

    return [transactionListData copy];
}

@end
