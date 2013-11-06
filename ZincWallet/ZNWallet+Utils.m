//
//  ZNWallet+Utils.m
//  ZincWallet
//
//  Created by Aaron Voisine on 9/23/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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

#import "ZNWallet+Utils.h"
#import "ZNTransaction.h"
#import "ZNKey.h"
#import "ZNUnspentOutputEntity.h"
#import "ZNAddressEntity.h"
#import "NSManagedObject+Utils.h"
#import "AFNetworking.h"

#define LOCAL_CURRENCY_SYMBOL_KEY @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY   @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY  @"LOCAL_CURRENCY_PRICE"

#define CURRENCY_SIGN @"\xC2\xA4" // generic currency sign (utf-8)

@implementation ZNWallet (Utils)

#pragma mark - string helpers

- (int64_t)amountForString:(NSString *)string
{
    return ([[self.format numberFromString:string] doubleValue] + DBL_EPSILON)*
    pow(10.0, self.format.maximumFractionDigits);
}

- (NSString *)stringForAmount:(int64_t)amount
{
    NSUInteger min = self.format.minimumFractionDigits;
    
    if (amount == 0) {
        self.format.minimumFractionDigits =
        self.format.maximumFractionDigits > 4 ? 4 : self.format.maximumFractionDigits;
    }
    
    NSString *r = [self.format stringFromNumber:@(amount/pow(10.0, self.format.maximumFractionDigits))];
    
    self.format.minimumFractionDigits = min;
    
    return r;
}

- (NSString *)localCurrencyStringForAmount:(int64_t)amount
{
    static NSNumberFormatter *format = nil;
    
    if (! format) {
        format = [NSNumberFormatter new];
        format.lenient = YES;
        format.numberStyle = NSNumberFormatterCurrencyStyle;
        format.negativeFormat =
            [format.positiveFormat stringByReplacingOccurrencesOfString:CURRENCY_SIGN withString:CURRENCY_SIGN @"-"];
    }

    if (! amount) return [format stringFromNumber:@(0)];
    
    NSString *symbol = [[NSUserDefaults standardUserDefaults] stringForKey:LOCAL_CURRENCY_SYMBOL_KEY];
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:LOCAL_CURRENCY_CODE_KEY];
    double price = [[NSUserDefaults standardUserDefaults] doubleForKey:LOCAL_CURRENCY_PRICE_KEY];
    
    if (! symbol.length || price <= DBL_EPSILON) return nil;
    
    format.currencySymbol = symbol;
    format.currencyCode = code;
    
    NSString *ret = [format stringFromNumber:@(amount/price)];
    
    // if the amount is too small to be represented in local currency (but is != 0) then return a string like "<$0.01"
    if (amount != 0 && [[format numberFromString:ret] isEqual:@(0.0)]) {
        ret = [@"<" stringByAppendingString:[format stringFromNumber:@(1.0/pow(10.0, format.maximumFractionDigits))]];
    }
    
    return ret;
}

#pragma mark - ZNTransaction helpers

// returns the estimated time in seconds until the transaction will be processed without a fee.
// this is based on the default satoshi client settings, but on the real network it's way off. in testing, a 0.01btc
// transaction with a 90 day time until free was confirmed in under an hour by Eligius pool.
- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction
{
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger currentHeight = self.lastBlockHeight, idx = 0;
    
    if (! currentHeight) return DBL_MAX;
    
    // get the heights (which block in the blockchain it's in) of all the transaction inputs
    for (NSData *hash in transaction.inputHashes) {
        ZNUnspentOutputEntity *o = [ZNUnspentOutputEntity objectsMatching:@"txHash == %@ && n == %d", hash,
                                    [transaction.inputIndexes[idx++] intValue]].lastObject;
        
        if (! o) break;
        [amounts addObject:@(o.value)];
        [heights addObject:@(currentHeight - o.confirmations)];
    }
    
    NSUInteger height = [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
    
    if (height == TX_UNCONFIRMED) return DBL_MAX;
    
    currentHeight = [self estimatedCurrentBlockHeight];
    
    return height > currentHeight + 1 ? (height - currentHeight)*600 : 0;
}

// retuns the total amount tendered in the trasaction (total unspent outputs consumed, change included)
- (uint64_t)transactionAmount:(ZNTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger idx = 0;
    
    for (NSData *hash in transaction.inputHashes) {
        ZNUnspentOutputEntity *o = [ZNUnspentOutputEntity objectsMatching:@"txHash == %@ && n == %d", hash,
                                    [transaction.inputIndexes[idx++] intValue]].lastObject;
        
        if (! o) {
            amount = 0;
            break;
        }
        else amount += o.value;
    }
    
    return amount;
}

// returns the transaction fee for the given transaction
- (uint64_t)transactionFee:(ZNTransaction *)transaction
{
    uint64_t amount = [self transactionAmount:transaction];
    
    if (amount == 0) return UINT64_MAX;
    
    for (NSNumber *amt in transaction.outputAmounts) {
        amount -= amt.unsignedLongLongValue;
    }
    
    return amount;
}

// returns the amount that the given transaction returns to a change address
- (uint64_t)transactionChange:(ZNTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger idx = 0;
    
    for (NSString *address in transaction.outputAddresses) {
        if ([self containsAddress:address]) amount += [transaction.outputAmounts[idx] unsignedLongLongValue];
        idx++;
    }
    
    return amount;
}

// returns the first trasnaction output address not contained in the wallet
- (NSString *)transactionTo:(ZNTransaction *)transaction
{
    NSString *address = nil;
    
    for (NSString *addr in transaction.outputAddresses) {
        if ([self containsAddress:addr]) continue;
        address = addr;
        break;
    }
    
    return address;
}

@end
