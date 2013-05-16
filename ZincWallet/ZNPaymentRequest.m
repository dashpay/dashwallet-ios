//
//  ZNPaymentRequest.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/9/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNPaymentRequest.h"
#import "ZNWallet.h"

@implementation ZNPaymentRequest

+ (id)requestWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

- (id)initWithData:(NSData *)data
{
    if (! (self = [self init])) return nil;

    self.data = data;
    
    return self;
}

// this should also handle bitcoin payment messages per: https://gist.github.com/gavinandresen/4120476
- (void)setData:(NSData *)data
{
    NSURL *url = [NSURL URLWithString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
    
    if (! url.host && url.resourceSpecifier) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", url.scheme, url.resourceSpecifier]];
    }
        
    self.paymentAddress = url.host;
    
    [[url.query componentsSeparatedByString:@"&"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSArray *pair = [obj componentsSeparatedByString:@"="];
        if (pair.count != 2) return;
        
        if ([pair[0] isEqual:@"amount"]) self.amount = [pair[1] doubleValue];
        else if ([pair[0] isEqual:@"label"])
            self.label = [pair[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        else if ([pair[0] isEqual:@"message"])
            self.message = [pair[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }];
}

- (NSData *)data
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"bitcoin:%@?amount=%.17g", self.paymentAddress,
                          self.amount];
    
    if (self.label.length) {
        [s appendFormat:@"&label=%@", [self.label stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    
    if (self.message.length) {
        [s appendFormat:@"&message=%@", [self.message stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)signedTransaction
{
    //XXX actually sign a transaction here
    return [[[ZNWallet singleton] transactionFor:self.amount to:self.paymentAddress]
            dataUsingEncoding:NSUTF8StringEncoding];

//    return [[[[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding] stringByAppendingString:@" - X"]
//            dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)isValid
{
    // XXX validate X.509 certificate, hopefully offline

    return true;
}

@end
