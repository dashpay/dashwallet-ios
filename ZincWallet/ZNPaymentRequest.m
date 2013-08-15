//
//  ZNPaymentRequest.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/9/13.
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

#import "ZNPaymentRequest.h"
#import "NSString+Base58.h"

@implementation ZNPaymentRequest

+ (instancetype)requestWithString:(NSString *)string
{
    return [[self alloc] initWithString:string];
}

+ (instancetype)requestWithURL:(NSURL *)url
{
    return [[self alloc] initWithURL:url];
}

+ (instancetype)requestWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

- (instancetype)initWithString:(NSString *)string
{
    return [self initWithData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (instancetype)initWithURL:(NSURL *)url
{
    return [self initWithData:[url.absoluteString dataUsingEncoding:NSUTF8StringEncoding]];
}


- (instancetype)initWithData:(NSData *)data
{
    if (! (self = [self init])) return nil;

    self.data = data;
    
    return self;
}

//XXX this should also handle bitcoin payment messages per: https://gist.github.com/gavinandresen/4120476
//XXX also should offer to sweep balance into wallet if it's a private key not already in wallet.
- (void)setData:(NSData *)data
{
    self.paymentAddress = nil;
    self.label = nil;
    self.message = nil;
    self.amount = 0;

    if (! data) return;

    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:s];
    
    if (! url || ! url.scheme) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"bitcoin://%@", s]];
    }
    else if (! url.host && url.resourceSpecifier) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", url.scheme, url.resourceSpecifier]];
    }
    
    self.paymentAddress = url.host;
    
    [[url.query componentsSeparatedByString:@"&"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSArray *pair = [obj componentsSeparatedByString:@"="];
        if (pair.count != 2) return;
        
        if ([pair[0] isEqual:@"amount"]) self.amount = ([pair[1] doubleValue] + DBL_EPSILON)*SATOSHIS;
        else if ([pair[0] isEqual:@"label"])
            self.label = [[pair[1] stringByReplacingOccurrencesOfString:@"+" withString:@"%20"]
                          stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        else if ([pair[0] isEqual:@"message"])
            self.message = [[pair[1] stringByReplacingOccurrencesOfString:@"+" withString:@"%20"]
                            stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }];
}

- (void)setPaymentAddress:(NSString *)paymentAddress
{
    _paymentAddress = [paymentAddress isValidBitcoinAddress] ? paymentAddress : nil;
}

- (NSData *)data
{
    if (! self.paymentAddress) return nil;

    NSMutableString *s = [NSMutableString stringWithFormat:@"bitcoin://%@", self.paymentAddress];
    NSMutableArray *q = [NSMutableArray array];
    
    if (self.amount > 0) {
        [q addObject:[NSString stringWithFormat:@"amount=%.16g", (double)self.amount/SATOSHIS]];
    }
    
    if (self.label.length) {
        [q addObject:[NSString stringWithFormat:@"label=%@",
         [self.label stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    }
    
    if (self.message.length) {
        [q addObject:[NSString stringWithFormat:@"message=%@",
         [self.message stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    }
    
    if (q.count) {
        [s appendString:@"?"];
        [s appendString:[q componentsJoinedByString:@"&"]];
    }
    
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)isValid
{
    if (! self.paymentAddress) return NO;
    
    // XXX validate X.509 certificate, hopefully offline

    return YES;
}

@end
