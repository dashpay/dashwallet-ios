//
//  ZNPaymentRequest.h
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

#import <Foundation/Foundation.h>

@class ZNPaymentProtocolRequest;

// BIP21 bitcoin URI object https://github.com/bitcoin/bips/blob/master/bip-0021.mediawiki
@interface ZNPaymentRequest : NSObject

@property (nonatomic, strong) NSString *paymentAddress;
@property (nonatomic, strong) NSString *label;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, strong) NSURL *r; // BIP72 URL: https://github.com/bitcoin/bips/blob/master/bip-0072.mediawiki
@property (nonatomic, strong) NSData *data;
@property (nonatomic, readonly, getter=isValid) BOOL valid;

+ (instancetype)requestWithData:(NSData *)data;
+ (instancetype)requestWithString:(NSString *)string;
+ (instancetype)requestWithURL:(NSURL *)url;

- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithURL:(NSURL *)url;

// fetches a BIP70 request over HTTP and calls completion block
// https://github.com/bitcoin/bips/blob/master/bip-0070.mediawiki
- (void)fetchOnCompletion:(void (^)(NSError *error, ZNPaymentProtocolRequest *req))completion;

@end
