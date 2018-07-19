//
//  DSTransaction+Utils.m
//  DashSync
//
//  Created by Henry on 10/27/15.
//  Copyright (c) 2015 Aaron Voisine <voisine@gmail.com>
//  Updated by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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

#import "DSTransaction+Utils.h"
#import "DSWalletManager.h"
#import "DSChainPeerManager.h"
#import "DSChainManager.h"
#import "DSChain.h"
#import "DSAccount.h"

@implementation DSTransaction (Utils)

- (DSTransactionType)transactionTypeInAccount:(DSAccount*)account
{
    uint64_t received = [account amountReceivedFromTransaction:self],
             sent = [account amountSentByTransaction:self];
    uint32_t blockHeight = self.blockHeight;
    uint32_t confirms = ([self lastBlockHeight] > blockHeight) ? 0 : (blockHeight - [self lastBlockHeight]) + 1;

    if (confirms == 0 && ! [account transactionIsValid:self]) {
        return DSTransactionTypeInvalid;
    }
    
    if (sent > 0 && received == sent) {
        return DSTransactionTypeMove;
    }
    else if (sent > 0) {
        return DSTransactionTypeSent;
    }
    else return DSTransactionTypeReceive;
}

- (DSTransactionType)transactionTypeInWallet:(DSWallet*)wallet
{
    uint64_t received = [wallet amountReceivedFromTransaction:self],
    sent = [wallet amountSentByTransaction:self];
    uint32_t blockHeight = self.blockHeight;
    uint32_t confirms = ([self lastBlockHeight] > blockHeight) ? 0 : (blockHeight - [self lastBlockHeight]) + 1;
    
    if (confirms == 0 && ! [wallet transactionIsValid:self]) {
        return DSTransactionTypeInvalid;
    }
    
    if (sent > 0 && received == sent) {
        return DSTransactionTypeMove;
    }
    else if (sent > 0) {
        return DSTransactionTypeSent;
    }
    else return DSTransactionTypeReceive;
}

- (NSString*)localCurrencyTextForAmountReceivedInAccount:(DSAccount*)account
{
    DSWalletManager *manager = [DSWalletManager sharedInstance];
    uint64_t received = [account amountReceivedFromTransaction:self],

    sent = [account amountSentByTransaction:self];

    if (sent > 0 && received == sent) {
        return [NSString stringWithFormat:@"(%@)", [manager localCurrencyStringForDashAmount:sent]];
    }
    else if (sent > 0) {
        return [NSString stringWithFormat:@"(%@)", [manager localCurrencyStringForDashAmount:received - sent]];
    }
    else return [NSString stringWithFormat:@"(%@)", [manager localCurrencyStringForDashAmount:received]];
}

- (NSString*)amountTextReceivedInAccount:(DSAccount*)account
{
    DSWalletManager *manager = [DSWalletManager sharedInstance];
    uint64_t received = [account amountReceivedFromTransaction:self],

    sent = [account amountSentByTransaction:self];

    if (sent > 0 && received == sent) {
        return [manager stringForDashAmount:sent];
    }
    else if (sent > 0) {
        return [manager stringForDashAmount:received - sent];
    }
    else return [manager stringForDashAmount:received];
}

- (uint32_t)lastBlockHeight
{
    static uint32_t height = 0;
    uint32_t h = self.chain.lastBlockHeight;
    
    if (h > height) height = h;
    return height;
}

- (NSString *)dateText
{
    NSDateFormatter *df = [NSDateFormatter new];
    
    df.dateFormat = dateFormat(@"Mdja");

    NSTimeInterval t = (self.timestamp > 1) ? self.timestamp :
                       [self.chain timestampForBlockHeight:self.blockHeight] - 5*60;
    NSString *date = [df stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:t]];

    date = [date stringByReplacingOccurrencesOfString:@"am" withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"pm" withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"AM" withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"PM" withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"a.m." withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"p.m." withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"A.M." withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"P.M." withString:@"p"];
    return date;
}

- (NSDate *)transactionDate
{
    return [NSDate dateWithTimeIntervalSinceReferenceDate:self.timestamp];
}

static NSString *dateFormat(NSString *template)
{
    NSString *format = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:[NSLocale currentLocale]];
    
    format = [format stringByReplacingOccurrencesOfString:@", " withString:@" "];
    format = [format stringByReplacingOccurrencesOfString:@" a" withString:@"a"];
    format = [format stringByReplacingOccurrencesOfString:@"hh" withString:@"h"];
    format = [format stringByReplacingOccurrencesOfString:@" ha" withString:@"@ha"];
    format = [format stringByReplacingOccurrencesOfString:@"HH" withString:@"H"];
    format = [format stringByReplacingOccurrencesOfString:@"H '" withString:@"H'"];
    format = [format stringByReplacingOccurrencesOfString:@"H " withString:@"H'h' "];
    format = [format stringByReplacingOccurrencesOfString:@"H" withString:@"H'h'"
              options:NSBackwardsSearch|NSAnchoredSearch range:NSMakeRange(0, format.length)];
    return format;
}

@end
