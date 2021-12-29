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
#import "DSWatchTransactionDataObject.h"
#import "DWAppGroupConstants.h"
#import "DWEnvironment.h"
#import "UIImage+Utils.h"

static CGSize const QR_SIZE = {240.0, 240.0};
static CGSize const HOLE_SIZE = {58.0, 58.0};
static CGSize const LOGO_SIZE = {54.0, 54.0};

@interface DWPhoneWCSessionManager () <WCSessionDelegate>

@property WCSession *session;
@property id balanceObserver, syncFinishedObserver, syncFailedObserver;

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
                [[NSNotificationCenter defaultCenter] addObserverForName:DSWalletBalanceDidChangeNotification
                                                                  object:nil
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *_Nonnull note) {
                                                                  if ([DWEnvironment sharedInstance].currentChainManager.combinedSyncProgress == 1.0)
                                                                      [self sendApplicationContext];
                                                              }];

            self.syncFinishedObserver =
                [[NSNotificationCenter defaultCenter] addObserverForName:DSChainManagerSyncFinishedNotification
                                                                  object:nil
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *_Nonnull note) {
                                                                  [self sendApplicationContext];
                                                              }];

            self.syncFailedObserver =
                [[NSNotificationCenter defaultCenter] addObserverForName:DSChainManagerSyncFailedNotification
                                                                  object:nil
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *_Nonnull note) {
                                                                  [self sendApplicationContext];
                                                              }];
        }
    }

    return self;
}

- (void)dealloc {
    if (self.balanceObserver)
        [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.syncFinishedObserver)
        [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver)
        [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
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
                // sync with peer whenever there is a request coming, so we can update watch side.
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication].delegate
                                              application:[UIApplication sharedApplication]
                        performFetchWithCompletionHandler:^(UIBackgroundFetchResult result) {
                            NSLog(@"watch triggered background fetch completed with result %lu", (unsigned long)result);
                        }];
                });
                break;

            case AWSessionRquestDataTypeQRCodeBits: {
                DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
                DSPaymentRequest *req = [DSPaymentRequest requestWithString:account.receiveAddress onChain:[DWEnvironment sharedInstance].currentChain];

                req.amount = [message[AW_SESSION_QR_CODE_BITS_KEY] integerValue];
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
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSArray *transactions = account.recentTransactions;
    UIImage *qrCodeImage = self.qrCode;
    BRAppleWatchData *appleWatchData = [[BRAppleWatchData alloc] init];

    appleWatchData.balance = [priceManager stringForDashAmount:account.balance];
    appleWatchData.balanceInLocalCurrency = [priceManager localCurrencyStringForDashAmount:account.balance];
#if SNAPSHOT
    appleWatchData.balance = [priceManager stringForDashAmount:42980000];
    appleWatchData.balanceInLocalCurrency = [priceManager localCurrencyStringForDashAmount:42980000];
#endif
    appleWatchData.receiveMoneyAddress = account.receiveAddress;
    appleWatchData.transactions = [self recentTransactionListFromTransactions:transactions];
    appleWatchData.receiveMoneyQRCodeImage = qrCodeImage;
    appleWatchData.hasWallet = !!account; // if there is no account there is no wallet

    if (transactions.count > 0) {
        appleWatchData.lastestTransction = [self lastTransactionStringFromTransaction:transactions[0]];
    }

    return appleWatchData;
}

- (nullable NSString *)lastTransactionStringFromTransaction:(DSTransaction *)transaction {
    if (transaction) {
        NSString *timeDescriptionString = [self timeDescriptionStringFrom:transaction.transactionDate];
        NSString *transactionTypeString;

        if (timeDescriptionString == nil) {
            timeDescriptionString = transaction.dateText;
        }

        switch ([transaction transactionStatusInAccount:[DWEnvironment sharedInstance].currentAccount]) {
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
        NSString *amountText = [transaction amountTextReceivedInAccount:[DWEnvironment sharedInstance].currentAccount];
        NSString *localCurrencyText = [transaction localCurrencyTextForAmountReceivedInAccount:[DWEnvironment sharedInstance].currentAccount];
        return [NSString
            stringWithFormat:@"%@ %@ %@ , %@", transactionTypeString,
                             [amountText stringByReplacingOccurrencesOfString:@"-"
                                                                   withString:@""],
                             (localCurrencyText.length > 2)
                                 ? localCurrencyText
                                 : @"",
                             timeDescriptionString];
    }

    return nil;
}

- (NSString *)timeDescriptionStringFrom:(NSDate *)date {
    if (date) {
        NSDate *now = [NSDate date];
        NSTimeInterval secondsSinceTransaction = [now timeIntervalSinceDate:date];
        return [NSString waitTimeFromNow:secondsSinceTransaction];
    }

    return nil;
}

- (nullable UIImage *)qrCode {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    if (!account) {
        return nil;
    }

    NSData *req = [DSPaymentRequest requestWithString:account.receiveAddress onChain:account.wallet.chain].data;
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

- (NSArray *)recentTransactionListFromTransactions:(NSArray *)transactions {
    NSMutableArray *transactionListData = [[NSMutableArray alloc] init];

    for (DSTransaction *transaction in transactions) {
        DSWatchTransactionDataObject *dataObject = [[DSWatchTransactionDataObject alloc] initWithTransaction:transaction];
        if (dataObject) {
            BRAppleWatchTransactionData *transactionData = [BRAppleWatchTransactionData appleWatchTransactionDataFrom:dataObject];
            [transactionListData addObject:transactionData];
        }
    }

#if SNAPSHOT
//    DSWalletManager *manager = [DSWalletManager sharedInstance];
//
//    [transactionListData removeAllObjects];
//
//    for (int i = 0; i < 6; i++) {
//        DSTransaction *tx = [DSTransaction new];
//        BRAppleWatchTransactionData *txData = [BRAppleWatchTransactionData new];
//        int64_t amount =
//            [@[@(-1010000), @(-10010000), @(54000000), @(-82990000), @(-10010000), @(93000000)][i] longLongValue];
//
//        txData.type = (amount >= 0) ? BRAWTransactionTypeReceive : BRAWTransactionTypeSent;
//        txData.amountText = [manager stringForDashAmount:amount];
//        txData.amountTextInLocalCurrency = [manager localCurrencyStringForDashAmount:amount];
//        tx.timestamp = [NSDate timeIntervalSince1970] - i * 100000;
//        txData.dateText = tx.dateText;
//        [transactionListData addObject:txData];
//    }
#endif

    return [transactionListData copy];
}

@end
