//
//  BRPhoneWCSessionManager.h
//  BreadWallet
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

#import <WatchConnectivity/WatchConnectivity.h>

#import <DashSync/DashSync.h>
#import <DashSync/UIImage+DSUtils.h>
#import <DashSync/DSTransaction+Utils.h>

#import "BRPhoneWCSessionManager.h"
#import "BRAppleWatchSharedConstants.h"
#import "BRAppleWatchTransactionData.h"
#import "BRAppGroupConstants.h"
#import "BRAppDelegate.h"

@interface BRPhoneWCSessionManager () <WCSessionDelegate>

@property WCSession *session;
@property id balanceObserver, syncFinishedObserver, syncFailedObserver;

@end

@implementation BRPhoneWCSessionManager

+ (instancetype)sharedInstance
{
    static BRPhoneWCSessionManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sharedInstance = [[self alloc] init]; });
    return sharedInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        // prevent pre watchOS iOS access the feature
        if ([WCSession class] && [WCSession isSupported]) {
            self.session = [WCSession defaultSession];
            self.session.delegate = self;
            [self.session activateSession];
            [self sendApplicationContext];
            
            self.balanceObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:DSWalletBalanceDidChangeNotification object:nil
                queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                    DSChainPeerManager *peerManager = [BRAppDelegate sharedDelegate].peerManager;
                    if (peerManager.syncProgress == 1.0) [self sendApplicationContext];
                }];

            self.syncFinishedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:DSChainPeerManagerSyncFinishedNotification
                object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                    [self sendApplicationContext];
                }];

            self.syncFailedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:DSChainPeerManagerSyncFailedNotification object:nil
                queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                    [self sendApplicationContext];
                }];
        }
    }
    
    return self;
}

- (void)dealloc
{
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
}

- (BOOL)reachable
{
    return self.session.reachable;
}

- (void)notifyTransactionString:(NSString *)notification
{
    if (self.reachable) {
        NSDictionary *msg = @{
            AW_PHONE_NOTIFICATION_KEY: notification,
            AW_PHONE_NOTIFICATION_TYPE_KEY: @(AWPhoneNotificationTypeTxReceive)
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
         replyHandler:(void (^)(NSDictionary<NSString *, id> *replyMessage))replyHandler
{
    NSLog(@"BRPhoneWCSessionManager didReceiveMessage %@", message);

    if ([message[AW_SESSION_REQUEST_TYPE] integerValue] == AWSessionRquestTypeFetchData) {
        switch ([message[AW_SESSION_REQUEST_DATA_TYPE_KEY] integerValue]) {
        case AWSessionRquestDataTypeApplicationContextData:
            [self handleApplicationContextDataRequest:message replyHandler:replyHandler];
            // sync with peer whenever there is a request coming, so we can update watch side.
            [(id<UIApplicationDelegate>)[UIApplication sharedApplication].delegate
                                      application:[UIApplication sharedApplication]
                performFetchWithCompletionHandler:^(UIBackgroundFetchResult result) {
                    NSLog(@"watch triggered background fetch completed with result %lu", (unsigned long)result);
                }];
            break;
            
        case AWSessionRquestDataTypeQRCodeBits: {
            DSChain *chain = [BRAppDelegate sharedDelegate].chain;
            DSWallet *wallet = chain.wallets.firstObject;
            DSAccount *account = wallet.accounts.firstObject; // TODO: fix it
            DSPaymentRequest *req = [DSPaymentRequest requestWithString:account.receiveAddress onChain:chain];

            req.amount = [message[AW_SESSION_QR_CODE_BITS_KEY] integerValue];
            NSLog(@"watch requested a qr code amount %lld", req.amount);

            NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
            UIImage *image = nil;
            
            if ([req.data isEqual:[defs objectForKey:APP_GROUP_REQUEST_DATA_KEY]]) {
                image = [UIImage imageWithData:[defs objectForKey:APP_GROUP_QR_IMAGE_KEY]];
            }
            
            if (! image && req.data) {
                image = [UIImage imageWithQRCodeData:req.data color:[CIColor colorWithRed:0.0 green:0.0 blue:0.0]];
            }

            image = [image resize:CGSizeMake(150, 150) withInterpolationQuality:kCGInterpolationNone];
            replyHandler(image ? @{AW_QR_CODE_BITS_KEY: UIImagePNGRepresentation(image)} : @{});
            break;
        }
        
        default: replyHandler(@{});
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
                               replyHandler:(void (^)(NSDictionary<NSString *, id> *replyMessage))replyHandler
{
    NSDictionary *replay =
        @{AW_SESSION_RESPONSE_KEY: [NSKeyedArchiver archivedDataWithRootObject:[self applicationContextData]]};

    replyHandler(replay);
}

- (void)sendApplicationContext
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BRAppleWatchData *appleWatchData = [self applicationContextData];
        [self.session updateApplicationContext:@{
            AW_APPLICATION_CONTEXT_KEY: [NSKeyedArchiver archivedDataWithRootObject:appleWatchData]
        }
                                         error:nil];
    });
}

- (BRAppleWatchData *)applicationContextData
{
    DSPriceManager *manager = [DSPriceManager sharedInstance];
    DSChain *chain = [BRAppDelegate sharedDelegate].chain;
    DSWallet *wallet = chain.wallets.firstObject;
    DSAccount *account = wallet.accounts.firstObject; // TODO: fix it
    NSArray *transactions = account.recentTransactions;
    UIImage *qrCodeImage = self.qrCode;
    BRAppleWatchData *appleWatchData = [[BRAppleWatchData alloc] init];
    
    appleWatchData.balance = [manager stringForDashAmount:wallet.balance];
    appleWatchData.balanceInLocalCurrency = [manager localCurrencyStringForDashAmount:wallet.balance];
#if SNAPSHOT
    appleWatchData.balance = [manager stringForDashAmount:42980000],
    appleWatchData.balanceInLocalCurrency = [manager localCurrencyStringForDashAmount:42980000];
#endif
    appleWatchData.receiveMoneyAddress = account.receiveAddress;
    appleWatchData.transactions = [[self recentTransactionListFromTransactions:transactions] copy];
    appleWatchData.receiveMoneyQRCodeImage = qrCodeImage;
    appleWatchData.hasWallet = chain.hasAWallet;
    
    if (transactions.count > 0) {
        appleWatchData.lastestTransction = [self lastTransactionStringFromTransaction:transactions[0]];
    }
    
    return appleWatchData;
}

- (NSString *)lastTransactionStringFromTransaction:(DSTransaction *)transaction
{
    if (transaction) {
        NSString *timeDescriptionString = [self timeDescriptionStringFrom:transaction.transactionDate];
        NSString *transactionTypeString;
        
        if (timeDescriptionString == nil) {
            timeDescriptionString = transaction.dateText;
        }

        switch (transaction.type) {
        case BRAWTransactionTypeSent: transactionTypeString = @"sent"; break;
        case BRAWTransactionTypeReceive: transactionTypeString = @"received"; break;
        case BRAWTransactionTypeMove: transactionTypeString = @"moved"; break;
        case BRAWTransactionTypeInvalid: transactionTypeString = @"invalid transaction"; break;
        }
        
        NSString *amountText = [transaction amountTextReceivedInAccount:transaction.account];
        NSString *localCurrencyTextForAmount = [transaction localCurrencyTextForAmountReceivedInAccount:transaction.account];

        return [NSString
            stringWithFormat:@"%@ %@ %@ , %@", transactionTypeString,
                             [amountText stringByReplacingOccurrencesOfString:@"-" withString:@""],
                             (localCurrencyTextForAmount.length > 2)
                                 ? localCurrencyTextForAmount
                                 : @"",
                             timeDescriptionString];
    }
    
    return @"no transaction";
}

- (NSString *)timeDescriptionStringFrom:(NSDate *)date
{
    if (date) {
        NSDate *now = [NSDate date];
        NSTimeInterval secondsSinceTransaction = [now timeIntervalSinceDate:date];
        
        if (secondsSinceTransaction < 60) {
            return @"just now";
        }
        else if (secondsSinceTransaction / 60 < 60) {
            return [NSString stringWithFormat:@"%@ minutes ago", @((NSInteger)(secondsSinceTransaction / 60))];
        }
        else if (secondsSinceTransaction / 60 / 60 < 24) {
            return [NSString stringWithFormat:@"%@ hours ago", @((NSInteger)(secondsSinceTransaction / 60 / 60))];
        }
    }
    
    return nil;
}

- (UIImage *)qrCode
{
    DSPriceManager *manager = [DSPriceManager sharedInstance];
    DSChain *chain = [BRAppDelegate sharedDelegate].chain;
    DSWallet *wallet = chain.wallets.firstObject;
    DSAccount *account = wallet.accounts.firstObject; // TODO: fix it
    NSData *req = [DSPaymentRequest requestWithString:account.receiveAddress onChain:chain].data;
    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
    UIImage *image = nil;
    
    if ([req isEqual:[defs objectForKey:APP_GROUP_REQUEST_DATA_KEY]]) {
        image = [UIImage imageWithData:[defs objectForKey:APP_GROUP_QR_IMAGE_KEY]];
    }

    if (! image && req) {
        image = [UIImage imageWithQRCodeData:req color:[CIColor colorWithRed:0.0 green:0.0 blue:0.0]];
    }
    
    return [image resize:CGSizeMake(150, 150) withInterpolationQuality:kCGInterpolationNone];
}

// MARK: - data helper methods

- (NSArray *)recentTransactionListFromTransactions:(NSArray *)transactions
{
    NSMutableArray *transactionListData = [[NSMutableArray alloc] init];
    
    for (DSTransaction *transaction in transactions) {
        [transactionListData addObject:[BRAppleWatchTransactionData appleWatchTransactionDataFrom:transaction]];
    }

#if SNAPSHOT
    DSPriceManager *manager = [DSPriceManager sharedInstance];
    
    [transactionListData removeAllObjects];

    for (int i = 0; i < 6; i++) {
        DSTransaction *tx = [DSTransaction new];
        BRAppleWatchTransactionData *txData = [BRAppleWatchTransactionData new];
        int64_t amount =
            [@[@(-1010000), @(-10010000), @(54000000), @(-82990000), @(-10010000), @(93000000)][i] longLongValue];

        txData.type = (amount >= 0) ? BRAWTransactionTypeReceive : BRAWTransactionTypeSent;
        txData.amountText = [manager stringForDashAmount:amount];
        txData.amountTextInLocalCurrency = [manager localCurrencyStringForDashAmount:amount];
        tx.timestamp = [NSDate timeIntervalSinceReferenceDate] - i * 100000;
        txData.dateText = tx.dateText;
        [transactionListData addObject:txData];
    }
#endif

    return transactionListData;
}

@end
