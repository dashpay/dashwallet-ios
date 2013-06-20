//
//  ZNPaymentRequest.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/9/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNPaymentRequest.h"
#import "NSString+Base58.h"

@implementation ZNPaymentRequest

+ (id)requestWithString:(NSString *)string
{
    return [[self alloc] initWithString:string];
}

+ (id)requestWithURL:(NSURL *)url
{
    return [[self alloc] initWithURL:url];
}

+ (id)requestWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

- (id)initWithString:(NSString *)string
{
    return [self initWithData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (id)initWithURL:(NSURL *)url
{
    return [self initWithData:[url.absoluteString dataUsingEncoding:NSUTF8StringEncoding]];
}


- (id)initWithData:(NSData *)data
{
    if (! (self = [self init])) return nil;

    self.data = data;
    
    return self;
}

//XXX this should also handle bitcoin payment messages per: https://gist.github.com/gavinandresen/4120476
//XXX also should offer to sweep balance into wallet if it's a private key not already in wallet.
- (void)setData:(NSData *)data
{
    if (! data) {
        self.paymentAddress = nil;
        self.label = nil;
        self.message = nil;
        self.amount = 0;
        return;
    }

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
        
        if ([pair[0] isEqual:@"amount"]) self.amount = [pair[1] doubleValue]*SATOSHIS;
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
