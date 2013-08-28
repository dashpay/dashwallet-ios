//
//  ZNUnspentOutputEntity.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/22/13.
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

#import "ZNUnspentOutputEntity.h"
#import "ZNTransactionEntity.h"
#import "ZNTxOutputEntity.h"
#import "NSString+Base58.h"
#import "NSManagedObject+Utils.h"
#import "NSMutableData+Bitcoin.h"

@implementation ZNUnspentOutputEntity

@dynamic txHash;
@dynamic script;
@dynamic confirmations;

+ (instancetype)entityWithJSON:(NSDictionary *)JSON
{
    ZNUnspentOutputEntity *e = [super entityWithJSON:JSON];
    
    if (! e) return nil;
        
    if ([JSON[@"tx_hash"] isKindOfClass:[NSString class]]) e.txHash = [JSON[@"tx_hash"] hexToData];
    if ([JSON[@"tx_output_n"] isKindOfClass:[NSNumber class]]) e.n = [JSON[@"tx_output_n"] intValue];
    if ([JSON[@"script"] isKindOfClass:[NSString class]]) e.script = [JSON[@"script"] hexToData];
    if ([JSON[@"confirmations"] isKindOfClass:[NSNumber class]]) e.confirmations = [JSON[@"confirmations"] intValue];
    e.address = [NSString addressWithScript:e.script];
    
    return e;
}

+ (instancetype)entityWithTxOutput:(ZNTxOutputEntity *)output
{
    ZNUnspentOutputEntity *e = [self managedObject];
    NSMutableData *script = [NSMutableData data];
    
    e.address = output.address;
    e.n = output.n;
    e.txIndex = output.txIndex;
    e.value = output.value;
    e.txHash = output.transaction.txHash;
    e.confirmations = 0;
    [script appendScriptPubKeyForAddress:e.address];
    e.script = script;
    
    return e;
}

@end
