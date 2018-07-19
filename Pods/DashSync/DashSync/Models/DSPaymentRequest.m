//
//  DSPaymentRequest.m
//  DashSync
//
//  Created by Aaron Voisine on 5/9/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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

#import "DSPaymentRequest.h"
#import "DSPaymentProtocol.h"
#import "NSString+Bitcoin.h"
#import "NSString+Dash.h"
#import "NSMutableData+Dash.h"
#import "DSChain.h"

@interface DSPaymentRequest()

@property(nonatomic,strong) DSChain * chain;

@end

// BIP21 bitcoin URI object https://github.com/bitcoin/bips/blob/master/bip-0021.mediawiki
@implementation DSPaymentRequest

+ (instancetype)requestWithString:(NSString *)string onChain:(DSChain*)chain
{
    return [[self alloc] initWithString:string onChain:chain];
}

+ (instancetype)requestWithData:(NSData *)data onChain:(DSChain*)chain
{
    return [[self alloc] initWithData:data onChain:chain];
}

+ (instancetype)requestWithURL:(NSURL *)url onChain:(DSChain*)chain
{
    return [[self alloc] initWithURL:url onChain:chain];
}

- (instancetype)initWithString:(NSString *)string onChain:(DSChain*)chain
{
    if (! (self = [super init])) return nil;
    self.chain = chain;
    self.string = string;
    return self;
}

- (instancetype)initWithData:(NSData *)data onChain:(DSChain*)chain
{
    return [self initWithString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] onChain:chain];
}

- (instancetype)initWithURL:(NSURL *)url onChain:(DSChain*)chain
{
    return [self initWithString:url.absoluteString onChain:chain];
}

- (void)setString:(NSString *)string
{
    self.scheme = nil;
    self.paymentAddress = nil;
    self.label = nil;
    self.message = nil;
    self.amount = 0;
    self.callbackScheme = nil;
    _wantsInstant = FALSE;
    _instantValueRequired = FALSE;
    self.r = nil;

    if (string.length == 0) return;

    NSString *s = [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                   stringByReplacingOccurrencesOfString:@" " withString:@"%20"];
    NSURL *url = [NSURL URLWithString:s];
    
    if (! url || ! url.scheme) {
        if ([s isValidDashAddressOnChain:self.chain] || [s isValidDashPrivateKeyOnChain:self.chain] || [s isValidDashBIP38Key]) {
            url = [NSURL URLWithString:[NSString stringWithFormat:@"dash://%@", s]];
            self.scheme = @"dash";
        } else if ([s isValidBitcoinAddressOnChain:self.chain] || [s isValidBitcoinPrivateKeyOnChain:self.chain]) {
            url = [NSURL URLWithString:[NSString stringWithFormat:@"bitcoin://%@", s]];
            self.scheme = @"bitcoin";
        }
    }
    else if (! url.host && url.resourceSpecifier) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", url.scheme, url.resourceSpecifier]];
        self.scheme = url.scheme;
    } else if (url.scheme) {
        self.scheme = url.scheme;
    } else {
        self.scheme = @"dash";
    }
    
    if ([url.scheme isEqualToString:@"dash"] || [url.scheme isEqualToString:@"bitcoin"]) {
        self.paymentAddress = url.host;
    
        //TODO: correctly handle unknown but required url arguments (by reporting the request invalid)
        for (NSString *arg in [url.query componentsSeparatedByString:@"&"]) {
            NSArray *pair = [arg componentsSeparatedByString:@"="]; // if more than one '=', then pair[1] != value

            if (pair.count < 2) continue;
        
            NSString *value = [[[arg substringFromIndex:[pair[0] length] + 1]
                                stringByReplacingOccurrencesOfString:@"+" withString:@" "]
                               stringByRemovingPercentEncoding];
            
            BOOL require = FALSE;
            NSString * key = pair[0];
            if ([key hasPrefix:@"req-"] && key.length > 4) {
                key = [key substringFromIndex:4];
                require = TRUE;
            }

            if ([key isEqual:@"amount"]) {
                NSDecimal dec, amount;

                if ([[NSScanner scannerWithString:value] scanDecimal:&dec]) {
                    NSDecimalMultiplyByPowerOf10(&amount, &dec, 8, NSRoundUp);
                    self.amount = [NSDecimalNumber decimalNumberWithDecimal:amount].unsignedLongLongValue;
                }
                if (require)
                    _amountValueImmutable = TRUE;
            }
            else if ([key isEqual:@"label"]) {
                self.label = value;
            }
            else if ([key isEqual:@"sender"]) {
                self.callbackScheme = value;
            }
            else if ([key isEqual:@"message"]) {
                self.message = value;
            }
            else if ([[key lowercaseString] isEqual:@"is"]) {
                if ([value  isEqual: @"1"])
                    _wantsInstant = TRUE;
                if (require)
                    _instantValueRequired = TRUE;
            }
            else if ([key isEqual:@"r"]) {
                self.r = value;
            }
            else if ([key isEqual:@"currency"]) {
                self.currency = value;
            }
            else if ([key isEqual:@"local"]) {
                self.currencyAmount = value;
            }
        }
    }
    else if (url) self.r = s; // BIP73 url: https://github.com/bitcoin/bips/blob/master/bip-0073.mediawiki
}

- (NSString *)string
{
    if (! ([self.scheme isEqual:@"bitcoin"] || [self.scheme isEqual:@"dash"])) return self.r;

    NSMutableString *s = [NSMutableString stringWithFormat:@"%@:",self.scheme];
    NSMutableArray *q = [NSMutableArray array];
    NSMutableCharacterSet *charset = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    
    [charset removeCharactersInString:@"&="];
    if (self.paymentAddress) [s appendString:self.paymentAddress];
    
    if (self.amount > 0) {
        [q addObject:[@"amount=" stringByAppendingString:[(id)[NSDecimalNumber numberWithUnsignedLongLong:self.amount]
                                                          decimalNumberByMultiplyingByPowerOf10:-8].stringValue]];
    }

    if (self.label.length > 0) {
        [q addObject:[@"label=" stringByAppendingString:[self.label
         stringByAddingPercentEncodingWithAllowedCharacters:charset]]];
    }
    
    if (self.message.length > 0) {
        [q addObject:[@"message=" stringByAppendingString:[self.message
         stringByAddingPercentEncodingWithAllowedCharacters:charset]]];
    }

    if (self.r.length > 0) {
        [q addObject:[@"r=" stringByAppendingString:[self.r
         stringByAddingPercentEncodingWithAllowedCharacters:charset]]];
    }
    
    if (self.wantsInstant) {
        [q addObject:@"IS=1"];
    }
    
    if (self.currency.length > 0) {
        [q addObject:[@"currency=" stringByAppendingString:[self.currency stringByAddingPercentEncodingWithAllowedCharacters:charset]]];
    }

    if (self.currencyAmount.length > 0) {
        [q addObject:[@"local=" stringByAppendingString:[self.currencyAmount stringByAddingPercentEncodingWithAllowedCharacters:charset]]];
    }

    if (q.count > 0) {
        [s appendString:@"?"];
        [s appendString:[q componentsJoinedByString:@"&"]];
    }
    
    return s;
}

- (void)setData:(NSData *)data
{
    self.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSData *)data
{
    return [self.string dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)setUrl:(NSURL *)url
{
    self.string = url.absoluteString;
}

- (NSURL *)url
{
    return [NSURL URLWithString:self.string];
}

- (BOOL)isValid
{
    if ([self.scheme isEqualToString:@"dash"]) {
        BOOL valid = ([self.paymentAddress isValidDashAddressOnChain:self.chain] || (self.r && [NSURL URLWithString:self.r])) ? YES : NO;
        if (!valid) {
            NSLog(@"Not a valid dash request");
        }
        return valid;
    } else if ([self.scheme isEqualToString:@"bitcoin"]) {
        BOOL valid = ([self.paymentAddress isValidBitcoinAddressOnChain:self.chain] || (self.r && [NSURL URLWithString:self.r])) ? YES : NO;
        if (!valid) {
            NSLog(@"Not a valid bitcoin request");
            
        }
        return valid;
    } else {
        return NO;
    }
}

// receiver converted to BIP70 request object
- (DSPaymentProtocolRequest *)protocolRequest
{
    NSData *name = [self.label dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *script = [NSMutableData data];
    if ([self.paymentAddress isValidDashAddressOnChain:self.chain]) {
        [script appendScriptPubKeyForAddress:self.paymentAddress forChain:self.chain];
    } else if ([self.paymentAddress isValidBitcoinAddressOnChain:self.chain]) {
        [script appendBitcoinScriptPubKeyForAddress:self.paymentAddress forChain:self.chain];
    }
    if (script.length == 0) return nil;
    
    DSPaymentProtocolDetails *details =
        [[DSPaymentProtocolDetails alloc] initWithOutputAmounts:@[@(self.amount)]
         outputScripts:@[script] time:0 expires:0 memo:self.message paymentURL:nil merchantData:nil onChain:self.chain];
    DSPaymentProtocolRequest *request =
        [[DSPaymentProtocolRequest alloc] initWithVersion:1 pkiType:@"none" certs:(name ? @[name] : nil) details:details
         signature:nil onChain:self.chain callbackScheme:self.callbackScheme];
    
    return request;
}

// fetches the request over HTTP and calls completion block
+ (void)fetch:(NSString *)url scheme:(NSString*)scheme onChain:(DSChain*)chain timeout:(NSTimeInterval)timeout
completion:(void (^)(DSPaymentProtocolRequest *req, NSError *error))completion
{
    if (! completion) return;

    NSURL *u = [NSURL URLWithString:url];
    NSMutableURLRequest *req = (u) ? [NSMutableURLRequest requestWithURL:u
                                      cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout] : nil;

    [req setValue:[NSString stringWithFormat:@"application/%@-paymentrequest",scheme] forHTTPHeaderField:@"Accept"];
//  [req addValue:@"text/uri-list" forHTTPHeaderField:@"Accept"]; // breaks some BIP72 implementations, notably bitpay's

    if (! req) {
        completion(nil, [NSError errorWithDomain:@"DashWallet" code:417
                         userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"bad payment request URL", nil)}]);
        return;
    }

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
    
        DSPaymentProtocolRequest *request = nil;
        
        if ([response.MIMEType.lowercaseString isEqual:[NSString stringWithFormat:@"application/%@-paymentrequest",scheme]] && data.length <= 50000) {
            request = [DSPaymentProtocolRequest requestWithData:data onChain:chain];
        }
        else if ([response.MIMEType.lowercaseString isEqual:@"text/uri-list"] && data.length <= 50000) {
            for (NSString *url in [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                                   componentsSeparatedByString:@"\n"]) {
                if ([url hasPrefix:@"#"]) continue; // skip comments
                request = [DSPaymentRequest requestWithString:url onChain:chain].protocolRequest; // use first url and ignore the rest
                break;
            }
        }
        
        if (! request) {
            NSLog(@"unexpected response from %@:\n%@", req.URL.host,
                  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            completion(nil, [NSError errorWithDomain:@"DashWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil),
                              req.URL.host]}]);
        }
        else if (![request.details.chain isActive]) {
            completion(nil, [NSError errorWithDomain:@"DashWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             [NSString stringWithFormat:NSLocalizedString(@"requested network \"%@\" not currently in use",
                                                                          nil), request.details.chain.networkName]}]);
        }
        else completion(request, nil);
    }] resume];
}

+ (void)postPayment:(DSPaymentProtocolPayment *)payment scheme:(NSString*)scheme to:(NSString *)paymentURL onChain:(DSChain*)chain
            timeout:(NSTimeInterval)timeout completion:(void (^)(DSPaymentProtocolACK *ack, NSError *error))completion
{
    NSURL *u = [NSURL URLWithString:paymentURL];
    NSMutableURLRequest *req = (u) ? [NSMutableURLRequest requestWithURL:u
                                      cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout] : nil;
    
    if (! req) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"DashWallet" code:417
                             userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"bad payment URL", nil)}]);
        }
        
        return;
    }

    [req setValue:[NSString stringWithFormat:@"application/%@-payment",scheme] forHTTPHeaderField:@"Content-Type"];
    [req addValue:[NSString stringWithFormat:@"application/%@-paymentack",scheme] forHTTPHeaderField:@"Accept"];
    req.HTTPMethod = @"POST";
    req.HTTPBody = payment.data;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        
        DSPaymentProtocolACK *ack = nil;
        
        if ([response.MIMEType.lowercaseString isEqual:[NSString stringWithFormat:@"application/%@-paymentack",scheme]] && data.length <= 50000) {
            ack = [DSPaymentProtocolACK ackWithData:data onChain:chain];
        }

        if (! ack) {
            NSLog(@"unexpected response from %@:\n%@", req.URL.host,
                  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            if (completion) {
                completion(nil, [NSError errorWithDomain:@"DashWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                                 [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil),
                                  req.URL.host]}]);
            }
        }
        else if (completion) completion(ack, nil);
     }] resume];
}

@end
